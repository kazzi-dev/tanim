import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tanim/features/scan/data/leaf_classifier.dart';

import 'fixtures.g.dart';

/// Runs the real int8 model through ONNX Runtime on a device and checks it
/// agrees with Python. Generate the embedded photos first, then run on a phone
/// or desktop:
///   dart run tool/embed_fixtures.dart
///   flutter test integration_test -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on-device predictions match Python', (tester) async {
    final expected = jsonDecode(fixtureExpectedJson) as Map<String, dynamic>;
    final images = (expected['images'] as List).cast<Map<String, dynamic>>();
    final classes = (expected['classes'] as List).cast<String>();
    final classifier = await LeafClassifier.load();

    var agree = 0;
    var worst = 0.0;
    for (final fixture in images) {
      final stopwatch = Stopwatch()..start();
      final d = await classifier.diagnose(base64Decode(fixturePhotosBase64[fixture['file']]!));
      stopwatch.stop();
      final python = (fixture['probs_int8'] as List).cast<num>();
      final pythonTop = python.indexOf(python.reduce((a, b) => a > b ? a : b));
      if (d.top.index == pythonTop) agree++;
      for (var i = 0; i < python.length; i++) {
        final gap = (d.probabilities[i] - python[i]).abs();
        if (gap > worst) worst = gap;
      }
      // Timings and per-photo results are the point of running this by hand.
      // ignore: avoid_print
      print(
        '${fixture['file']}: ${d.top.label} ${(d.confidence * 100).round()}% '
        '(python ${classes[pythonTop]} ${(python[pythonTop] * 100).round()}%) '
        '${stopwatch.elapsedMilliseconds} ms',
      );
      expect(d.cams, hasLength(5));
      expect(d.cams.first, hasLength(49));
    }
    // Summary line for whoever runs this by hand.
    // ignore: avoid_print
    print('agree $agree/${images.length}, largest probability gap ${worst.toStringAsFixed(3)}');
    expect(agree, images.length);
    expect(worst, lessThan(0.1));
    await classifier.close();
  });
}
