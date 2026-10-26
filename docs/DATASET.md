# Dataset card

Tanim v0 is trained on public rice leaf photos. These are a stand-in: the plan is to replace and extend them with
photos from Filipino farmers. None of the images below were taken in the Philippines.

## Classes

| Class | What it looks like |
|---|---|
| `bacterial_leaf_blight` | Yellow to straw-coloured streaks running from the leaf tip and edges, often with wavy margins |
| `blast` | Diamond or spindle-shaped lesions with grey centres and brown borders |
| `brown_spot` | Small round to oval brown spots, often with a yellow halo |
| `tungro` | Yellow-orange discolouration starting at the tip; stunted plants (virus spread by leafhoppers) |
| `healthy` | Uniformly green leaf with no lesions |

## Sources

All three are on Mendeley Data under **CC BY 4.0**, which allows reuse with attribution. The exact files, checksums and
folder-to-class mapping are in [`ml/sources.json`](../ml/sources.json).

| Source | Where | Used folders | Left out |
|---|---|---|---|
| **Sethy et al.**, Rice Leaf Disease Image Samples ([doi:10.17632/fwcj7stb8r.2](https://doi.org/10.17632/fwcj7stb8r.2)) | Odisha, India | Bacterial blight, Blast, Brown spot, Tungro | none |
| **RiceLeafBD** ([doi:10.17632/kx9rx8p2mz.1](https://doi.org/10.17632/kx9rx8p2mz.1)) | Sylhet and Dhaka, Bangladesh; field, smartphone | Bacterial Leaf Blight, Brown Spot, Tungro Virus, Healthy Leaf | none |
| **RiceLeafDisease-BD5** ([doi:10.17632/sjkptpgv79.2](https://doi.org/10.17632/sjkptpgv79.2)) | Dhaka, Bangladesh; field, smartphone | Blast, Tungro, Normal Leaf (→ healthy) | Narrow Brown Spot, Sheath Blight (different diseases from our classes) |

Sethy et al. ask to be cited as: Sethy, P. K., Barpanda, N. K., Rath, A. K., & Behera, S. K. (2020). *Deep feature based
rice leaf disease identification using support vector machine.* Computers and Electronics in Agriculture, 175, 105527.

## Cleaning

`ml/scripts/build_dataset.py` hashes every image with a perceptual hash in all 8 orientations and groups images whose
hashes are within 4 bits of each other. Each group keeps one image.

| Step | Images |
|---|---|
| Downloaded (readable) | 9,540 |
| Duplicates removed (exact copies, rotations, flips) | −6,166 |
| Removed because copies of the same photo had different labels | −46 |
| **Kept** | **3,328** |

**Sethy's 5,932 images are about 342 unique photos.** Each photo appears about 16 times as rotations, flips and
mirror-padded versions under different file names. Splitting that set at random would put rotated copies of training
photos in the test set and make the model look far better than it is. After de-duplication no group spans two sources.

**RiceLeafBD has 46 photos filed under two different diseases** (mostly the same file in both *Bacterial Leaf Blight*
and *Tungro Virus*). We can't tell which label is right, so both copies are dropped.

## Splits

Stratified by class *and* source, 70 / 15 / 15, seed 2026. The test split is locked: don't look at it while tuning.

| | train | val | test | total |
|---|---:|---:|---:|---:|
| bacterial_leaf_blight | 276 | 59 | 60 | 395 |
| blast | 429 | 92 | 92 | 613 |
| brown_spot | 313 | 67 | 67 | 447 |
| tungro | 677 | 145 | 145 | 967 |
| healthy | 634 | 136 | 136 | 906 |
| **total** | **2,329** | **499** | **500** | **3,328** |

| | sethy2020 | riceleafbd | bd5 |
|---|---:|---:|---:|
| bacterial_leaf_blight | 75 | 320 | 0 |
| blast | 80 | 0 | 533 |
| brown_spot | 101 | 346 | 0 |
| tungro | 86 | 491 | 390 |
| healthy | 0 | 251 | 655 |

## Known problems

- **Source and class are tangled.** Blast comes mostly from BD5, bacterial leaf blight and brown spot mostly from
  RiceLeafBD, and Sethy has no healthy leaves. A model can score well by learning *which camera or background* a photo
  came from instead of the disease. Report accuracy per source, and check the heatmaps for attention on the background.
  This is visible by eye: BD5 photographs picked leaves on **white paper**, while RiceLeafBD photographs them in the
  field. So "white background" alone points to blast or healthy.
- **Some Sethy images carry a "PhilRice" watermark.** A watermark is another shortcut the model could learn, and those
  photos may originally come from PhilRice materials.
- **Not Philippine fields.** Varieties, lighting, backgrounds and phones differ. Expect lower accuracy on local photos;
  measuring that gap is the point of collecting farmer photos.
- **Labels are the dataset authors'.** We haven't had an agriculturist review them.
- **Near-duplicates can still slip through** if they are cropped or zoomed rather than rotated or flipped.

## Next: Filipino farmer photos

Collect them with the app's **Collect** mode (see `app/README.md`), export the zip, then:

```bash
.venv/Scripts/python ml/scripts/import_collection.py tanim_photos_YYYYMMDD_HHMMSS.zip
.venv/Scripts/python ml/scripts/build_dataset.py
```

They become the `ph_field` source, split like the others, so `ph_field`'s test images form a **Philippine-only test
set**. Report it next to the public-data test score. Also run `train.py --holdout ph_field`: that's the honest
"never seen a Philippine photo" number. Each row records who labelled it (self, farmer, agriculturist); prefer
agriculturist labels for the test set.

Before publishing any of these photos, get the farmer's consent; the importer marks the source that way.
