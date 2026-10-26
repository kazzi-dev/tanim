# Tanim

**An offline rice leaf disease scanner.** Point a phone at a sick rice leaf and Tanim says which disease it most likely
is (bacterial leaf blight, blast, brown spot or tungro) or that the leaf looks healthy. It also shows how sure it is and
which part of the leaf it looked at. Everything runs on the phone, so it works in the field with no signal.

*Tanim* means "to plant" in Filipino.

> Tanim is a study project, not a diagnosis. Check with your local agriculturist before treating a field.

## Status

- [x] Public datasets downloaded, de-duplicated and split ([dataset card](docs/DATASET.md))
- [x] Baseline model: MobileNetV3-Large, 0.98 validation macro-F1 ([model card](docs/MODEL.md))
- [x] Never-seen-source test: 0.32–0.61 accuracy, the model leans on backgrounds (see model card)
- [ ] Reduce the background shortcut
- [x] ONNX export: 3.4 MB int8, 5.7 ms per photo, heatmaps built in
- [ ] Flutter app (`app/`)
- [ ] Collect and add photos from Filipino farmers

## Layout

```
ml/
  sources.json             datasets, licences, checksums, folder → class mapping
  scripts/download.py      download + verify + extract the datasets
  scripts/build_dataset.py de-duplicate and split → ml/data/manifest.csv
  scripts/train.py         fine-tune a pretrained backbone → ml/runs/<name>/
  scripts/heatmaps.py      draw what the model looks at on validation images
  scripts/export.py        ONNX export + int8 quantization + checks → ml/export/<run>/
  scripts/common.py        shared dataset, model and metrics code
  data/                    (git-ignored) downloads, raw images, manifest
docs/
  DATASET.md               where the images come from and what's wrong with them
  MODEL.md                 model, training setup and results
```

## Build the dataset

Needs Python 3.12 and about 1.5 GB of disk space. On Windows the scripts use the built-in `tar.exe` to extract the zip,
7z and rar archives.

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r ml/requirements.txt
.venv/Scripts/python ml/scripts/download.py
.venv/Scripts/python ml/scripts/build_dataset.py
```

(On macOS or Linux use `.venv/bin/python`.) The result is `ml/data/manifest.csv`, with one row per kept image giving
its path, label, source and split.

## Train

Install PyTorch with CUDA first for GPU training (the CPU build works too, just slower):

```bash
.venv/Scripts/python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
.venv/Scripts/python ml/scripts/train.py --arch mobilenet_v3_large
.venv/Scripts/python ml/scripts/heatmaps.py mobilenet_v3_large
.venv/Scripts/python ml/scripts/train.py --holdout bd5 --name loso_bd5   # never-seen-source test
.venv/Scripts/python ml/scripts/export.py mobilenet_v3_large
```

## Credits

The images are from three CC BY 4.0 datasets on Mendeley Data: Sethy et al. (2020), RiceLeafBD and RiceLeafDisease-BD5.
See [docs/DATASET.md](docs/DATASET.md) for full citations.
