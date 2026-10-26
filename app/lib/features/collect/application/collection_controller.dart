import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tanim/features/collect/data/collection_repository.dart';
import 'package:tanim/features/collect/domain/sample.dart';

final collectionRepositoryProvider = FutureProvider<CollectionRepository>((ref) => CollectionRepository.open());

final collectionProvider = AsyncNotifierProvider<CollectionController, List<Sample>>(CollectionController.new);

class CollectionController extends AsyncNotifier<List<Sample>> {
  Future<CollectionRepository> get _repo => ref.read(collectionRepositoryProvider.future);

  @override
  Future<List<Sample>> build() async => await (await ref.watch(collectionRepositoryProvider.future)).load();

  Future<Sample> add({
    required String photoPath,
    required SampleLabel label,
    required LabelledBy labelledBy,
    String note = '',
    String? modelPrediction,
    double? modelConfidence,
    String? modelVersion,
  }) async {
    final repo = await _repo;
    final sample = await repo.add(
      photoPath: photoPath,
      label: label,
      labelledBy: labelledBy,
      note: note,
      modelPrediction: modelPrediction,
      modelConfidence: modelConfidence,
      modelVersion: modelVersion,
    );
    state = AsyncData(await repo.load());
    return sample;
  }

  Future<void> delete(Sample sample) async {
    final repo = await _repo;
    await repo.delete(sample);
    state = AsyncData(await repo.load());
  }
}
