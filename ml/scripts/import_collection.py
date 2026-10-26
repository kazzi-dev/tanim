"""Import a zip of training photos exported from the Tanim app.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/import_collection.py path/to/tanim_photos_20261101_090000.zip
    .venv/Scripts/python ml/scripts/build_dataset.py      # then rebuild the manifest

Photos land in ml/data/raw/ph_field/<label>/ and their rows are merged into
ml/data/raw/ph_field/labels.csv. Importing the same zip twice is harmless.
The first import also adds a "ph_field" source to ml/sources.json, with
"other" and "unsure" photos kept but left out of training.

The zip is treated as untrusted: only <label>/<id>.jpg entries with a known
label and a plain file name are extracted, so nothing can be written outside
the target folder.
"""

import csv
import io
import json
import re
import sys
import zipfile
from pathlib import Path

ML_DIR = Path(__file__).resolve().parents[1]
TARGET = ML_DIR / "data" / "raw" / "ph_field"
SOURCE_ID = "ph_field"
EXTRA_LABELS = ("other", "unsure")
ENTRY = re.compile(r"^([a-z_]+)/([0-9]{8}_[0-9]{6}_[0-9a-f]{4})\.jpg$")
COLUMNS = ["file", "label", "labelled_by", "taken_at", "note", "model_prediction", "model_confidence", "model_version"]


def ensure_source(classes: list[str]) -> None:
    path = ML_DIR / "sources.json"
    config = json.loads(path.read_text(encoding="utf-8"))
    if any(s["id"] == SOURCE_ID for s in config["sources"]):
        return
    config["sources"].append({
        "id": SOURCE_ID,
        "name": "Philippine field photos collected with the Tanim app",
        "local": True,
        "license": "Own photos. Get the farmer's consent before publishing any of them.",
        "folders": {**{c: c for c in classes}, **{e: None for e in EXTRA_LABELS}},
    })
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Added source '{SOURCE_ID}' to ml/sources.json")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    classes = json.loads((ML_DIR / "sources.json").read_text(encoding="utf-8"))["classes"]
    allowed = set(classes) | set(EXTRA_LABELS)

    with zipfile.ZipFile(sys.argv[1]) as z:
        try:
            rows = list(csv.DictReader(io.TextIOWrapper(z.open("labels.csv"), encoding="utf-8")))
        except KeyError:
            sys.exit("Not a Tanim export: labels.csv is missing.")
        names = set(z.namelist())

        for label in allowed:
            (TARGET / label).mkdir(parents=True, exist_ok=True)
        labels_csv = TARGET / "labels.csv"
        existing = {}
        if labels_csv.exists():
            with labels_csv.open(encoding="utf-8", newline="") as f:
                existing = {r["file"]: r for r in csv.DictReader(f)}

        added, skipped = 0, []
        for row in rows:
            m = ENTRY.match(row["file"])
            if not m or m.group(1) not in allowed or m.group(1) != row["label"] or row["file"] not in names:
                skipped.append(row["file"])
                continue
            out = TARGET / row["file"]
            if row["file"] not in existing:
                added += 1
            out.write_bytes(z.read(row["file"]))
            existing[row["file"]] = {c: row.get(c, "") for c in COLUMNS}

    with labels_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(sorted(existing.values(), key=lambda r: r["file"]))

    ensure_source(classes)
    counts = {}
    for r in existing.values():
        counts[r["label"]] = counts.get(r["label"], 0) + 1
    print(f"Imported {added} new photos ({len(rows) - added - len(skipped)} already there).")
    if skipped:
        print(f"Skipped {len(skipped)} entries that don't look like Tanim photos: {skipped[:5]}")
    print("ph_field now has: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    print("Next: .venv/Scripts/python ml/scripts/build_dataset.py")


if __name__ == "__main__":
    main()
