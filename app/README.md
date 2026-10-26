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

`integration_test/model_test.dart` runs the real model through ONNX Runtime on a device and checks the predictions
match Python. The fixture photos are embedded first, because a phone can't read files from the laptop:

```bash
dart run tool/embed_fixtures.dart
flutter test integration_test -d <device id>     # see `flutter devices`
```

Last run on a phone (Android 17, arm64, over wireless debugging): 10/10 top classes match Python, largest
probability gap 0.063, 50–110 ms per photo from bytes to heatmap after a 308 ms first run.

On Windows, building for desktop needs **Developer Mode** turned on (Settings → System → For developers), because
Flutter links plugins with symlinks.

## Updating the model

After retraining, run `ml/scripts/export.py <run>`, copy `tanim_int8.onnx` and `labels.json` from
`ml/export/<run>/` to `assets/model/`, then run `ml/scripts/make_app_fixtures.py <run>`, `flutter test`, and the device test above.
