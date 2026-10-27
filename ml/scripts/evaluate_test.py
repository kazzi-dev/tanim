"""Score a finished model on the locked test split. Run this once per final model.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/evaluate_test.py mobilenet_v3_large

Scores the exported int8 ONNX model (what the app ships) on every test image,
overall and per source, and writes ml/runs/<run>/test_metrics.json and
confusion_test.png. Tuning on these numbers would make them meaningless, so
the script refuses to run twice unless --again is passed.
"""

import argparse
import json
import sys

import numpy as np
import onnxruntime as ort

from common import CLASSES, RUNS, read_manifest, summarize
from export import EXPORT, to_input
from train import plot_confusion


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("run")
    p.add_argument("--again", action="store_true", help="re-run even though test results already exist")
    args = p.parse_args()

    out = RUNS / args.run / "test_metrics.json"
    if out.exists() and not args.again:
        sys.exit(f"{out} exists: the test split was already used for this model. Pass --again to re-run.")

    session = ort.InferenceSession(str(EXPORT / args.run / "tanim_int8.onnx"), providers=["CPUExecutionProvider"])
    rows = [r for r in read_manifest() if r["split"] == "test"]
    probs = np.array([session.run(["probs"], {"image": to_input(r, 224)})[0][0] for r in rows])
    y_true = np.array([CLASSES.index(r["label"]) for r in rows])
    y_pred = probs.argmax(1)

    sources = np.array([r["source"] for r in rows])
    report = {
        "model": f"{args.run} (int8 ONNX)",
        "images": len(rows),
        "overall": summarize(y_true, y_pred),
        "by_source": {s: summarize(y_true[sources == s], y_pred[sources == s]) for s in sorted(set(sources))},
    }
    out.write_text(json.dumps(report, indent=2))
    plot_confusion(report["overall"]["confusion"], f"{args.run} int8 - test", RUNS / args.run / "confusion_test.png")

    o = report["overall"]
    print(f"Test ({len(rows)} images): macro-F1 {o['macro_f1']:.3f}, accuracy {o['accuracy']:.3f}")
    for c, m in o["per_class"].items():
        print(f"  {c:22s} P {m['precision']:.2f}  R {m['recall']:.2f}  F1 {m['f1']:.2f}  (n={m['support']})")
    for s, m in report["by_source"].items():
        print(f"  {s:11s} accuracy {m['accuracy']:.3f}  (n={sum(v['support'] for v in m['per_class'].values())})")


if __name__ == "__main__":
    main()
