import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tanim/features/scan/data/preprocess.dart';
import 'package:tanim/features/scan/domain/disease.dart';

/// Fixtures come from ml/scripts/make_app_fixtures.py, which runs the same
/// photos through the Python pipeline the model was trained and checked with.
final _expected = jsonDecode(File('test/fixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;
final List<Map<String, dynamic>> _images = (_expected['images'] as List).cast<Map<String, dynamic>>();

List<double> _pool28(Float32List tensor) {
  const n = kModelSize;
  const p = 8;
  const m = n ~/ p;
  final out = <double>[];
  for (var c = 0; c < 3; c++) {
    for (var by = 0; by < m; by++) {
      for (var bx = 0; bx < m; bx++) {
        var sum = 0.0;
        for (var y = 0; y < p; y++) {
          for (var x = 0; x < p; x++) {
            sum += tensor[c * n * n + (by * p + y) * n + bx * p + x];
          }
        }
        out.add(sum / (p * p));
      }
    }
  }
  return out;
}

void main() {
  test('class order matches the model', () {
    expect(Disease.values.map((d) => d.label).toList(), _expected['classes']);
    final labels = jsonDecode(File('assets/model/labels.json').readAsStringSync()) as List;
    expect(Disease.values.map((d) => d.label).toList(), labels);
  });

  group('prepareImage matches the Python pipeline', () {
    for (final fixture in _images) {
      test(fixture['file'] as String, () {
        final prepared = prepareImage(File('test/fixtures/${fixture['file']}').readAsBytesSync());
        expect(prepared.tensor.length, 3 * kModelSize * kModelSize);

        final dart = _pool28(prepared.tensor);
        final python = (fixture['pooled28'] as List).cast<num>();
        var diff = 0.0;
        for (var i = 0; i < dart.length; i++) {
          diff += (dart[i] - python[i]).abs();
        }
        // JPEG decoders and resize filters differ a little between PIL and
        // package:image (up to ~0.015 on very sharp, grassy photos). A wrong crop,
        // flip or channel order lands around 0.1 or more.
        expect(diff / dart.length, lessThan(0.02));
      });
    }
  });

  test('photos are turned upright using EXIF orientation', () {
    // Stored sideways: red on the left, blue on the right. EXIF 6 = "rotate 90° clockwise to view",
    // so upright the red half is on top.
    final sideways = img.Image(width: 400, height: 300);
    img.fillRect(sideways, x1: 0, y1: 0, x2: 199, y2: 299, color: img.ColorRgb8(220, 20, 20));
    img.fillRect(sideways, x1: 200, y1: 0, x2: 399, y2: 299, color: img.ColorRgb8(20, 20, 220));
    sideways.exif.imageIfd.orientation = 6;
    final t = prepareImage(img.encodeJpg(sideways, quality: 95)).tensor;

    const plane = kModelSize * kModelSize;
    double red(int x, int y) => t[y * kModelSize + x];
    double blue(int x, int y) => t[2 * plane + y * kModelSize + x];
    expect(red(112, 20), greaterThan(blue(112, 20)), reason: 'top should be red');
    expect(blue(112, 200), greaterThan(red(112, 200)), reason: 'bottom should be blue');
  });

  test('a dark photo is flagged, a flat photo is flagged as blurry', () {
    final dark = img.Image(width: 300, height: 300);
    img.fill(dark, color: img.ColorRgb8(10, 12, 8));
    final quality = prepareImage(img.encodePng(dark)).quality;
    expect(quality.tooDark, isTrue);
    expect(quality.blurry, isTrue);
  });

  test('the quality check passes sharp photos and flags the soft Sethy one', () {
    PhotoQuality quality(String file) => prepareImage(File('test/fixtures/$file').readAsBytesSync()).quality;
    expect(quality('00_bacterial_leaf_blight_riceleafbd.jpg').ok, isTrue);
    expect(quality('02_blast_bd5.jpg').ok, isTrue);
    // An upscaled, soft photo: sharpness ~12, under the 1st-percentile cut-off.
    expect(quality('01_bacterial_leaf_blight_sethy2020.jpg').blurry, isTrue);
  });

  test('a non-image is rejected', () {
    expect(() => prepareImage(Uint8List.fromList(utf8.encode('not a photo'))), throwsFormatException);
  });
}
