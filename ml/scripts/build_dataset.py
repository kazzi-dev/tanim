"""Turn the extracted datasets into one labelled, de-duplicated, split manifest.

Usage (from the repo root, after download.py):
    .venv/Scripts/python ml/scripts/build_dataset.py

Steps:
  1. Walk each source's folders and map them to Tanim's classes using the
     "folders" table in ml/sources.json (null = leave that folder out).
  2. Drop files Pillow can't open.
  3. Find exact and near-duplicate images with a perceptual hash. Keeping both
     copies would let the same photo land in train and test and inflate scores.
     Each duplicate group keeps one image; groups whose copies disagree on the
     label are dropped entirely.
  4. Split 70/15/15, stratified by (class, source), with a fixed seed.

Writes ml/data/manifest.csv and ml/data/report.json, and prints a summary.
"""

import csv
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

import imagehash
import numpy as np
from PIL import Image

ML_DIR = Path(__file__).resolve().parents[1]
DATA = ML_DIR / "data"
RAW = DATA / "raw"

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
NEAR_DUP_BITS = 4  # pHash distance (out of 64) at or below which two images count as the same photo
SPLITS = (("train", 0.70), ("val", 0.15), ("test", 0.15))
SEED = 2026


ORIENTATIONS = [None, *Image.Transpose]  # identity, flips, 90/180/270 rotations, transposes


def orientation_phashes(img: Image.Image) -> list[int]:
    """pHashes of the image in all 8 orientations (the first is the original).

    Some sources pad their folders with rotated/flipped versions of the same
    photo. Comparing every orientation of one image with another catches those.
    """
    small = img.convert("L").resize((32, 32), Image.Resampling.LANCZOS)
    return [
        int(str(imagehash.phash(small if t is None else small.transpose(t))), 16)
        for t in ORIENTATIONS
    ]


def collect(sources: list[dict], classes: list[str]) -> tuple[list[dict], Counter]:
    rows, skipped = [], Counter()
    for source in sources:
        root = RAW / source["id"]
        if not source["folders"]:
            raise SystemExit(f"{source['id']}: no folder mapping in sources.json yet")
        for folder, label in source["folders"].items():
            folder_path = root / folder
            if not folder_path.is_dir():
                raise SystemExit(f"{source['id']}: folder not found: {folder_path}")
            if label is None:
                continue
            if label not in classes:
                raise SystemExit(f"{source['id']}: unknown class {label!r} for {folder}")
            for path in sorted(folder_path.rglob("*")):
                if path.suffix.lower() not in IMAGE_EXTS:
                    continue
                try:
                    with Image.open(path) as img:
                        img = img.convert("RGB")
                        width, height = img.size
                        phashes = orientation_phashes(img)
                except Exception:
                    skipped["unreadable"] += 1
                    continue
                rows.append({
                    "path": path.relative_to(DATA).as_posix(),
                    "label": label,
                    "source": source["id"],
                    "width": width,
                    "height": height,
                    "phash": phashes[0],
                    "phashes": phashes,
                })
    return rows, skipped


def dedupe(rows: list[dict]) -> tuple[list[dict], Counter]:
    """Group images within NEAR_DUP_BITS of each other in any orientation (union-find)."""
    originals = np.array([r["phash"] for r in rows], dtype=np.uint64)
    oriented = np.array([r["phashes"] for r in rows], dtype=np.uint64)
    parent = list(range(len(rows)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(rows) - 1):
        distance = np.bitwise_count(originals[i + 1:][None, :] ^ oriented[i][:, None]).min(axis=0)
        close = np.nonzero(distance <= NEAR_DUP_BITS)[0]
        for j in close + i + 1:
            parent[find(int(j))] = find(i)

    groups = defaultdict(list)
    for i in range(len(rows)):
        groups[find(i)].append(rows[i])

    kept, dropped = [], Counter()
    for members in groups.values():
        if len({m["label"] for m in members}) > 1:
            dropped["label conflict"] += len(members)
            continue
        # Keep the largest copy; the rest are duplicates.
        members.sort(key=lambda m: m["width"] * m["height"], reverse=True)
        kept.append(members[0])
        dropped["duplicate"] += len(members) - 1
    return kept, dropped


def split(rows: list[dict]) -> None:
    rng = random.Random(SEED)
    strata = defaultdict(list)
    for r in rows:
        strata[(r["label"], r["source"])].append(r)
    for key in sorted(strata):
        members = sorted(strata[key], key=lambda r: r["path"])
        rng.shuffle(members)
        n = len(members)
        n_train = round(n * SPLITS[0][1])
        n_val = round(n * SPLITS[1][1])
        for k, r in enumerate(members):
            r["split"] = "train" if k < n_train else "val" if k < n_train + n_val else "test"


def table(rows: list[dict], col: str, cols: list[str], labels: list[str]) -> str:
    counts = Counter((r["label"], r[col]) for r in rows)
    width = max(map(len, labels)) + 2
    lines = ["".ljust(width) + "".join(c.rjust(12) for c in cols) + "total".rjust(9)]
    for label in labels:
        cells = [counts[(label, c)] for c in cols]
        lines.append(label.ljust(width) + "".join(str(n).rjust(12) for n in cells) + str(sum(cells)).rjust(9))
    totals = [sum(counts[(label, c)] for label in labels) for c in cols]
    lines.append("total".ljust(width) + "".join(str(n).rjust(12) for n in totals) + str(sum(totals)).rjust(9))
    return "\n".join(lines)


def main() -> None:
    config = json.loads((ML_DIR / "sources.json").read_text(encoding="utf-8"))
    classes, sources = config["classes"], config["sources"]

    rows, skipped = collect(sources, classes)
    print(f"Found {len(rows)} readable images")
    rows, dropped = dedupe(rows)
    split(rows)
    rows.sort(key=lambda r: (r["split"], r["label"], r["path"]))

    with (DATA / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "label", "source", "split", "width", "height", "phash"])
        writer.writeheader()
        for r in rows:
            writer.writerow({**{k: v for k, v in r.items() if k != "phashes"}, "phash": f"{r['phash']:016x}"})

    report = {
        "images": len(rows),
        "removed": {**skipped, **dropped},
        "by_split": {s: dict(Counter(r["label"] for r in rows if r["split"] == s)) for s, _ in SPLITS},
        "by_source": {s["id"]: dict(Counter(r["label"] for r in rows if r["source"] == s["id"])) for s in sources},
    }
    (DATA / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Removed: {dict(report['removed']) or 'nothing'}")
    print(f"Kept {len(rows)} images -> ml/data/manifest.csv\n")
    print("By source")
    print(table(rows, "source", [s["id"] for s in sources], classes))
    print("\nBy split")
    print(table(rows, "split", [s for s, _ in SPLITS], classes))


if __name__ == "__main__":
    main()
