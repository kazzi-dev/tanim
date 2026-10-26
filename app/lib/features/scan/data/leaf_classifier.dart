import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:tanim/features/scan/data/heatmap.dart';
import 'package:tanim/features/scan/data/preprocess.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';
import 'package:tanim/features/scan/domain/disease.dart';

const _modelAsset = 'assets/model/tanim_int8.onnx';
const _labelsAsset = 'assets/model/labels.json';

/// Which training run the bundled model came from; saved with each training photo.
const kModelVersion = 'mobilenet_v3_large@2026-10-26';

/// Runs the exported model (see ml/scripts/export.py) on the phone.
class LeafClassifier {
  LeafClassifier._(this._session);

  final OrtSession _session;

  static Future<LeafClassifier> load() async {
    final labels = (jsonDecode(await rootBundle.loadString(_labelsAsset)) as List).cast<String>();
    final expected = Disease.values.map((d) => d.label).toList();
    if (labels.join(',') != expected.join(',')) {
      throw StateError('Model labels $labels do not match the app $expected');
    }
    final session = await OnnxRuntime().createSessionFromAsset(_modelAsset);
    return LeafClassifier._(session);
  }

  Future<Diagnosis> diagnose(Uint8List photoBytes) async {
    final prepared = await Isolate.run(() => prepareImage(photoBytes));
    final (probs, cams) = await _run(prepared.tensor);
    final top = probs.indexOf(probs.reduce((a, b) => a > b ? a : b));
    final overlay = await Isolate.run(() => heatmapPng(cams[top]));
    return Diagnosis(
      probabilities: probs,
      cams: cams,
      cropPng: prepared.cropPng,
      heatmapPng: overlay,
      quality: prepared.quality,
    );
  }

  Future<(List<double>, List<List<double>>)> _run(Float32List tensor) async {
    final input = await OrtValue.fromList(tensor, [1, 3, kModelSize, kModelSize]);
    final outputs = await _session.run({'image': input});
    try {
      final probs = (await outputs['probs']!.asFlattenedList()).map((v) => (v as num).toDouble()).toList();
      final flatCams = (await outputs['cams']!.asFlattenedList()).map((v) => (v as num).toDouble()).toList();
      final perClass = flatCams.length ~/ probs.length;
      final cams = [for (var c = 0; c < probs.length; c++) flatCams.sublist(c * perClass, (c + 1) * perClass)];
      return (probs, cams);
    } finally {
      await input.dispose();
      for (final value in outputs.values) {
        await value.dispose();
      }
    }
  }

  Future<void> close() => _session.close();
}
