"""Fine-tune a pretrained backbone on the Tanim manifest.

Usage (from the repo root):
    .venv/Scripts/python ml/scripts/train.py --arch mobilenet_v3_large
    .venv/Scripts/python ml/scripts/train.py --arch efficientnet_b0 --name effb0

Two stages: first only the new head trains (backbone frozen), then everything
trains at a lower learning rate. The checkpoint with the best validation
macro-F1 is kept. The test split is never read here.

Writes ml/runs/<name>/: config.json, best.pt, history.json, val_metrics.json,
val_predictions.csv, curves.png, confusion_val.png.
"""

import argparse
import csv
import json
import math
import time
from collections import Counter

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader

from common import CLASSES, RUNS, LeafDataset, TanimNet, eval_transform, read_manifest, summarize, train_transform


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--arch", default="mobilenet_v3_large", choices=["mobilenet_v3_large", "efficientnet_b0"])
    p.add_argument("--name", help="run folder name (default: the arch)")
    p.add_argument("--img", type=int, default=224)
    p.add_argument("--batch", type=int, default=32)
    p.add_argument("--head-epochs", type=int, default=3)
    p.add_argument("--epochs", type=int, default=30, help="full fine-tuning epochs after the head stage")
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--patience", type=int, default=8)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--seed", type=int, default=2026)
    return p.parse_args()


def run_epoch(model, loader, device, criterion, optimizer=None, scheduler=None):
    training = optimizer is not None
    model.train(training)
    total_loss, preds, labels = 0.0, [], []
    with torch.set_grad_enabled(training):
        for x, y in loader:
            x, y = x.to(device, non_blocking=True), y.to(device, non_blocking=True)
            with torch.autocast(device_type=device, dtype=torch.bfloat16, enabled=device == "cuda"):
                logits = model(x)
                loss = criterion(logits, y)
            if training:
                optimizer.zero_grad(set_to_none=True)
                loss.backward()
                optimizer.step()
                if scheduler:
                    scheduler.step()
            total_loss += loss.item() * len(y)
            preds.append(logits.argmax(1).cpu())
            labels.append(y.cpu())
    y_true, y_pred = torch.cat(labels).numpy(), torch.cat(preds).numpy()
    return total_loss / len(y_true), summarize(y_true, y_pred)


@torch.no_grad()
def predict(model, loader, device) -> np.ndarray:
    model.eval()
    probs = []
    for x, _ in loader:
        with torch.autocast(device_type=device, dtype=torch.bfloat16, enabled=device == "cuda"):
            probs.append(torch.softmax(model(x.to(device)).float(), 1).cpu())
    return torch.cat(probs).numpy()


