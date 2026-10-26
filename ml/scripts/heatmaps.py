"""Draw class activation maps over validation images to see what the model looks at.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/heatmaps.py mobilenet_v3_large
    .venv/Scripts/python ml/scripts/heatmaps.py mobilenet_v3_large --per-cell 4 --wrong

One row per (source, class) pair, a few images per row, the predicted class's
heatmap blended over each one. --wrong shows only misclassified images.
Saves ml/runs/<run>/heatmaps[_wrong].jpg.
"""

import argparse
import random
from collections import defaultdict

import numpy as np
import torch
import torch.nn.functional as F
from matplotlib import colormaps
from PIL import Image, ImageDraw

from common import CLASSES, RUNS, cached_path, eval_transform, load_run, read_manifest

TILE = 200


def overlay(img: Image.Image, cam: np.ndarray) -> Image.Image:
    heat = (colormaps["jet"](cam)[..., :3] * 255).astype(np.uint8)
    return Image.blend(img, Image.fromarray(heat), 0.45)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("run")
    p.add_argument("--per-cell", type=int, default=5)
    p.add_argument("--wrong", action="store_true")
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    run_dir = RUNS / args.run
    model, config = load_run(run_dir, device)
    tf = eval_transform(config["img"])

    rows = [r for r in read_manifest() if r["split"] == "val"]
    picked = []
    with torch.no_grad():
        for r in rows:
            img = Image.open(cached_path(r)).convert("RGB")
            logits, maps = model.forward_with_maps(tf(img)[None].to(device))
            prob = torch.softmax(logits, 1)[0]
            pred = int(prob.argmax())
            if args.wrong == (CLASSES[pred] != r["label"]):
                cam = model.cam(maps, torch.tensor([pred], device=device))
                cam = F.interpolate(cam[:, None], size=(config["img"],) * 2, mode="bilinear")[0, 0].cpu().numpy()
                picked.append((r, pred, float(prob[pred]), cam))

    groups = defaultdict(list)
    for item in picked:
        groups[(item[0]["source"], item[0]["label"])].append(item)
    random.seed(args.seed)
    keys = sorted(groups)
    sheet = Image.new("RGB", (TILE * args.per_cell, TILE * len(keys)), "white")
    draw = ImageDraw.Draw(sheet)
    for y, key in enumerate(keys):
        items = groups[key]
        for x, (r, pred, conf, cam) in enumerate(random.sample(items, min(args.per_cell, len(items)))):
            base = Image.open(cached_path(r)).convert("RGB")
            # Same resize + centre crop as eval_transform, so the heatmap lines up.
            s = config["img"] / min(base.size)
            base = base.resize((round(base.width * s), round(base.height * s)))
            left, top = (base.width - config["img"]) // 2, (base.height - config["img"]) // 2
            base = base.crop((left, top, left + config["img"], top + config["img"]))
            tile = overlay(base, cam).resize((TILE, TILE))
            sheet.paste(tile, (x * TILE, y * TILE))
            draw.rectangle((x * TILE, y * TILE, x * TILE + TILE, y * TILE + 30), fill=(0, 0, 0))
            draw.text((x * TILE + 4, y * TILE + 2), f"{key[0]} / true: {key[1]}", fill="white")
            draw.text((x * TILE + 4, y * TILE + 15), f"pred: {CLASSES[pred]} {conf:.0%}",
                      fill="lime" if CLASSES[pred] == key[1] else "red")
    out = run_dir / ("heatmaps_wrong.jpg" if args.wrong else "heatmaps.jpg")
    sheet.save(out, quality=88)
    print(f"{len(picked)} images, {len(keys)} rows -> {out}")


if __name__ == "__main__":
    main()
