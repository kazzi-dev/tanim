import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turn one raw class activation map (h x w, straight from the model's `cams`
/// output) into a transparent PNG overlay of [size] x [size].
///
/// Negative evidence is dropped, the map is scaled so its peak is 1, then
/// stretched with bilinear sampling (matching PyTorch's
/// `interpolate(..., align_corners=False)`) and coloured with a jet ramp.
/// Weak areas fade to transparent so the leaf stays visible.
Uint8List heatmapPng(List<double> cam, {int h = 7, int w = 7, int size = 224}) {
  final values = cam.map((v) => math.max(0, v).toDouble()).toList();
  final peak = values.fold<double>(0, math.max);
  if (peak > 0) {
    for (var i = 0; i < values.length; i++) {
      values[i] /= peak;
    }
  }

  final out = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    final sy = ((y + 0.5) * h / size - 0.5).clamp(0, h - 1).toDouble();
    final y0 = sy.floor();
    final y1 = math.min(y0 + 1, h - 1);
    final fy = sy - y0;
    for (var x = 0; x < size; x++) {
      final sx = ((x + 0.5) * w / size - 0.5).clamp(0, w - 1).toDouble();
      final x0 = sx.floor();
      final x1 = math.min(x0 + 1, w - 1);
      final fx = sx - x0;
      final v =
          (values[y0 * w + x0] * (1 - fx) + values[y0 * w + x1] * fx) * (1 - fy) +
          (values[y1 * w + x0] * (1 - fx) + values[y1 * w + x1] * fx) * fy;
      final (r, g, b) = jet(v);
      out.setPixelRgba(x, y, r, g, b, (255 * 0.7 * math.pow(v, 1.5)).round());
    }
  }
  return img.encodePng(out);
}

/// Matplotlib-style jet: blue -> cyan -> yellow -> red.
(int, int, int) jet(double v) {
  int channel(double centre) => (255 * (1.5 - (4 * v - centre).abs()).clamp(0.0, 1.0)).round();
  return (channel(3), channel(2), channel(1));
}
