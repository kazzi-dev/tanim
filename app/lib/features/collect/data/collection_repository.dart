import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tanim/features/collect/domain/sample.dart';

/// Labelled photos for training, kept in the app's private storage:
///
///   collection/samples.json      the labels
///   collection/photos/ID.jpg     the original photos, untouched
class CollectionRepository {
  CollectionRepository(this.root);

  static Future<CollectionRepository> open() async =>
      CollectionRepository(Directory('${(await getApplicationDocumentsDirectory()).path}/collection'));

  final Directory root;

  File get _index => File('${root.path}/samples.json');
  Directory get _photos => Directory('${root.path}/photos');

  File photoFile(Sample sample) => File('${_photos.path}/${sample.photoName}');

  Future<List<Sample>> load() async {
    if (!_index.existsSync()) return [];
    final list = jsonDecode(await _index.readAsString()) as List;
    return [for (final item in list) Sample.fromJson(item as Map<String, dynamic>)]
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  /// Copies the photo in, so it survives the camera's temp files being cleared.
  Future<Sample> add({
    required String photoPath,
    required SampleLabel label,
    required LabelledBy labelledBy,
    String note = '',
    String? modelPrediction,
    double? modelConfidence,
    String? modelVersion,
    DateTime? now,
  }) async {
    final takenAt = now ?? DateTime.now();
    final sample = Sample(
      id: _newId(takenAt),
      label: label,
      labelledBy: labelledBy,
      takenAt: takenAt,
      note: note.trim(),
      modelPrediction: modelPrediction,
      modelConfidence: modelConfidence,
      modelVersion: modelVersion,
    );
    await _photos.create(recursive: true);
    await File(photoPath).copy(photoFile(sample).path);
    await _save([sample, ...await load()]);
    return sample;
  }

  Future<void> delete(Sample sample) async {
    await _save([
      for (final s in await load())
        if (s.id != sample.id) s,
    ]);
    final photo = photoFile(sample);
    if (photo.existsSync()) await photo.delete();
  }

  /// A zip with one folder per label plus labels.csv, ready for
  /// ml/scripts/import_collection.py. Built off the UI thread.
  Future<File> exportZip(Directory outDir, {DateTime? now}) async {
    final samples = await load();
    final photos = {for (final s in samples) s.id: photoFile(s).path};
    final stamp = _stamp(now ?? DateTime.now());
    final bytes = await Isolate.run(() => buildZip(samples, photos));
    final out = File('${outDir.path}/tanim_photos_$stamp.zip');
    await out.writeAsBytes(bytes);
    return out;
  }

  Future<void> _save(List<Sample> samples) async {
    await root.create(recursive: true);
    // Write then rename, so a crash mid-write can't leave half a file.
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in samples) s.toJson()]));
    await tmp.rename(_index.path);
  }

  static final _random = Random();

  static String _newId(DateTime t) => '${_stamp(t)}_${_random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')}';

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

const labelsCsvColumns = [
  'file',
  'label',
  'labelled_by',
  'taken_at',
  'note',
  'model_prediction',
  'model_confidence',
  'model_version',
];

List<int> buildZip(List<Sample> samples, Map<String, String> photoPaths) {
  final archive = Archive();
  final csv = StringBuffer()..writeln(labelsCsvColumns.join(','));
  for (final s in samples) {
    final file = File(photoPaths[s.id]!);
    if (!file.existsSync()) continue;
    final name = '${s.label.id}/${s.photoName}';
    archive.addFile(ArchiveFile.bytes(name, file.readAsBytesSync()));
    csv.writeln(
      [
        name,
        s.label.id,
        s.labelledBy.id,
        s.takenAt.toIso8601String(),
        s.note,
        s.modelPrediction ?? '',
        s.modelConfidence?.toStringAsFixed(4) ?? '',
        s.modelVersion ?? '',
      ].map(_csvField).join(','),
    );
  }
  archive
    ..addFile(ArchiveFile.string('labels.csv', csv.toString()))
    ..addFile(ArchiveFile.string('README.txt', _readme));
  return ZipEncoder().encodeBytes(archive);
}

String _csvField(String v) => v.contains(RegExp('[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

const _readme = '''
Tanim training photos

One folder per label. labels.csv has one row per photo:
  label            what the person said is on the leaf
  labelled_by      self, farmer or agriculturist
  model_prediction what Tanim guessed, if the photo was saved from a result

Import on the laptop with:
  .venv/Scripts/python ml/scripts/import_collection.py tanim_photos_<date>.zip
''';
