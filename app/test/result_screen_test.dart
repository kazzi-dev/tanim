import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:tanim/app.dart';
import 'package:tanim/features/scan/application/scan_providers.dart';
import 'package:tanim/features/scan/data/heatmap.dart';
import 'package:tanim/features/scan/data/preprocess.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';
import 'package:tanim/features/scan/presentation/result_screen.dart';

Diagnosis _diagnosis(List<double> probs, {PhotoQuality quality = const PhotoQuality(brightness: 0.5, sharpness: 200)}) {
  final crop = img.encodePng(img.Image(width: 224, height: 224));
  final cam = List<double>.generate(49, (i) => i.toDouble());
  return Diagnosis(
    probabilities: probs,
    cams: List.filled(5, cam),
    cropPng: crop,
    heatmapPng: heatmapPng(cam),
    quality: quality,
  );
}

Future<void> _show(WidgetTester tester, Diagnosis diagnosis) async {
  // A tall phone screen, so the whole result is laid out.
  tester.view.physicalSize = const Size(1200, 7200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const ResultScreen(photoPath: 'leaf.jpg'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [diagnosisProvider.overrideWith((ref, path) async => diagnosis)],
      child: TanimApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a confident result names the disease and what to do', (tester) async {
    await _show(tester, _diagnosis([0.03, 0.88, 0.05, 0.02, 0.02]));

    expect(find.text('Rice blast'), findsOneWidget);
    expect(find.text('88% sure'), findsOneWidget);
    expect(find.text('WHAT YOU CAN DO'), findsOneWidget);
    expect(find.textContaining('Municipal Agriculture Office'), findsOneWidget);
    expect(find.text('Not sure'), findsNothing);
  });

  testWidgets('a low-confidence result says it is not sure and names both options', (tester) async {
    await _show(tester, _diagnosis([0.45, 0.05, 0.05, 0.40, 0.05]));

    expect(find.text('Not sure'), findsOneWidget);
    expect(find.textContaining('bacterial leaf blight (45%)'), findsOneWidget);
    expect(find.textContaining('tungro (40%)'), findsOneWidget);
  });

  testWidgets('a dark photo shows a warning with a retake button', (tester) async {
    await _show(
      tester,
      _diagnosis([0.02, 0.02, 0.02, 0.02, 0.92], quality: const PhotoQuality(brightness: 0.05, sharpness: 200)),
    );

    expect(find.text('This photo looks too dark'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('No disease found'), findsOneWidget);
  });

  testWidgets('the heatmap can be switched off', (tester) async {
    await _show(tester, _diagnosis([0.03, 0.88, 0.05, 0.02, 0.02]));

    final opacity = find.byType(AnimatedOpacity);
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    await tester.tap(find.byTooltip('Hide heatmap'));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
  });

  test('fixtures exist', () => expect(Directory('test/fixtures').existsSync(), isTrue));
}
