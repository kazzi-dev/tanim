import 'dart:typed_data';

import 'package:tanim/features/scan/data/preprocess.dart';
import 'package:tanim/features/scan/domain/disease.dart';

/// Below this top-class probability Tanim says it isn't sure. The model is
/// trained with label smoothing, so even easy photos top out around 0.9.
const double kConfidentAt = 0.70;

class Diagnosis {
  const Diagnosis({
    required this.probabilities,
    required this.cams,
    required this.cropPng,
    required this.heatmapPng,
    required this.quality,
  });

  /// One probability per [Disease], in enum order.
  final List<double> probabilities;

  /// Raw class activation maps, 7x7 per [Disease], in enum order.
  final List<List<double>> cams;

  final Uint8List cropPng;

  /// Overlay for [top].
  final Uint8List heatmapPng;

  final PhotoQuality quality;

  Disease get top => Disease.values[_topIndex];
  double get confidence => probabilities[_topIndex];
  bool get sure => confidence >= kConfidentAt;

  /// Other classes in order of probability, for "it could also be".
  List<(Disease, double)> get runnersUp {
    final ranked = [for (final d in Disease.values) (d, probabilities[d.index])]..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked.skip(1).toList();
  }

  int get _topIndex {
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return best;
  }
}