def plot_curves(history: list[dict], path) -> None:
    epochs = [h["epoch"] for h in history]
    fig, (a, b) = plt.subplots(1, 2, figsize=(10, 3.6))
    a.plot(epochs, [h["train_loss"] for h in history], label="train")
    a.plot(epochs, [h["val_loss"] for h in history], label="val")
    a.set_title("Loss"), a.set_xlabel("epoch"), a.legend()
    b.plot(epochs, [h["train_f1"] for h in history], label="train")
    b.plot(epochs, [h["val_f1"] for h in history], label="val")
    b.set_title("Macro-F1"), b.set_xlabel("epoch"), b.set_ylim(0, 1), b.legend()
    for ax in (a, b):
        ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def plot_confusion(matrix: list[list[int]], title: str, path) -> None:
    m = np.array(matrix)
    fig, ax = plt.subplots(figsize=(5.6, 4.8))
    ax.imshow(m / m.sum(1, keepdims=True).clip(1), cmap="Greens", vmin=0, vmax=1)
    short = [c.replace("bacterial_leaf_blight", "leaf blight").replace("_", " ") for c in CLASSES]
    ax.set_xticks(range(len(CLASSES)), short, rotation=35, ha="right")
    ax.set_yticks(range(len(CLASSES)), short)
    ax.set_xlabel("predicted"), ax.set_ylabel("true"), ax.set_title(title)
    for i in range(len(CLASSES)):
        for j in range(len(CLASSES)):
            ax.text(j, i, m[i, j], ha="center", va="center", color="white" if m[i, j] > m[i].sum() / 2 else "black")
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    run_dir = RUNS / (args.name or args.arch)
    run_dir.mkdir(parents=True, exist_ok=True)

    rows = read_manifest()
    train_rows = [r for r in rows if r["split"] == "train"]
    val_rows = [r for r in rows if r["split"] == "val"]
    print(f"Caching images (first run only)... train {len(train_rows)}, val {len(val_rows)}")
    train_ds = LeafDataset(train_rows, train_transform(args.img))
    val_ds = LeafDataset(val_rows, eval_transform(args.img))
    loader_kw = dict(batch_size=args.batch, num_workers=args.workers, pin_memory=True, persistent_workers=args.workers > 0)
    train_dl = DataLoader(train_ds, shuffle=True, drop_last=True, **loader_kw)
    val_dl = DataLoader(val_ds, shuffle=False, **loader_kw)

    # Weight the loss so rarer classes count as much as tungro.
    counts = Counter(train_ds.labels)
    weights = torch.tensor([len(train_ds) / (len(CLASSES) * counts[i]) for i in range(len(CLASSES))], dtype=torch.float32)
    criterion = nn.CrossEntropyLoss(weight=weights.to(device), label_smoothing=0.1)

    model = TanimNet(args.arch).to(device)
    (run_dir / "config.json").write_text(json.dumps({**vars(args), "classes": CLASSES, "device": device}, indent=2))

    history, best_f1, best_epoch, epoch = [], -1.0, 0, 0
    stages = [("head", args.head_epochs), ("full", args.epochs)]
    for stage, n_epochs in stages:
        if n_epochs == 0:
            continue
        for p in model.features.parameters():
            p.requires_grad = stage == "full"
        if stage == "head":
            optimizer = torch.optim.AdamW(model.fc.parameters(), lr=1e-3, weight_decay=1e-4)
            scheduler = None
        else:
            optimizer = torch.optim.AdamW([
                {"params": model.features.parameters(), "lr": args.lr * 0.5},
                {"params": model.fc.parameters(), "lr": args.lr},
            ], weight_decay=1e-4)
            total = n_epochs * len(train_dl)
            warmup = len(train_dl)
            scheduler = torch.optim.lr_scheduler.LambdaLR(
                optimizer, lambda s: min(1.0, (s + 1) / warmup) * 0.5 * (1 + math.cos(math.pi * min(s, total) / total))
            )
        stale = 0
        for _ in range(n_epochs):
            epoch += 1
            t0 = time.time()
            train_loss, train_m = run_epoch(model, train_dl, device, criterion, optimizer, scheduler)
            val_loss, val_m = run_epoch(model, val_dl, device, criterion)
            history.append({
                "epoch": epoch, "stage": stage,
                "train_loss": train_loss, "val_loss": val_loss,
                "train_f1": train_m["macro_f1"], "val_f1": val_m["macro_f1"], "val_acc": val_m["accuracy"],
            })
            mark = ""
            if val_m["macro_f1"] > best_f1:
                best_f1, best_epoch, stale, mark = val_m["macro_f1"], epoch, 0, " *"
                torch.save(model.state_dict(), run_dir / "best.pt")
            else:
                stale += 1
            print(f"[{stage}] epoch {epoch:2d}  train loss {train_loss:.3f} f1 {train_m['macro_f1']:.3f}  "
                  f"val loss {val_loss:.3f} f1 {val_m['macro_f1']:.3f} acc {val_m['accuracy']:.3f}  "
                  f"({time.time() - t0:.0f}s){mark}")
            if stage == "full" and stale >= args.patience:
                print(f"No improvement for {args.patience} epochs, stopping.")
                break

    (run_dir / "history.json").write_text(json.dumps(history, indent=2))
    plot_curves(history, run_dir / "curves.png")

    # Final validation report from the best checkpoint, broken down by source.
    model.load_state_dict(torch.load(run_dir / "best.pt", map_location=device, weights_only=True))
    probs = predict(model, val_dl, device)
    y_true, y_pred = np.array(val_ds.labels), probs.argmax(1)
    report = {"best_epoch": best_epoch, "overall": summarize(y_true, y_pred), "by_source": {}}
    sources = np.array([r["source"] for r in val_rows])
    for s in sorted(set(sources)):
        mask = sources == s
        report["by_source"][s] = summarize(y_true[mask], y_pred[mask])
    (run_dir / "val_metrics.json").write_text(json.dumps(report, indent=2))
    plot_confusion(report["overall"]["confusion"], f"{args.arch} - validation", run_dir / "confusion_val.png")

    with (run_dir / "val_predictions.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["path", "source", "label", "predicted", "confidence"])
        for r, p in zip(val_rows, probs):
            w.writerow([r["path"], r["source"], r["label"], CLASSES[p.argmax()], f"{p.max():.4f}"])

    o = report["overall"]
    print(f"\nBest epoch {best_epoch}: val macro-F1 {o['macro_f1']:.3f}, accuracy {o['accuracy']:.3f}")
    for c, m in o["per_class"].items():
        print(f"  {c:22s} P {m['precision']:.2f}  R {m['recall']:.2f}  F1 {m['f1']:.2f}  (n={m['support']})")
    print("By source:")
    for s, m in report["by_source"].items():
        recalls = ", ".join(f"{c} {v['recall']:.2f}" for c, v in m["per_class"].items() if v["support"])
        print(f"  {s:11s} acc {m['accuracy']:.3f}  | recall: {recalls}")


if __name__ == "__main__":
    main()
