"""Cut leaves out of plain-background photos so training can swap the background.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/make_masks.py            # writes masks + a preview sheet

BD5 photographed picked leaves on white paper, and some Sethy photos have a
plain wall or table behind the leaf. A paper or wall background is pale and
grey (low colour saturation); leaves are green, yellow or brown (saturated).
So: leaf = saturated or dark pixels, then close small holes (grey blast
centres) and drop specks.

A mask is kept only when it looks like a cut-out leaf: 4-75% of the frame is
leaf and most of the border is background. Field photos fail that test (grass
everywhere) and get no mask.

Writes ml/data/masks/<cache name>.png (white = leaf), ml/data/masks/index.json,
and ml/data/masks/preview.jpg.
"""

import json
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from common import DATA, cached_path, read_manifest

MASKS = DATA / "masks"
MASK_SOURCES = {"bd5", "sethy2020"}


def leaf_mask(img: Image.Image) -> np.ndarray:
    hsv = np.asarray(img.convert("HSV"), dtype=np.float32) / 255
    sat, val = hsv[..., 1], hsv[..., 2]
    leaf = (sat > 0.16) | (val < 0.30)
    m = Image.fromarray((leaf * 255).astype(np.uint8))
    # Close gaps (pale blast lesions, glare), then open to drop specks.
    m = m.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11))
    m = m.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    return fill_holes(np.asarray(m) > 127)


def fill_holes(mask: np.ndarray) -> np.ndarray:
    """Background is whatever non-leaf area touches the border; any other gap is inside a leaf."""
    # copy(): fromarray can share the numpy buffer read-only, and floodfill then silently does nothing.
    padded = Image.fromarray(np.pad(~mask, 1, constant_values=True).astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(padded, (0, 0), 128)
    outside = np.asarray(padded)[1:-1, 1:-1] == 128
    return ~outside


def looks_cut_out(mask: np.ndarray) -> bool:
    border = np.concatenate([mask[0], mask[-1], mask[:, 0], mask[:, -1]])
    return 0.04 <= mask.mean() <= 0.75 and border.mean() <= 0.5


def main() -> None:
    MASKS.mkdir(parents=True, exist_ok=True)
    rows = [r for r in read_manifest() if r["source"] in MASK_SOURCES and r["split"] != "test"]
    index, tried = {}, {s: 0 for s in MASK_SOURCES}
    kept = {s: 0 for s in MASK_SOURCES}
    for r in rows:
        src = cached_path(r)
        with Image.open(src) as img:
            mask = leaf_mask(img.convert("RGB"))
        tried[r["source"]] += 1
        if looks_cut_out(mask):
            Image.fromarray((mask * 255).astype(np.uint8)).save(MASKS / f"{src.stem}.png")
            index[r["path"]] = f"{src.stem}.png"
            kept[r["source"]] += 1
    (MASKS / "index.json").write_text(json.dumps(index, indent=1))
    for s in sorted(MASK_SOURCES):
        print(f"{s}: masks for {kept[s]} of {tried[s]} train/val photos")

    # Preview: photo | mask outline, 16 random masked photos.
    random.seed(0)
    masked = [r for r in rows if r["path"] in index]
    # Blast lesions and yellow tungro tips are the hard cases, so show more of them.
    sample = random.sample([r for r in masked if r["label"] == "blast"], 8) + random.sample(
        [r for r in masked if r["label"] != "blast"], 8
    )
    tile = 180
    sheet = Image.new("RGB", (tile * 8, tile * 4), "white")
    for k, r in enumerate(sample):
        img = Image.open(cached_path(r)).convert("RGB")
        mask = Image.open(MASKS / index[r["path"]]).convert("L")
        cut = Image.composite(img, Image.new("RGB", img.size, (255, 0, 255)), mask)
        for j, im in enumerate((img, cut)):
            im = im.copy()
            im.thumbnail((tile, tile))
            x, y = (k % 4) * 2 * tile + j * tile, (k // 4) * tile
            sheet.paste(im, (x, y))
        ImageDraw.Draw(sheet).text(((k % 4) * 2 * tile + 3, (k // 4) * tile + 3), f"{r['source']} {r['label']}", fill="yellow")
    sheet.save(MASKS / "preview.jpg", quality=85)


if __name__ == "__main__":
    main()
