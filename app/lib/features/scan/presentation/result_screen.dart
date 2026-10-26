import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/features/collect/domain/sample.dart';
import 'package:tanim/features/collect/presentation/label_screen.dart';
import 'package:tanim/features/scan/application/scan_providers.dart';
import 'package:tanim/features/scan/data/leaf_classifier.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';
import 'package:tanim/features/scan/domain/disease.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({required this.photoPath, super.key});
  final String photoPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(diagnosisProvider(photoPath));
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: switch (result) {
        AsyncData(:final value) => _ResultBody(diagnosis: value, photoPath: photoPath),
        AsyncError(:final error) => _Failure(error: error, onRetry: () => ref.invalidate(diagnosisProvider(photoPath))),
        _ => const _Checking(),
      },
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Checking the leaf…')],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is FormatException
        ? (error as FormatException).message
        : 'Something went wrong reading this photo.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(onPressed: () => context.pop(), child: const Text('Take another photo')),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.diagnosis, required this.photoPath});
  final Diagnosis diagnosis;
  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final d = diagnosis;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        _HeatmapPhoto(diagnosis: d),
        const SizedBox(height: 16),
        if (!d.quality.ok) ...[_QualityWarning(diagnosis: d), const SizedBox(height: 16)],
        if (d.sure) _SureHeadline(diagnosis: d) else _UnsureHeadline(diagnosis: d),
        const SizedBox(height: 24),
        if (d.sure) _Advice(disease: d.top) else _Advice(disease: d.top, tentative: true),
        const SizedBox(height: 24),
        _OtherPossibilities(diagnosis: d),
        const SizedBox(height: 24),
        const _Disclaimer(),
        const SizedBox(height: 24),
        _SaveForTraining(diagnosis: d, photoPath: photoPath),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Scan another leaf'),
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}

class _HeatmapPhoto extends StatefulWidget {
  const _HeatmapPhoto({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  State<_HeatmapPhoto> createState() => _HeatmapPhotoState();
}

class _HeatmapPhotoState extends State<_HeatmapPhoto> {
  bool _showHeatmap = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(widget.diagnosis.cropPng, fit: BoxFit.cover, gaplessPlayback: true),
                AnimatedOpacity(
                  opacity: _showHeatmap ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Image.memory(
                    widget.diagnosis.heatmapPng,
                    fit: BoxFit.cover,
                    semanticLabel: 'Heatmap of where Tanim looked',
                  ),
                ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show where Tanim looked'),
          subtitle: const Text('Red areas shaped the answer most.'),
          value: _showHeatmap,
          onChanged: (v) => setState(() => _showHeatmap = v),
        ),
      ],
    );
  }
}

class _QualityWarning extends StatelessWidget {
  const _QualityWarning({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final q = diagnosis.quality;
    final problem = q.tooDark && q.blurry
        ? 'too dark and blurry'
        : q.tooDark
        ? 'too dark'
        : 'blurry';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
        title: Text('This photo looks $problem', style: TextStyle(color: scheme.onErrorContainer)),
        subtitle: Text(
          'The result below may be wrong. Retake it in daylight, holding the phone steady.',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: TextButton(onPressed: () => context.pop(), child: const Text('Retake')),
      ),
    );
  }
}

class _SureHeadline extends StatelessWidget {
  const _SureHeadline({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final top = diagnosis.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(top == Disease.healthy ? 'No disease found' : 'Most likely', style: text.labelLarge),
        const SizedBox(height: 4),
        Text(top.name, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (top.cause != null) Text(top.cause!, style: text.bodyMedium),
        const SizedBox(height: 12),
        _ConfidenceBar(value: diagnosis.confidence),
      ],
    );
  }
}

class _UnsureHeadline extends StatelessWidget {
  const _UnsureHeadline({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final second = diagnosis.runnersUp.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Not sure', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          'It might be ${diagnosis.top.name.toLowerCase()} (${_pct(diagnosis.confidence)}) '
          'or ${second.$1.name.toLowerCase()} (${_pct(second.$2)}). '
          'Try a closer photo of one leaf in daylight.',
          style: text.bodyLarge,
        ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: value, minHeight: 10),
          ),
        ),
        const SizedBox(width: 12),
        Text('${_pct(value)} sure'),
      ],
    );
  }
}

class _Advice extends StatelessWidget {
  const _Advice({required this.disease, this.tentative = false});
  final Disease disease;
  final bool tentative;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tentative ? 'If it is ${disease.name.toLowerCase()}' : 'What it looks like', style: text.titleMedium),
        const SizedBox(height: 6),
        Text(disease.signs, style: text.bodyMedium),
        const SizedBox(height: 16),
        Text('What you can do', style: text.titleMedium),
        const SizedBox(height: 6),
        for (final step in disease.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 8),
                  child: Icon(Icons.check_circle_outline, size: 18),
                ),
                Expanded(child: Text(step, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _OtherPossibilities extends StatelessWidget {
  const _OtherPossibilities({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Other possibilities', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final (disease, p) in diagnosis.runnersUp)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 150, child: Text(disease.name, style: text.bodyMedium)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: p, minHeight: 6),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(_pct(p), textAlign: TextAlign.right, style: text.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Tanim is a study project, not a diagnosis. Before spraying or pulling plants, '
          'check with your Municipal Agriculture Office.',
        ),
      ),
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';

/// Hands the photo to the label screen, with Tanim's guess kept apart from the
/// person's label so field accuracy can be measured later.
class _SaveForTraining extends StatefulWidget {
  const _SaveForTraining({required this.diagnosis, required this.photoPath});
  final Diagnosis diagnosis;
  final String photoPath;

  @override
  State<_SaveForTraining> createState() => _SaveForTrainingState();
}

class _SaveForTrainingState extends State<_SaveForTraining> {
  Sample? _saved;

  Future<void> _save() async {
    final saved = await context.push<Sample>(
      Routes.label,
      extra: LabelArgs(
        photoPath: widget.photoPath,
        prediction: widget.diagnosis.top.label,
        confidence: widget.diagnosis.confidence,
        modelVersion: kModelVersion,
      ),
    );
    if (saved != null && mounted) setState(() => _saved = saved);
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return OutlinedButton.icon(
      icon: Icon(saved == null ? Icons.bookmark_add_outlined : Icons.check),
      label: Text(saved == null ? 'Save for training' : 'Saved as ${saved.label.name.toLowerCase()}'),
      onPressed: saved == null ? _save : null,
    );
  }
}
