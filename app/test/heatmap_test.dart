import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanim/features/scan/data/heatmap.dart';

void main() {
  test('the hot cell of the CAM is the most opaque part of the overlay', () {
    final cam = List<double>.filled(49, -1)..[1 * 7 + 5] = 3.0; // row 1, column 5
    final overlay = img.decodePng(heatmapPng(cam))!;
    expect(overlay.width, 224);

    var best = (x: 0, y: 0, a: -1.0);
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final a = overlay.getPixel(x, y).a.toDouble();
        if (a > best.a) best = (x: x, y: y, a: a);
      }
    }
    // Cell (5, 1) covers x 160..192, y 32..64.
    expect(best.x ~/ 32, 5);
    expect(best.y ~/ 32, 1);
    // Negative evidence is clamped to nothing.
    expect(overlay.getPixel(10, 200).a, 0);
  });

  test('an all-negative CAM gives an empty overlay', () {
    final overlay = img.decodePng(heatmapPng(List<double>.filled(49, -2)))!;
    expect(overlay.getPixel(112, 112).a, 0);
  });

  test('jet runs blue to red', () {
    expect(jet(0).$3, greaterThan(jet(0).$1));
    expect(jet(1).$1, greaterThan(jet(1).$3));
  });
}
