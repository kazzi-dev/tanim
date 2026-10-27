import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/core/theme/app_theme.dart';
import 'package:tanim/core/widgets/ios.dart';
import 'package:tanim/features/collect/domain/sample.dart';
import 'package:tanim/features/collect/presentation/label_screen.dart';
import 'package:tanim/features/scan/application/scan_providers.dart';
import 'package:tanim/features/scan/data/leaf_classifier.dart';
import 'package:tanim/features/scan/domain/diagnosis.dart';
import 'package:tanim/features/scan/domain/disease.dart';

/// Photo first: the square the model saw fills the top, the answer sits in a
/// sheet underneath, and the advice follows as inset grouped sections.
class ResultScreen extends ConsumerWidget {
  const ResultScreen({required this.photoPath, super.key});
  final String photoPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(diagnosisProvider(photoPath));
    return switch (result) {
      AsyncData(:final value) => _ResultBody(diagnosis: value, photoPath: photoPath),
      AsyncError(:final error) => _Plain(
        child: _Failure(error: error, onRetry: () => ref.invalidate(diagnosisProvider(photoPath))),
      ),
      _ => const _Plain(child: _Checking()),
    };
  }
}

class _Plain extends StatelessWidget {
  const _Plain({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Result')),
    body: child,
  );
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CupertinoActivityIndicator(radius: 14),
        const SizedBox(height: 14),
        Text('Checking the leaf…', style: TextStyle(color: context.colors.secondaryLabel, fontSize: 15)),
      ],
    ),
  );
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
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            PillButton(label: 'Try again', onPressed: onRetry),
            const SizedBox(height: 10),
            PillButton(label: 'Take another photo', tinted: true, onPressed: () => context.pop()),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends StatefulWidget {
  const _ResultBody({required this.diagnosis, required this.photoPath});
  final Diagnosis diagnosis;
  final String photoPath;

  @override
  State<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends State<_ResultBody> {
  bool _showHeatmap = true;

  @override
  Widget build(BuildContext context) {
    final d = widget.diagnosis;
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // white status bar over the photo
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Photo and sheet share one sliver: a viewport paints later slivers
                // underneath earlier ones, which would hide the sheet's rounded top.
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Photo(diagnosis: d, showHeatmap: _showHeatmap),
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.background,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Grabber(),
                                const SizedBox(height: 18),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: d.sure ? _SureHeadline(diagnosis: d) : _UnsureHeadline(diagnosis: d),
                                ),
                                const SizedBox(height: 14),
                                _Others(diagnosis: d),
                                if (!d.quality.ok) ...[const SizedBox(height: 20), _QualityWarning(diagnosis: d)],
                                const SizedBox(height: 28),
                                _Advice(disease: d.top, tentative: !d.sure),
                                const SizedBox(height: 28),
                                PillButton(
                                  label: 'Scan another leaf',
                                  icon: CupertinoIcons.camera,
                                  onPressed: () => context.pop(),
                                ),
                                const SizedBox(height: 10),
                                _SaveForTraining(diagnosis: d, photoPath: widget.photoPath),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GlassButton(icon: CupertinoIcons.chevron_back, tooltip: 'Back', onPressed: () => context.pop()),
                    const Spacer(),
                    GlassButton(
                      icon: _showHeatmap ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                      label: _showHeatmap ? 'Hide heatmap' : 'Show heatmap',
                      tooltip: _showHeatmap ? 'Hide heatmap' : 'Show heatmap',
                      onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exact square the model looked at, edge to edge, with the heatmap.
class _Photo extends StatelessWidget {
  const _Photo({required this.diagnosis, required this.showHeatmap});
  final Diagnosis diagnosis;
  final bool showHeatmap;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(diagnosis.cropPng, fit: BoxFit.cover, gaplessPlayback: true),
        AnimatedOpacity(
          opacity: showHeatmap ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Image.memory(
            diagnosis.heatmapPng,
            fit: BoxFit.cover,
            semanticLabel: 'Heatmap of where Tanim looked. Red areas shaped the answer most.',
          ),
        ),
      ],
    ),
  );
}

class _SureHeadline extends StatelessWidget {
  const _SureHeadline({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final top = diagnosis.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top == Disease.healthy ? 'No disease found' : 'Most likely',
          style: TextStyle(fontSize: 15, color: c.secondaryLabel),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(top.name, style: text.headlineMedium)),
            const SizedBox(width: 12),
            Text(
              '${_pct(diagnosis.confidence)} sure',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.accent, letterSpacing: -0.3),
            ),
          ],
        ),
        if (top.cause != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(top.cause!, style: TextStyle(fontSize: 15, color: c.secondaryLabel)),
          ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: diagnosis.confidence,
            minHeight: 6,
            backgroundColor: c.fill,
            color: c.accent,
          ),
        ),
      ],
    );
  }
}

class _UnsureHeadline extends StatelessWidget {
  const _UnsureHeadline({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final second = diagnosis.runnersUp.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Not sure', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'It might be ${diagnosis.top.name.toLowerCase()} (${_pct(diagnosis.confidence)}) '
          'or ${second.$1.name.toLowerCase()} (${_pct(second.$2)}). '
          'Try a closer photo of one leaf in daylight.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colors.secondaryLabel),
        ),
      ],
    );
  }
}

class _Others extends StatelessWidget {
  const _Others({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      // Under 1% would read as "0%" and look broken; leave those out.
      for (final (disease, p) in diagnosis.runnersUp.where((r) => r.$2 >= 0.01))
        PillTag('${disease == Disease.bacterialLeafBlight ? 'Leaf blight' : disease.name} ${_pct(p)}'),
    ],
  );
}

class _QualityWarning extends StatelessWidget {
  const _QualityWarning({required this.diagnosis});
  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = diagnosis.quality;
    final problem = q.tooDark && q.blurry
        ? 'too dark and blurry'
        : q.tooDark
        ? 'too dark'
        : 'blurry';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(color: c.dangerBackground, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill, color: c.danger, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This photo looks $problem',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.label),
                ),
                const SizedBox(height: 2),
                Text(
                  'The result may be wrong. Retake it in daylight, holding the phone steady.',
                  style: TextStyle(fontSize: 13, color: c.secondaryLabel, height: 1.35),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => context.pop(),
            child: Text(
              'Retake',
              style: TextStyle(color: c.danger, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _Advice extends StatelessWidget {
  const _Advice({required this.disease, this.tentative = false});
  final Disease disease;
  final bool tentative;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedSection(
          header: tentative ? 'If it is ${disease.name.toLowerCase()}' : 'What it looks like',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(disease.signs, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
        const SizedBox(height: 24),
        GroupedSection(
          header: 'What you can do',
          footer:
              'Tanim is a study project, not a diagnosis. Before spraying or pulling plants, '
              'check with your Municipal Agriculture Office.',
          children: [
            for (final (i, step) in disease.steps.indexed)
              GroupedRow(
                leading: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: c.accent, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                title: step,
              ),
          ],
        ),
      ],
    );
  }
}

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
    return PillButton(
      tinted: true,
      icon: saved == null ? CupertinoIcons.bookmark : CupertinoIcons.checkmark_alt,
      label: saved == null ? 'Save for training' : 'Saved as ${saved.label.name.toLowerCase()}',
      onPressed: saved == null ? _save : null,
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';
