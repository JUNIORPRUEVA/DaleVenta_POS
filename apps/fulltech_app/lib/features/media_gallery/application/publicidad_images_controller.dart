import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/publicidad_images_repository.dart';
import '../models/publicidad_image_model.dart';

class PublicidadImagesController
    extends StateNotifier<AsyncValue<List<PublicidadImage>>> {
  final PublicidadImagesRepository _repository;

  PublicidadImagesController(this._repository)
    : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getAll());
  }

  Future<void> create({required String url, String? caption}) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    final image = await _repository.create(url: url, caption: caption);
    final items = [...currentState.value!, image];
    state = AsyncValue.data(items);
  }

  Future<void> delete(String id) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    await _repository.delete(id);
    final items = currentState.value!.where((e) => e.id != id).toList();
    state = AsyncValue.data(items);
  }

  Future<void> update(String id, {String? caption}) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    final updatedImage = await _repository.update(id, caption: caption);
    final items = currentState.value!
        .map((e) => e.id == id ? updatedImage : e)
        .toList();
    state = AsyncValue.data(items);
  }

  /// Upload image bytes (already read via XFile.readAsBytes()) to the API via
  /// multipart form-data. The server saves the file and creates the DB record.
  Future<void> uploadBytesAndSave({
    required Uint8List bytes,
    required String contentType,
    required String filename,
    String? caption,
  }) async {
    final image = await _repository.uploadFile(
      bytes: bytes,
      contentType: contentType,
      filename: filename,
      caption: caption,
    );
    final currentState = state;
    final existing = currentState.hasValue
        ? currentState.value!
        : <PublicidadImage>[];
    state = AsyncValue.data([image, ...existing]);
  }
}

final publicidadImagesControllerProvider =
    StateNotifierProvider<
      PublicidadImagesController,
      AsyncValue<List<PublicidadImage>>
    >((ref) {
      final repository = ref.watch(publicidadImagesRepositoryProvider);
      final controller = PublicidadImagesController(repository);
      controller.load();
      return controller;
    });
