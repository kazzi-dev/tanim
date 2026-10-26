import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/features/collect/application/collection_controller.dart';
import 'package:tanim/features/collect/data/collection_repository.dart';
import 'package:tanim/features/collect/domain/sample.dart';

/// The photos saved for training, with export to a zip for the laptop.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = ref.watch(collectionProvider);
    final repo = ref.watch(collectionRepositoryProvider).value;
    final hasPhotos = samples.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training photos'),
        actions: [
          if (hasPhotos && repo != null)
            IconButton(
              tooltip: 'Export all',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _export(context, repo),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Collect'),
        onPressed: () => context.push(Routes.collect),
      ),
      body: switch (samples) {
        AsyncData(:final value) when value.isEmpty => const _Empty(),
        AsyncData(:final value) when repo != null => _Grid(samples: value, repo: repo),
        AsyncError() => const Center(child: Text('Could not read the saved photos.')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _export(BuildContext context, CollectionRepository repo) async {
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(const SnackBar(content: Text('Packing photos…'), duration: Duration(seconds: 30)));
    try {
      final zip = await repo.exportZip(await getTemporaryDirectory());
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          subject: 'Tanim training photos',
        ),
      );
    } on FileSystemException {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not pack the photos. Is the phone full?')));
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco_outlined, size: 48),
            const SizedBox(height: 16),
            Text('No training photos yet', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Photograph rice leaves in the field and say what is on them. '
              'These photos teach Tanim what Philippine fields look like.\n\n'
              'Photos stay on this phone until you export them.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.samples, required this.repo});
  final List<Sample> samples;
  final CollectionRepository repo;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final l in SampleLabel.values) l: samples.where((s) => s.label == l).length};
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${samples.length} photos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: label, value: n) in counts.entries)
                      if (n > 0) Chip(label: Text('${label.name} $n'), visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: samples.length,
            itemBuilder: (context, i) => _Tile(sample: samples[i], file: repo.photoFile(samples[i])),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.sample, required this.file});
  final Sample sample;
  final File file;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _Details(sample: sample, file: file),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(file, fit: BoxFit.cover, cacheWidth: 320),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Text(
                  sample.label.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.sample, required this.file});
  final Sample sample;
  final File file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final t = sample.takenAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(file, fit: BoxFit.cover, cacheWidth: 900),
              ),
            ),
            const SizedBox(height: 16),
            Text(sample.label.name, style: text.titleLarge),
            Text('Labelled by ${sample.labelledBy.name.toLowerCase()} · $when', style: text.bodyMedium),
            if (sample.modelPrediction != null)
              Text(
                'Tanim guessed ${SampleLabel.fromId(sample.modelPrediction!).name.toLowerCase()} '
                '(${((sample.modelConfidence ?? 0) * 100).round()}%)',
                style: text.bodyMedium,
              ),
            if (sample.note.isNotEmpty) ...[const SizedBox(height: 8), Text(sample.note, style: text.bodyMedium)],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete photo'),
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Delete this photo?'),
                    content: const Text('It will be removed from the phone and from future exports.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (sure ?? false) {
                  await ref.read(collectionProvider.notifier).delete(sample);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
