import 'package:tanim/features/scan/domain/disease.dart';

/// What a person says is on the leaf. The five model classes plus two escape
/// hatches, so nobody is forced to guess.
enum SampleLabel {
  bacterialLeafBlight('bacterial_leaf_blight', 'Bacterial leaf blight'),
  blast('blast', 'Rice blast'),
  brownSpot('brown_spot', 'Brown spot'),
  tungro('tungro', 'Tungro'),
  healthy('healthy', 'Healthy'),
  other('other', 'Something else'),
  unsure('unsure', 'Not sure');

  SampleLabel(this.id, this.name);

  /// Written to labels.csv; the first five match the model's class names.
  final String id;
  final String name;

  static SampleLabel fromId(String id) => values.firstWhere((l) => l.id == id);
  static SampleLabel fromDisease(Disease d) => fromId(d.label);
}

/// Labels from an agriculturist are worth more than a guess; keep track.
enum LabelledBy {
  me('self', 'Me'),
  farmer('farmer', 'Farmer'),
  agriculturist('agriculturist', 'Agriculturist');

  LabelledBy(this.id, this.name);
  final String id;
  final String name;

  static LabelledBy fromId(String id) => values.firstWhere((l) => l.id == id);
}

class Sample {
  const Sample({
    required this.id,
    required this.label,
    required this.labelledBy,
    required this.takenAt,
    this.note = '',
    this.modelPrediction,
    this.modelConfidence,
    this.modelVersion,
  });

  factory Sample.fromJson(Map<String, dynamic> json) => Sample(
    id: json['id'] as String,
    label: SampleLabel.fromId(json['label'] as String),
    labelledBy: LabelledBy.fromId(json['labelled_by'] as String),
    takenAt: DateTime.parse(json['taken_at'] as String),
    note: json['note'] as String? ?? '',
    modelPrediction: json['model_prediction'] as String?,
    modelConfidence: (json['model_confidence'] as num?)?.toDouble(),
    modelVersion: json['model_version'] as String?,
  );

  /// Also the photo's file name without extension.
  final String id;
  final SampleLabel label;
  final LabelledBy labelledBy;
  final DateTime takenAt;
  final String note;

  /// What Tanim guessed, when the photo was saved from a result. Kept apart
  /// from [label] so field accuracy can be measured later.
  final String? modelPrediction;
  final double? modelConfidence;
  final String? modelVersion;

  String get photoName => '$id.jpg';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label.id,
    'labelled_by': labelledBy.id,
    'taken_at': takenAt.toIso8601String(),
    'note': note,
    'model_prediction': modelPrediction,
    'model_confidence': modelConfidence,
    'model_version': modelVersion,
  };
}
