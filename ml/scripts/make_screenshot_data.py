"""Real model outputs for the app screenshots (app/tool/screenshots/).

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/make_screenshot_data.py mobilenet_v3_large

Runs the shipped int8 model on a few validation photos and saves each photo
(the 320 px cached copy) with its probabilities and heatmaps, so the rendered
screenshots show what the app would really say.
"""

import json
import shutil
import sys

import numpy as np
import onnxruntime as ort

from common import ML_DIR, cached_path, read_manifest
from export import EXPORT, to_input

OUT = ML_DIR.parent / "app" / "tool" / "screenshots"

# A confident field photo and an honest "not sure" one, both from RiceLeafBD's field photos.
PICKS = ["sure", "unsure"]


def main() -> None:
    run = sys.argv[1] if len(sys.argv) > 1 else "mobilenet_v3_large"
    session = ort.InferenceSession(str(EXPORT / run / "tanim_int8.onnx"), providers=["CPUExecutionProvider"])
    val = sorted((r for r in read_manifest() if r["split"] == "val"), key=lambda r: r["path"])
    (OUT / "photos").mkdir(parents=True, exist_ok=True)

    field = [r for r in val if r["source"] == "riceleafbd"]
    scored = [(session.run(None, {"image": to_input(r, 224)})[0][0], r) for r in field]
    sure = max((t for t in scored if t[1]["label"] == "brown_spot"), key=lambda t: t[0][2])
    # Unsure: top class between 45% and 65%, closest to 55%.
    unsure = min((t for t in scored if 0.45 <= t[0].max() <= 0.65), key=lambda t: abs(t[0].max() - 0.55))

    data = {}
    for name, (_, r) in zip(PICKS, [sure, unsure]):
        probs, cams = session.run(None, {"image": to_input(r, 224)})
        shutil.copy(cached_path(r), OUT / "photos" / f"{name}.jpg")
        data[name] = {
            "label": r["label"],
            "source": r["source"],
            "probs": np.round(probs[0], 5).tolist(),
            "cams": np.round(cams[0].reshape(5, -1), 4).tolist(),
        }
        print(f"{name}: true {r['label']} -> {np.round(probs[0], 3).tolist()}")
    (OUT / "data.json").write_text(json.dumps(data))


if __name__ == "__main__":
    main()
