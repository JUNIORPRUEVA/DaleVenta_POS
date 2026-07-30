import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/env.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/product_image_url.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_sync_utils.dart';

class CatalogState {
  final List<ProductModel> items;
  final bool loading;
  final bool refreshing;
  final String? error;
  final bool saving;
  final String? actionError;

  const CatalogState({
    this.items = const [],
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.saving = false,
    this.actionError,
  });

  CatalogState copyWith({
    List<ProductModel>? items,
    bool? loading,
    bool? refreshing,
    String? error,
    bool? saving,
    String? actionError,
    bool clearError = false,
  }) {
    return CatalogState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      saving: saving ?? this.saving,
      actionError: clearError ? null : (actionError ?? this.actionError),
    );
  }
}

final catalogControllerProvider =
    StateNotifierProvider<CatalogController, CatalogState>((ref) {
      return CatalogController(ref);
    });

class CatalogImportDraft {
  const CatalogImportDraft({
    required this.nombre,
    required this.precio,
    required this.costo,
    required this.stock,
    required this.categoria,
  });

  final String nombre;
  final double precio;
  final double costo;
  final double stock;
  final String categoria;
}

class CatalogController extends StateNotifier<CatalogState> {
  final Ref ref;
  static const _silentRefreshMinInterval = Duration(seconds: 20);
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;

  CatalogController(this.ref) : super(const CatalogState());

  String _newProductOperationId(String action, {String? productId}) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final suffix = productId == null ? '' : '-$productId';
    return '$action-$now-$hashCode$suffix';
  }

  Future<void> load({bool silent = false, bool forceRemote = false}) async {
    if (silent && forceRemote && _remoteRefreshInFlight) return;
    if (silent &&
        forceRemote &&
        state.items.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }
    if (silent && forceRemote) {
      _remoteRefreshInFlight = true;
    }

    final shouldShowLoading = !silent || state.items.isEmpty;

    if (shouldShowLoading && state.items.isEmpty) {
      state = state.copyWith(
        loading: true,
        refreshing: false,
        clearError: true,
      );
    } else if (shouldShowLoading) {
      state = state.copyWith(
        loading: false,
        refreshing: true,
        clearError: true,
      );
    } else {
      state = state.copyWith(clearError: true);
    }

    try {
      final repo = ref.read(catalogRepositoryProvider);
      final fetched = await repo.fetchProducts(
        forceRefresh: forceRemote,
        silent: silent,
      );
      final merged = mergeRecoveredCatalogImages(
        previousItems: state.items,
        fetchedItems: fetched,
      );
      final syncVersion = buildCatalogSyncVersion(merged);
      final items = applyCatalogSyncVersion(merged, syncVersion);
      state = state.copyWith(items: items, loading: false, refreshing: false);
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          items.map((item) => item.displayFotoUrl),
        ),
      );
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar los productos';
      // Keep cached/previous items (if any) so UI doesn't go blank.
      if (silent && state.items.isNotEmpty) return;
      state = state.copyWith(loading: false, refreshing: false, error: message);
    } finally {
      if (silent && forceRemote) {
        _remoteRefreshInFlight = false;
      }
    }
  }

  Future<void> create({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    required String categoria,
    List<int>? imageBytes,
    String? filename,
    String? operationId,
  }) async {
    if (state.saving) return;
    state = state.copyWith(saving: true, actionError: null);
    final saveOperationId = operationId ?? _newProductOperationId('create');
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? path;
      if (imageBytes != null && filename != null) {
        path = await repo.uploadImage(bytes: imageBytes, filename: filename);
        final cachedUrl = buildProductImageUrl(
          imageUrl: path,
          baseUrl: Env.apiBaseUrl,
        );
        unawaited(
          FulltechImageCacheManager.putImageBytes(
            url: cachedUrl,
            bytes: imageBytes,
            filename: filename,
          ),
        );
      }
      final created = await repo.createProduct(
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: path,
        categoria: categoria,
        operationId: saveOperationId,
      );
      final updated = [created, ...state.items];
      state = state.copyWith(items: updated, saving: false);
      await load(forceRemote: true, silent: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo crear el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<int> importProducts(List<CatalogImportDraft> drafts) async {
    if (drafts.isEmpty) return 0;
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      var createdCount = 0;
      for (final draft in drafts) {
        await repo.createProduct(
          nombre: draft.nombre,
          precio: draft.precio,
          costo: draft.costo,
          stock: draft.stock,
          categoria: draft.categoria,
          operationId: _newProductOperationId('import-${createdCount + 1}'),
        );
        createdCount += 1;
      }
      state = state.copyWith(saving: false);
      await load(forceRemote: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
      return createdCount;
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron importar los productos';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> update({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    required String categoria,
    List<int>? newImageBytes,
    String? newFilename,
    String? operationId,
  }) async {
    if (state.saving) return;
    state = state.copyWith(saving: true, actionError: null);
    final saveOperationId =
        operationId ?? _newProductOperationId('update', productId: id);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? fotoUrl;
      if (newImageBytes != null && newFilename != null) {
        fotoUrl = await repo.uploadImage(
          bytes: newImageBytes,
          filename: newFilename,
        );
        final cachedUrl = buildProductImageUrl(
          imageUrl: fotoUrl,
          baseUrl: Env.apiBaseUrl,
        );
        unawaited(
          FulltechImageCacheManager.putImageBytes(
            url: cachedUrl,
            bytes: newImageBytes,
            filename: newFilename,
          ),
        );
      }
      final updated = await repo.updateProduct(
        id: id,
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl,
        categoria: categoria,
        operationId: saveOperationId,
      );
      final list = state.items.map((p) => p.id == id ? updated : p).toList();
      state = state.copyWith(items: list, saving: false);
      await load(forceRemote: true, silent: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo actualizar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<void> adjustStock({
    required ProductModel product,
    required double stock,
  }) {
    return update(
      id: product.id,
      nombre: product.nombre,
      codigo: product.codigo,
      precio: product.precio,
      costo: product.costo,
      stock: stock,
      categoria: product.categoriaLabel,
    );
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      await repo.deleteProduct(id);
      final list = state.items.where((p) => p.id != id).toList();
      state = state.copyWith(items: list, saving: false);
      await load(forceRemote: true, silent: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo eliminar el producto';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }

  Future<int> purgeAllDebug() async {
    state = state.copyWith(saving: true, actionError: null);
    try {
      final result = await ref.read(catalogRepositoryProvider).purgeAllDebug();
      state = state.copyWith(items: const [], saving: false, clearError: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
      return (result['deletedProducts'] as num?)?.toInt() ?? 0;
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron limpiar los productos';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
  }
}
