import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/core/theme/app_theme.dart';
import 'package:tanim/core/widgets/ios.dart';
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

/// Ask what is really on the leaf, iOS picker style. Pops with the saved
/// [Sample], or null.
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t save the photo. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final guess = widget.args.prediction;
    return Scaffold(
      appBar: AppBar(title: const Text('Label photo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(File(widget.args.photoPath), fit: BoxFit.cover, cacheWidth: 800),
            ),
          ),
          const SizedBox(height: 28),
          GroupedSection(
            header: 'What is on this leaf?',
            footer: guess == null
                ? 'Pick what you know from the field, not a guess.'
                : 'Tanim guessed ${SampleLabel.fromId(guess).name.toLowerCase()}. '
                      'Pick what you know from the field, not what Tanim said.',
            children: [
              for (final label in SampleLabel.values)
                GroupedRow(
                  title: label.name,
                  onTap: () => setState(() => _label = label),
                  trailing: Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 20,
                    color: _label == label ? c.accent : Colors.transparent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          GroupedSection(
            header: 'Who says so?',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: CupertinoSlidingSegmentedControl<LabelledBy>(
                  groupValue: _by,
                  onValueChanged: (v) => setState(() => _by = v ?? _by),
                  children: {for (final by in LabelledBy.values) by: Text(by.name)},
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          GroupedSection(
            header: 'Note',
            children: [
              TextField(
                controller: _note,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 17, color: c.label),
                decoration: InputDecoration(
                  hintText: 'Variety, barangay, days after planting…',
                  hintStyle: TextStyle(color: c.tertiaryLabel),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          PillButton(label: _saving ? 'Saving…' : 'Save photo', onPressed: _label == null || _saving ? null : _save),
        ],
      ),
    );
  }
}
