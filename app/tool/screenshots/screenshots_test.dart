// Renders app screens to PNGs for the README and portfolio, using the real
// model's output on real photos (made by ml/scripts/make_screenshot_data.py).
// Not part of `flutter test`; run it on its own:
//
//   flutter test --update-goldens tool/screenshots/screenshots_test.dart
//
// Output: tool/screenshots/out/*.png at 1179 x 2556 (a 393 x 852 pt phone @3x).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/app.dart';
import 'package:tanim/features/collect/application/collection_controller.dart';
import 'package:tanim/features/collect/data/collection_repository.dart';
import 'package:tanim/features/collect/domain/sample.dart';
import 'package:tanim/features/collect/presentation/collection_screen.dart';
import 'package:tanim/features/collect/presentation/label_screen.dart';
import 'package:tanim/features/scan/application/scan_providers.dart';
import 'package:tanim/features/scan/data/heatmap.dart';
import 'package:tanim/features/scan/data/preprocess.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';
import 'package:tanim/features/scan/presentation/result_screen.dart';

const _dir = 'tool/screenshots';

/// Real Roboto and Material Icons from the Flutter SDK, instead of the test font's boxes.
Future<void> _loadFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/artifacts/material_fonts').existsSync()) {
    dir = dir.parent;
  }
  final fonts = '${dir.path}/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(File('$fonts/$f').readAsBytesSync());
  await (FontLoader('Roboto')
        ..addFont(read('roboto-regular.ttf'))
        ..addFont(read('roboto-medium.ttf'))
        ..addFont(read('roboto-bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(read('materialicons-regular.otf'))).load();
}

Diagnosis _diagnosis(String name) {
  final data = (jsonDecode(File('$_dir/data.json').readAsStringSync()) as Map<String, dynamic>)[name] as Map;
  final probs = [for (final p in data['probs'] as List) (p as num).toDouble()];
  final cams = [
    for (final c in data['cams'] as List) [for (final v in c as List) (v as num).toDouble()],
  ];
  final prepared = prepareImage(File('$_dir/photos/$name.jpg').readAsBytesSync());
  final top = probs.indexOf(probs.reduce((a, b) => a > b ? a : b));
  return Diagnosis(
    probabilities: probs,
    cams: cams,
    cropPng: prepared.cropPng,
    heatmapPng: heatmapPng(cams[top]),
    quality: prepared.quality,
  );
}

Future<void> _shoot(WidgetTester tester, Widget screen, String out, {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: 54 * 3, bottom: 20 * 3);
  addTearDown(tester.view.reset);
  debugDisableShadows = false; // set back by _golden before the test ends
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(collectionProvider.future));
  // Build on the real clock so photo files load and decode for real; started on
  // the test's fake clock, an Image.file load never finishes.
  await tester.runAsync(() async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: TanimApp(router: router)));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pumpAndSettle();
  await _golden(tester, out);
}

/// flutter_test draws elevation shadows as hard outlines. Real ones are switched
/// on before the screen is painted and back off after the picture, because the
/// flag must be restored before the test ends.
Future<void> _golden(WidgetTester tester, String out) async {
  debugDisableShadows = false;
  try {
    await tester.pump();
    await expectLater(find.byType(TanimApp), matchesGoldenFile('out/$out.png'));
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  late Directory tmp;
  late CollectionRepository repo;

  setUpAll(_loadFonts);
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('tanim_shots_');
    repo = CollectionRepository(Directory('${tmp.path}/collection'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<Override> base() => [collectionRepositoryProvider.overrideWith((ref) async => repo)];

  testWidgets('result: confident', (tester) async {
    await _shoot(
      tester,
      const ResultScreen(photoPath: 'sure.jpg'),
      'result_sure',
      overrides: [...base(), diagnosisProvider.overrideWith((ref, path) async => _diagnosis('sure'))],
    );
  });

  testWidgets('result: not sure', (tester) async {
    await _shoot(
      tester,
      const ResultScreen(photoPath: 'unsure.jpg'),
      'result_unsure',
      overrides: [...base(), diagnosisProvider.overrideWith((ref, path) async => _diagnosis('unsure'))],
    );
  });

  testWidgets('label screen', (tester) async {
    await _shoot(tester, const LabelScreen(args: LabelArgs(photoPath: '$_dir/photos/sure.jpg')), 'label', overrides: base());
    await tester.tap(find.text('Brown spot'));
    await tester.pumpAndSettle();
    await _golden(tester, 'label');
  });

  testWidgets('training photos', (tester) async {
    final photos = [
      ('$_dir/photos/sure.jpg', SampleLabel.brownSpot, LabelledBy.agriculturist),
      ('$_dir/photos/unsure.jpg', SampleLabel.bacterialLeafBlight, LabelledBy.farmer),
      ('test/fixtures/07_tungro_riceleafbd.jpg', SampleLabel.tungro, LabelledBy.farmer),
      ('test/fixtures/09_healthy_riceleafbd.jpg', SampleLabel.healthy, LabelledBy.me),
      ('test/fixtures/03_blast_sethy2020.jpg', SampleLabel.blast, LabelledBy.agriculturist),
      ('test/fixtures/00_bacterial_leaf_blight_riceleafbd.jpg', SampleLabel.bacterialLeafBlight, LabelledBy.farmer),
      ('test/fixtures/05_brown_spot_sethy2020.jpg', SampleLabel.brownSpot, LabelledBy.me),
      ('test/fixtures/04_brown_spot_riceleafbd.jpg', SampleLabel.unsure, LabelledBy.me),
    ];
    await tester.runAsync(() async {
      for (final (i, (path, label, by)) in photos.indexed) {
        await repo.add(photoPath: path, label: label, labelledBy: by, now: DateTime(2026, 11, 1, 9, i));
      }
    });
    await _shoot(tester, const CollectionScreen(), 'collection', overrides: base());
  });
}
