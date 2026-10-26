import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/features/collect/application/collection_controller.dart';
import 'package:tanim/features/collect/domain/sample.dart';

class LabelArgs {
  const LabelArgs({required this.photoPath, this.prediction, this.confidence, this.modelVersion});

  final String photoPath;

  /// Set when the photo comes from a result screen.
  final String? prediction;
  final double? confidence;
  final String? modelVersion;
}

/// Ask what is really on the leaf. Pops with the saved [Sample], or null.
class LabelScreen extends ConsumerStatefulWidget {
  const LabelScreen({required this.args, super.key});
  final LabelArgs args;

  @override
  ConsumerState<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends ConsumerState<LabelScreen> {
  SampleLabel? _label;
  LabelledBy _by = LabelledBy.me;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label;
    if (label == null || _saving) return;
    setState(() => _saving = true);
    try {
      final sample = await ref
          .read(collectionProvider.notifier)
          .add(
            photoPath: widget.args.photoPath,
            label: label,
            labelledBy: _by,
            note: _note.text,
            modelPrediction: widget.args.prediction,
            modelConfidence: widget.args.confidence,
            modelVersion: widget.args.modelVersion,
          );
      if (mounted) context.pop(sample);
    } on FileSystemException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the photo. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final guess = widget.args.prediction;
    return Scaffold(
      appBar: AppBar(title: const Text('Label this photo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(File(widget.args.photoPath), fit: BoxFit.cover, cacheWidth: 800),
            ),
          ),
          const SizedBox(height: 20),
          Text('What is on this leaf?', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            guess == null
                ? 'Pick what you know from the field, not a guess.'
                : 'Tanim guessed ${SampleLabel.fromId(guess).name.toLowerCase()}. '
                      'Pick what you know from the field, not what Tanim said.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 8),
          RadioGroup<SampleLabel>(
            groupValue: _label,
            onChanged: (v) => setState(() => _label = v),
            child: Column(
              children: [
                for (final label in SampleLabel.values)
                  RadioListTile<SampleLabel>(contentPadding: EdgeInsets.zero, value: label, title: Text(label.name)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Who says so?', style: text.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<LabelledBy>(
            segments: [for (final by in LabelledBy.values) ButtonSegment(value: by, label: Text(by.name))],
            selected: {_by},
            onSelectionChanged: (s) => setState(() => _by = s.single),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Variety, barangay, days after planting…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _label == null || _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save photo'),
          ),
        ],
      ),
    );
  }
}
