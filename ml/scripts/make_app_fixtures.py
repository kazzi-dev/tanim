"""Write test fixtures so the Flutter app can check it matches the Python pipeline.

Usage (from the repo root, after export.py):
    .venv/Scripts/python ml/scripts/make_app_fixtures.py mobilenet_v3_large

Copies a few validation photos into app/test/fixtures/ and writes expected.json:
for each photo, the 224x224 input average-pooled to 28x28 per channel (small
enough to commit, detailed enough to catch a wrong resize, crop or channel
order) and the fp32/int8 ONNX probabilities.
"""

import json
import shutil
import sys

import numpy as np
import onnxruntime as ort

from common import CLASSES, ML_DIR, cached_path, read_manifest
from export import EXPORT, to_input

FIXTURES = ML_DIR.parent / "app" / "test" / "fixtures"
POOL = 8  # 224 / 8 = 28


def main() -> None:
    run = sys.argv[1] if len(sys.argv) > 1 else "mobilenet_v3_large"
    s32 = ort.InferenceSession(str(EXPORT / run / "tanim_fp32.onnx"), providers=["CPUExecutionProvider"])
    s8 = ort.InferenceSession(str(EXPORT / run / "tanim_int8.onnx"), providers=["CPUExecutionProvider"])

    val = sorted((r for r in read_manifest() if r["split"] == "val"), key=lambda r: r["path"])
    picked = []
    for label in CLASSES:  # one per class, plus a second source where there is one
        by_source = {}
        for r in val:
            if r["label"] == label and r["source"] not in by_source:
                by_source[r["source"]] = r
        picked += list(by_source.values())[:2]

    FIXTURES.mkdir(parents=True, exist_ok=True)
    expected = []
    for i, r in enumerate(picked):
        name = f"{i:02d}_{r['label']}_{r['source']}.jpg"
        shutil.copy(cached_path(r), FIXTURES / name)
        x = to_input(r, 224)
        pooled = x[0].reshape(3, 224 // POOL, POOL, 224 // POOL, POOL).mean(axis=(2, 4))
        expected.append({
            "file": name,
            "label": r["label"],
            "source": r["source"],
            "pooled28": np.round(pooled, 4).ravel().tolist(),
            "probs_fp32": np.round(s32.run(["probs"], {"image": x})[0][0], 5).tolist(),
            "probs_int8": np.round(s8.run(["probs"], {"image": x})[0][0], 5).tolist(),
        })
    (FIXTURES / "expected.json").write_text(json.dumps({"classes": CLASSES, "images": expected}))
    (FIXTURES / "CREDITS.md").write_text(
        "Photos are from the Tanim training sources, all CC BY 4.0 on Mendeley Data: "
        "Sethy et al. (2020) doi:10.17632/fwcj7stb8r.2, RiceLeafBD doi:10.17632/kx9rx8p2mz.1, "
        "RiceLeafDisease-BD5 doi:10.17632/sjkptpgv79.2. Resized to a 320 px short side.\n"
    )
    print(f"{len(expected)} fixtures -> {FIXTURES}")


if __name__ == "__main__":
    main()
