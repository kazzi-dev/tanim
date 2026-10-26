# Tanim app

Flutter app that runs the exported model ([`../ml/scripts/export.py`](../ml/scripts/export.py)) on the phone with
ONNX Runtime. No network is needed.

## Screens

- **Scan:** camera preview with a square guide (the model looks at the centre square of the photo), a shutter button and
  a gallery picker. Without a camera, it falls back to the gallery.
- **Result:** the square the model saw with a toggleable heatmap; the top class with confidence, or "Not sure" under 70%
  with the two likeliest options; a warning if the photo is too dark or blurry; what the disease looks like and what to
  do; the other classes; and a reminder to check with the Municipal Agriculture Office.
- **About:** how it works, what it gets wrong, photo credits.

## How a photo becomes an answer

1. Decode, apply EXIF rotation, shrink the short side to 320 then 224, centre-crop 224×224 (same as training).
   Done in a background isolate. See `lib/features/scan/data/preprocess.dart`.
2. Check brightness and sharpness against cut-offs picked from the validation photos.
3. Run `assets/model/tanim_int8.onnx` (3.4 MB). The graph normalizes the input and returns `probs` [1, 5] and `cams`
   [1, 5, 7, 7].
4. Draw the top class's CAM as a transparent jet overlay (`lib/features/scan/data/heatmap.dart`).

## Run

```bash
flutter pub get
flutter run                 # phone or emulator
flutter test                # unit + widget tests
flutter build apk --release --split-per-abi
```

`flutter test` checks that the Dart preprocessing matches the Python pipeline on 10 fixture photos
(`test/fixtures/`, made by `ml/scripts/make_app_fixtures.py`).

`integration_test/model_test.dart` runs the real model through ONNX Runtime and checks the predictions match Python:

```bash
flutter test integration_test -d windows
```

On Windows, building for desktop needs **Developer Mode** turned on (Settings → System → For developers), because
Flutter links plugins with symlinks.

## Updating the model

After retraining, run `ml/scripts/export.py <run>`, copy `tanim_int8.onnx` and `labels.json` from
`ml/export/<run>/` to `assets/model/`, then run `ml/scripts/make_app_fixtures.py <run>` and `flutter test`.
