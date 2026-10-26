"""Export a trained run to ONNX for the app, quantize it, and check it still agrees.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/export.py mobilenet_v3_large

The exported graph takes the work off the phone:
  input   image   float32 [1, 3, 224, 224], RGB in 0..1 (already resized + centre-cropped)
  output  probs   float32 [1, 5]            softmax over CLASSES
  output  cams    float32 [1, 5, 7, 7]      raw class activation maps, one per class

For the heatmap the app takes cams[0, top class], clamps negatives to 0,
divides by the max, and stretches it over the photo.

Writes ml/export/<run>/: tanim_fp32.onnx, tanim_int8.onnx, labels.json, export_report.json.
"""

import argparse
import json
import random
import sys
import time

import numpy as np
import onnxruntime as ort
import torch
from onnxruntime.quantization import CalibrationDataReader, CalibrationMethod, QuantFormat, QuantType, quantize_static
from onnxruntime.quantization.shape_inference import quant_pre_process
from PIL import Image
from torch import nn

from common import CLASSES, MEAN, ML_DIR, RUNS, STD, TanimNet, cached_path, load_run, read_manifest, summarize
from torchvision.transforms import v2 as T

EXPORT = ML_DIR / "export"


class Deployable(nn.Module):
    """Normalization in, softmax and per-class CAMs out."""

    def __init__(self, model: TanimNet):
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, image: torch.Tensor):
        logits, maps = self.model.forward_with_maps((image - self.mean) / self.std)
        cams = torch.einsum("ck,nkhw->nchw", self.model.fc.weight, maps)
        return torch.softmax(logits, dim=1), cams


def to_input(row: dict, size: int) -> np.ndarray:
    """Same resize + centre crop the app does, without normalization."""
    tf = T.Compose([T.Resize(size), T.CenterCrop(size), T.ToImage(), T.ToDtype(torch.float32, scale=True)])
    with Image.open(cached_path(row)) as img:
        return tf(img.convert("RGB"))[None].numpy()


class Calibration(CalibrationDataReader):
    def __init__(self, rows: list[dict], size: int):
        self.batches = iter([{"image": to_input(r, size)} for r in rows])

    def get_next(self):
        return next(self.batches, None)


def evaluate(session: ort.InferenceSession, rows: list[dict], size: int) -> tuple[dict, np.ndarray, float]:
    probs, times = [], []
    for r in rows:
        x = to_input(r, size)
        t0 = time.perf_counter()
        probs.append(session.run(["probs"], {"image": x})[0][0])
        times.append(time.perf_counter() - t0)
    probs = np.array(probs)
    y_true = np.array([CLASSES.index(r["label"]) for r in rows])
    return summarize(y_true, probs.argmax(1)), probs, float(np.median(times) * 1000)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")  # the exporter prints emoji; the Windows console defaults to cp1252
    p = argparse.ArgumentParser()
    p.add_argument("run")
    p.add_argument("--calibration", type=int, default=200, help="training images used to calibrate int8")
    args = p.parse_args()

    model, config = load_run(RUNS / args.run)
    size = config["img"]
    out = EXPORT / args.run
    out.mkdir(parents=True, exist_ok=True)
    fp32, prepped, int8 = out / "tanim_fp32.onnx", out / "tanim_prepped.onnx", out / "tanim_int8.onnx"

    deploy = Deployable(model).eval()
    torch.onnx.export(
        deploy, (torch.rand(1, 3, size, size),), fp32,
        input_names=["image"], output_names=["probs", "cams"], opset_version=18, dynamo=True, external_data=False, verbose=False,
    )

    rows = read_manifest()
    train_rows = [r for r in rows if r["split"] == "train"]
    val_rows = [r for r in rows if r["split"] == "val"]
    random.Random(0).shuffle(train_rows)

    quant_pre_process(str(fp32), str(prepped))
    quantize_static(
        str(prepped), str(int8), Calibration(train_rows[: args.calibration], size),
        quant_format=QuantFormat.QDQ, per_channel=True,
        activation_type=QuantType.QUInt8, weight_type=QuantType.QInt8,
        # Min/max calibration let a few extreme activations stretch the int8 range,
        # and val macro-F1 fell from 0.98 to 0.69. Clipping at the 99.99th percentile keeps it at 0.98.
        calibrate_method=CalibrationMethod.Percentile, extra_options={"CalibPercentile": 99.99},
    )
    prepped.unlink()

    # Does ONNX agree with PyTorch?
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 1  # closer to a phone than a 16-thread laptop
    s32 = ort.InferenceSession(str(fp32), opts, providers=["CPUExecutionProvider"])
    s8 = ort.InferenceSession(str(int8), opts, providers=["CPUExecutionProvider"])
    x = torch.from_numpy(to_input(val_rows[0], size))
    with torch.no_grad():
        ref_probs, ref_cams = deploy(x)
    onnx_probs, onnx_cams = s32.run(None, {"image": x.numpy()})
    parity = {
        "max_prob_diff": float(np.abs(ref_probs.numpy() - onnx_probs).max()),
        "max_cam_diff": float(np.abs(ref_cams.numpy() - onnx_cams).max()),
    }

    m32, p32, ms32 = evaluate(s32, val_rows, size)
    m8, p8, ms8 = evaluate(s8, val_rows, size)
    report = {
        "run": args.run,
        "classes": CLASSES,
        "input": {"name": "image", "shape": [1, 3, size, size], "range": "RGB 0..1, resize short side + centre crop"},
        "parity_fp32_vs_torch": parity,
        "fp32": {"mb": round(fp32.stat().st_size / 1e6, 2), "val_macro_f1": m32["macro_f1"], "val_acc": m32["accuracy"], "median_ms_1thread": round(ms32, 1)},
        "int8": {"mb": round(int8.stat().st_size / 1e6, 2), "val_macro_f1": m8["macro_f1"], "val_acc": m8["accuracy"], "median_ms_1thread": round(ms8, 1)},
        "int8_agrees_with_fp32": float((p32.argmax(1) == p8.argmax(1)).mean()),
    }
    (out / "labels.json").write_text(json.dumps(CLASSES, indent=2))
    (out / "export_report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
