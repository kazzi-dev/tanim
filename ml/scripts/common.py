"""Shared pieces for training and evaluation: image cache, dataset, model, metrics."""

import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageOps
from torch import nn
from torch.utils.data import Dataset
from torchvision import models
from torchvision.transforms import v2 as T

ML_DIR = Path(__file__).resolve().parents[1]
DATA = ML_DIR / "data"
CACHE = DATA / "cache"
RUNS = ML_DIR / "runs"

CLASSES: list[str] = json.loads((ML_DIR / "sources.json").read_text(encoding="utf-8"))["classes"]
CACHE_SHORT_SIDE = 320
MEAN, STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)


# ---------------------------------------------------------------- data

def read_manifest() -> list[dict]:
    with (DATA / "manifest.csv").open(encoding="utf-8") as f:
        return list(csv.DictReader(f))


def cached_path(row: dict) -> Path:
    """Phone photos are up to 4000px; decoding them every epoch is the bottleneck.
    Keep a copy with the short side at CACHE_SHORT_SIDE, upright per EXIF."""
    out = CACHE / (hashlib.sha1(row["path"].encode()).hexdigest()[:16] + ".jpg")
    if not out.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        with Image.open(DATA / row["path"]) as img:
            img = ImageOps.exif_transpose(img).convert("RGB")
            scale = CACHE_SHORT_SIDE / min(img.size)
            if scale < 1:
                img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
            img.save(out, quality=95)
    return out


def train_transform(size: int) -> T.Compose:
    # Field photos: any angle, uneven sun, some blur.
    return T.Compose([
        T.RandomResizedCrop(size, scale=(0.4, 1.0), ratio=(0.6, 1.66)),
        T.RandomHorizontalFlip(),
        T.RandomVerticalFlip(),
        T.RandomApply([T.RandomRotation(30)], p=0.5),
        T.ColorJitter(brightness=0.35, contrast=0.3, saturation=0.25, hue=0.03),
        T.RandomApply([T.GaussianBlur(5, sigma=(0.1, 2.0))], p=0.2),
        T.ToImage(),
        T.ToDtype(torch.float32, scale=True),
        T.Normalize(MEAN, STD),
    ])


def eval_transform(size: int) -> T.Compose:
    return T.Compose([
        T.Resize(size),
        T.CenterCrop(size),
        T.ToImage(),
        T.ToDtype(torch.float32, scale=True),
        T.Normalize(MEAN, STD),
    ])


class LeafDataset(Dataset):
    def __init__(self, rows: list[dict], transform):
        self.rows = rows
        self.paths = [cached_path(r) for r in rows]
        self.labels = [CLASSES.index(r["label"]) for r in rows]
        self.transform = transform

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, i: int):
        with Image.open(self.paths[i]) as img:
            return self.transform(img.convert("RGB")), self.labels[i]


# ---------------------------------------------------------------- model

class TanimNet(nn.Module):
    """Pretrained backbone -> global average pool -> one linear layer.

    Keeping the head to a single linear layer makes class activation maps exact
    and cheap: CAM[c] = sum_k fc.weight[c, k] * features[k]. The phone can
    compute the heatmap from the feature maps without gradients.
    """

    def __init__(self, arch: str, num_classes: int = len(CLASSES), pretrained: bool = True):
        super().__init__()
        if arch == "mobilenet_v3_large":
            net = models.mobilenet_v3_large(weights="DEFAULT" if pretrained else None)
            channels = net.classifier[0].in_features
        elif arch == "efficientnet_b0":
            net = models.efficientnet_b0(weights="DEFAULT" if pretrained else None)
            channels = net.classifier[1].in_features
        else:
            raise ValueError(f"unknown arch {arch!r}")
        self.arch = arch
        self.features = net.features
        self.dropout = nn.Dropout(0.3)
        self.fc = nn.Linear(channels, num_classes)

    def forward_with_maps(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        maps = self.features(x)
        logits = self.fc(self.dropout(maps.mean(dim=(2, 3))))
        return logits, maps

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.forward_with_maps(x)[0]

    def cam(self, maps: torch.Tensor, class_idx: torch.Tensor) -> torch.Tensor:
        """Heatmaps in [0, 1], shape (N, H, W), for the given class per image."""
        weights = self.fc.weight[class_idx]  # (N, K)
        cam = torch.relu(torch.einsum("nk,nkhw->nhw", weights, maps))
        return cam / cam.amax(dim=(1, 2), keepdim=True).clamp_min(1e-6)


def load_run(run_dir: Path, device: str = "cpu") -> tuple[TanimNet, dict]:
    config = json.loads((run_dir / "config.json").read_text(encoding="utf-8"))
    model = TanimNet(config["arch"], pretrained=False)
    model.load_state_dict(torch.load(run_dir / "best.pt", map_location=device, weights_only=True))
    return model.to(device).eval(), config


# ---------------------------------------------------------------- metrics

def confusion(y_true: np.ndarray, y_pred: np.ndarray, n: int = len(CLASSES)) -> np.ndarray:
    m = np.zeros((n, n), dtype=int)
    np.add.at(m, (y_true, y_pred), 1)
    return m


def summarize(y_true: np.ndarray, y_pred: np.ndarray) -> dict:
    m = confusion(y_true, y_pred)
    tp = np.diag(m).astype(float)
    precision = np.divide(tp, m.sum(0), out=np.zeros_like(tp), where=m.sum(0) > 0)
    recall = np.divide(tp, m.sum(1), out=np.zeros_like(tp), where=m.sum(1) > 0)
    f1 = np.divide(2 * precision * recall, precision + recall, out=np.zeros_like(tp), where=(precision + recall) > 0)
    present = m.sum(1) > 0
    return {
        "accuracy": float(tp.sum() / max(m.sum(), 1)),
        "macro_f1": float(f1[present].mean()) if present.any() else 0.0,
        "per_class": {
            c: {"precision": float(precision[i]), "recall": float(recall[i]), "f1": float(f1[i]), "support": int(m[i].sum())}
            for i, c in enumerate(CLASSES)
        },
        "confusion": m.tolist(),
    }
