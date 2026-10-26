import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Side of the square the model sees.
const int kModelSize = 224;

/// Training images were cached with this short side (LANCZOS) before the
/// final resize, so the app shrinks big photos to the same size first.
const int _cacheShortSide = 320;

/// Below these the photo is flagged. Both sit near the 1st percentile of the
/// validation photos, so a decent photo is rarely flagged.
const double kMinBrightness = 0.18;
const double kMinSharpness = 15;

class PhotoQuality {
  const PhotoQuality({required this.brightness, required this.sharpness});

  /// Mean luminance, 0..1.
  final double brightness;

  /// Variance of the Laplacian of the 224x224 grey crop (0..255 scale).
  final double sharpness;

  bool get tooDark => brightness < kMinBrightness;
  bool get blurry => sharpness < kMinSharpness;
  bool get ok => !tooDark && !blurry;
}

class PreparedImage {
  const PreparedImage({required this.tensor, required this.cropPng, required this.quality});

  /// Float32 [1, 3, 224, 224], RGB in 0..1. The model normalizes internally.
  final Float32List tensor;

  /// The exact square the model looked at, for showing under the heatmap.
  final Uint8List cropPng;

  final PhotoQuality quality;
}

/// Decode, turn upright, resize and centre-crop like `eval_transform` in
/// ml/scripts/common.py. Pure Dart, so it can run in a background isolate.
PreparedImage prepareImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Not an image Tanim can read.');
  }
  final crop = centreCrop(img.bakeOrientation(decoded));
  final rgb = crop.getBytes(order: img.ChannelOrder.rgb);
  return PreparedImage(tensor: toTensor(rgb), cropPng: img.encodePng(crop), quality: measureQuality(rgb));
}

img.Image centreCrop(img.Image source) {
  var image = source.convert(numChannels: 3, format: img.Format.uint8);
  final shortSide = math.min(image.width, image.height);
  if (shortSide > _cacheShortSide) {
    image = _resizeShortSide(image, _cacheShortSide, img.Interpolation.average);
  }
  image = _resizeShortSide(image, kModelSize, img.Interpolation.linear);
  return img.copyCrop(
    image,
    x: (image.width - kModelSize) ~/ 2,
    y: (image.height - kModelSize) ~/ 2,
    width: kModelSize,
    height: kModelSize,
  );
}

img.Image _resizeShortSide(img.Image image, int side, img.Interpolation how) {
  final scale = side / math.min(image.width, image.height);
  return img.copyResize(
    image,
    width: math.max(side, (image.width * scale).round()),
    height: math.max(side, (image.height * scale).round()),
    interpolation: how,
  );
}

/// Interleaved RGB bytes -> planar float32 [1, 3, H, W] in 0..1.
Float32List toTensor(Uint8List rgb) {
  const plane = kModelSize * kModelSize;
  final out = Float32List(3 * plane);
  for (var i = 0; i < plane; i++) {
    out[i] = rgb[i * 3] / 255;
    out[plane + i] = rgb[i * 3 + 1] / 255;
    out[2 * plane + i] = rgb[i * 3 + 2] / 255;
  }
  return out;
}

/// Same definitions used to pick the thresholds from the validation photos.
PhotoQuality measureQuality(Uint8List rgb) {
  const n = kModelSize;
  final grey = Float64List(n * n);
  var sum = 0.0;
  for (var i = 0; i < n * n; i++) {
    final g = 0.299 * rgb[i * 3] + 0.587 * rgb[i * 3 + 1] + 0.114 * rgb[i * 3 + 2];
    grey[i] = g;
    sum += g;
  }
  var lapSum = 0.0;
  var lapSq = 0.0;
  for (var y = 1; y < n - 1; y++) {
    for (var x = 1; x < n - 1; x++) {
      final i = y * n + x;
      final lap = grey[i - n] + grey[i + n] + grey[i - 1] + grey[i + 1] - 4 * grey[i];
      lapSum += lap;
      lapSq += lap * lap;
    }
  }
  const count = (n - 2) * (n - 2);
  final mean = lapSum / count;
  return PhotoQuality(brightness: sum / (n * n) / 255, sharpness: lapSq / count - mean * mean);
}
