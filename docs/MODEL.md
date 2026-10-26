# Model card

## v0 baseline: MobileNetV3-Large

| | |
|---|---|
| Backbone | MobileNetV3-Large, ImageNet-pretrained (torchvision) |
| Head | global average pool → dropout 0.3 → one linear layer (5 classes) |
| Size | 2.98 M parameters, 11.9 MB in fp32 (before quantization) |
| Input | 224 × 224 RGB, ImageNet normalization |
| Training | `ml/scripts/train.py --arch mobilenet_v3_large` on an RTX 4070 Laptop, about 4 s per epoch |

The single linear head is deliberate. With it, the heatmap for class *c* is just `sum_k fc.weight[c, k] * features[k]`,
so the phone can draw it without computing gradients.

### Training

- Stage 1: backbone frozen, head only, 3 epochs, AdamW lr 1e-3
- Stage 2: everything, AdamW (backbone lr 1.5e-4, head lr 3e-4), 1 epoch warm-up then cosine, early stop after 8
  epochs without improvement
- Class-weighted cross-entropy with label smoothing 0.1
- Augmentation: random resized crop (40–100%), horizontal and vertical flips, rotation up to 30°, colour jitter, blur
- Best epoch: 20 of 28

![Training curves](img/curves.png)

### Validation results

These are **validation** numbers (499 images). The test split hasn't been opened yet; it's saved for the final model.

| Class | Precision | Recall | F1 | n |
|---|---:|---:|---:|---:|
| bacterial_leaf_blight | 0.97 | 0.98 | 0.97 | 59 |
| blast | 1.00 | 0.99 | 0.99 | 92 |
| brown_spot | 0.96 | 0.97 | 0.96 | 67 |
| tungro | 0.98 | 0.97 | 0.98 | 145 |
| healthy | 1.00 | 1.00 | 1.00 | 136 |
| **macro** | | | **0.982** | 499 |

| Source | Accuracy |
|---|---:|
| bd5 (white paper backgrounds) | 1.000 |
| riceleafbd (field) | 0.967 |
| sethy2020 | 0.980 (small: about 50 images) |

![Confusion matrix](img/confusion_val.png)

EfficientNet-B0 scored about the same (macro-F1 0.977) while being 35% larger, so MobileNetV3-Large is the pick for
now.

### What the heatmaps show

![Heatmaps on validation images](img/heatmaps_val.jpg)

- On most images the attention sits on the leaf and its lesions, not the background. That includes BD5's white paper
  photos, and for brown spot it lands on the spots themselves.
- On healthy field photos some attention spreads onto the surrounding grass.
- The 9 mistakes are look-alike pairs: tungro ↔ bacterial leaf blight (both yellow the leaf) and blast → brown spot.

![Misclassified validation images](img/heatmaps_wrong.jpg)

### Why 98% is not the real number

The validation photos come from the same three datasets, cameras and fields as the training photos. A 2-epoch
smoke-test model recognized 94% of BD5 blast photos but **0%** of Sethy blast photos, which shows how much the source
matters early on. The number that counts will come from photos the model has never seen the like of: Filipino farmers'
phones in Philippine fields.

## Next

- Leave-one-source-out runs to measure how well it carries over to a new source
- Export to ONNX (with the feature maps as a second output for the heatmap) and int8 quantization
- Open the test split once, for the final model only
