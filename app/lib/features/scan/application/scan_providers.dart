import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tanim/features/scan/data/leaf_classifier.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';

/// Anything that can turn photo bytes into a [Diagnosis]. Tests swap in a fake.
abstract interface class Diagnoser {
  Future<Diagnosis> diagnose(Uint8List photoBytes);
}

class _OnnxDiagnoser implements Diagnoser {
  _OnnxDiagnoser(this._classifier);
  final LeafClassifier _classifier;

  @override
  Future<Diagnosis> diagnose(Uint8List photoBytes) => _classifier.diagnose(photoBytes);
}

final diagnoserProvider = FutureProvider<Diagnoser>((ref) async {
  final classifier = await LeafClassifier.load();
  ref.onDispose(classifier.close);
  return _OnnxDiagnoser(classifier);
});

/// A diagnosis for one photo, keyed by its path.
final FutureProviderFamily<Diagnosis, String> diagnosisProvider = FutureProvider.autoDispose.family<Diagnosis, String>((
  ref,
  path,
) async {
  final diagnoser = await ref.watch(diagnoserProvider.future);
  final bytes = await XFile(path).readAsBytes();
  return await diagnoser.diagnose(bytes);
});

/// Cameras on this device; empty when there are none or listing fails.
final camerasProvider = FutureProvider<List<CameraDescription>>((ref) async {
  try {
    return await availableCameras();
  } on CameraException {
    return const [];
  }
});
