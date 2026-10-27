import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/app.dart';
import 'package:tanim/core/widgets/ios.dart';
import 'package:tanim/features/collect/application/collection_controller.dart';
import 'package:tanim/features/collect/data/collection_repository.dart';
import 'package:tanim/features/collect/domain/sample.dart';
import 'package:tanim/features/collect/presentation/collection_screen.dart';
import 'package:tanim/features/collect/presentation/label_screen.dart';

const _photo = 'test/fixtures/02_blast_bd5.jpg';

void main() {
  late Directory tmp;
  late CollectionRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tanim_collection_');
    repo = CollectionRepository(Directory('${tmp.path}/collection'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('CollectionRepository', () {
    test('add copies the photo and keeps the label, newest first', () async {
      final first = await repo.add(
        photoPath: _photo,
        label: SampleLabel.blast,
        labelledBy: LabelledBy.farmer,
        note: '  NSIC Rc 222 ',
        now: DateTime(2026, 11, 1, 9),
      );
      await repo.add(
        photoPath: _photo,
        label: SampleLabel.healthy,
        labelledBy: LabelledBy.me,
        modelPrediction: 'blast',
        modelConfidence: 0.81,
        now: DateTime(2026, 11, 1, 10),
      );

      final loaded = await repo.load();
      expect(loaded.map((s) => s.label), [SampleLabel.healthy, SampleLabel.blast]);
      expect(loaded.last.note, 'NSIC Rc 222');
      expect(loaded.last.labelledBy, LabelledBy.farmer);
      expect(loaded.first.modelPrediction, 'blast');
      expect(repo.photoFile(first).lengthSync(), File(_photo).lengthSync());
    });

    test('delete removes the row and the photo', () async {
      final s = await repo.add(photoPath: _photo, label: SampleLabel.tungro, labelledBy: LabelledBy.me);
      await repo.delete(s);
      expect(await repo.load(), isEmpty);
      expect(repo.photoFile(s).existsSync(), isFalse);
    });

    test('export zips one folder per label plus labels.csv the importer understands', () async {
      await repo.add(
        photoPath: _photo,
        label: SampleLabel.blast,
        labelledBy: LabelledBy.agriculturist,
        note: 'edge, "quoted"\nnote',
        now: DateTime(2026, 11, 1, 9),
      );
      await repo.add(photoPath: _photo, label: SampleLabel.unsure, labelledBy: LabelledBy.me);

      final zip = await repo.exportZip(tmp, now: DateTime(2026, 11, 2));
      expect(zip.path, endsWith('tanim_photos_20261102_000000.zip'));
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final names = archive.files.map((f) => f.name).toList();
      expect(names.where((n) => n.startsWith('blast/')), hasLength(1));
      expect(names.where((n) => n.startsWith('unsure/')), hasLength(1));
      expect(names, containsAll(['labels.csv', 'README.txt']));

      final csv = utf8.decode(archive.findFile('labels.csv')!.content as List<int>);
      expect(csv.split('\n').first, labelsCsvColumns.join(','));
      // Same pattern ml/scripts/import_collection.py accepts.
      final entry = RegExp(r'^([a-z_]+)/([0-9]{8}_[0-9]{6}_[0-9a-f]{4})\.jpg$');
      for (final n in names.where((n) => n.endsWith('.jpg'))) {
        expect(entry.hasMatch(n), isTrue, reason: n);
      }
      expect(csv, contains('"edge, ""quoted""\nnote"'));
    });
  });

  group('screens', () {
    Future<ProviderContainer> pump(WidgetTester tester, GoRouter router) async {
      tester.view.physicalSize = const Size(1200, 7200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [collectionRepositoryProvider.overrideWith((ref) async => repo)]);
      addTearDown(container.dispose);
      // Load the collection with real IO first; started inside the fake clock
      // (by building the screen), the file read would never finish.
      await tester.runAsync(() => container.read(collectionProvider.future));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TanimApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('label screen needs a label before saving, then saves it', (tester) async {
      Sample? popped;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () async =>
                  popped = await context.push<Sample>('/label', extra: const LabelArgs(photoPath: _photo)),
              child: const Text('open'),
            ),
          ),
          GoRoute(
            path: '/label',
            builder: (_, s) => LabelScreen(args: s.extra! as LabelArgs),
          ),
        ],
      );
      final container = await pump(tester, router);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final save = find.widgetWithText(PillButton, 'Save photo');
      expect(tester.widget<PillButton>(save).onPressed, isNull);

      await tester.tap(find.text('Tungro'));
      await tester.tap(find.text('Agriculturist'));
      await tester.enterText(find.byType(TextField), 'Barangay Tiguma');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(save);
        // The save does real file IO; let it finish outside the fake clock.
        for (var i = 0; i < 50 && popped == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(popped?.label, SampleLabel.tungro);
      expect(popped?.labelledBy, LabelledBy.agriculturist);
      expect(popped?.note, 'Barangay Tiguma');
      expect(container.read(collectionProvider).value, hasLength(1));
    });

    testWidgets('collection screen shows counts per label', (tester) async {
      await tester.runAsync(() async {
        await repo.add(photoPath: _photo, label: SampleLabel.blast, labelledBy: LabelledBy.me);
        await repo.add(photoPath: _photo, label: SampleLabel.blast, labelledBy: LabelledBy.me);
        await repo.add(photoPath: _photo, label: SampleLabel.healthy, labelledBy: LabelledBy.farmer);
      });
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const CollectionScreen())],
      );
      await pump(tester, router);

      expect(find.text('3 photos'), findsOneWidget);
      expect(find.text('Rice blast 2'), findsOneWidget);
      expect(find.text('Healthy 1'), findsOneWidget);
      expect(find.byTooltip('Export all'), findsOneWidget);
    });

    testWidgets('an empty collection explains what it is for', (tester) async {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const CollectionScreen())],
      );
      await pump(tester, router);
      expect(find.text('No training photos yet'), findsOneWidget);
      expect(find.byTooltip('Export all'), findsNothing);
    });
  });
}
