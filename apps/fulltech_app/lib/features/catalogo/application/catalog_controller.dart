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
    this.codigo,
    required this.precio,
    required this.costo,
    required this.stock,
    required this.categoria,
    this.fotoUrl,
  });

  final String nombre;
  final String? codigo;
  final double precio;
  final double costo;
  final double stock;
  final String categoria;
  final String? fotoUrl;
}

class CatalogImportProgress {
  const CatalogImportProgress({
    required this.done,
    required this.total,
    required this.current,
  });

  final int done;
  final int total;
  final String current;
}

class CatalogImportResult {
  const CatalogImportResult({
    required this.created,
    required this.updated,
    required this.skippedExisting,
    required this.skippedFileDuplicates,
  });

  final int created;
  final int updated;
  final int skippedExisting;
  final int skippedFileDuplicates;

  int get processed => created + updated + skippedExisting;
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

  String _normalizeImportCode(String? value) {
    return (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _normalizeImportText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _importIdentityKey({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    required String categoria,
  }) {
    final code = _normalizeImportCode(codigo);
    if (code.isNotEmpty) return 'code:$code';
    return [
      'identity',
      _normalizeImportText(nombre),
      _normalizeImportText(categoria),
      precio.toStringAsFixed(2),
      costo.toStringAsFixed(2),
      stock.toStringAsFixed(2),
    ].join('|');
  }

  ProductModel? _findImportMatch(
    CatalogImportDraft draft,
    Map<String, ProductModel> existingByCode,
    Map<String, ProductModel> existingByIdentity,
  ) {
    final code = _normalizeImportCode(draft.codigo);
    if (code.isNotEmpty) {
      final byCode = existingByCode[code];
      if (byCode != null) return byCode;
    }
    return existingByIdentity[_importIdentityKey(
      nombre: draft.nombre,
      precio: draft.precio,
      costo: draft.costo,
      stock: draft.stock,
      categoria: draft.categoria,
    )];
  }

  bool _canContinueWithoutUploadedImage(Object error) {
    if (error is! ApiException) return false;
    final code = error.code;
    return code == null || code >= 500;
  }

  Future<String?> _resolveImportImageUrl(
    CatalogRepository repo,
    CatalogImportDraft draft,
  ) async {
    final source = (draft.fotoUrl ?? '').trim();
    if (source.isEmpty) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(source)) {
      return source;
    }
    try {
      final imported = await repo.importImageFromUrl(
        source,
        productName: draft.nombre,
      );
      return (imported ?? '').trim().isNotEmpty ? imported : source;
    } catch (_) {
      return source;
    }
  }

  Future<void> _saveSnapshotSafely(
    CatalogRepository repo,
    List<ProductModel> items,
  ) async {
    try {
      await repo.saveProductsSnapshot(items);
    } catch (_) {
      // La cache offline no debe bloquear el flujo principal del catálogo.
    }
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
      unawaited(_saveSnapshotSafely(repo, items));
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
        try {
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
        } catch (e) {
          if (!_canContinueWithoutUploadedImage(e)) rethrow;
        }
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
      unawaited(_saveSnapshotSafely(repo, updated));
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

  Future<CatalogImportResult> importProducts(
    List<CatalogImportDraft> drafts, {
    bool updateExisting = false,
    void Function(CatalogImportProgress progress)? onProgress,
  }) async {
    if (drafts.isEmpty) {
      return const CatalogImportResult(
        created: 0,
        updated: 0,
        skippedExisting: 0,
        skippedFileDuplicates: 0,
      );
    }
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final uniqueDrafts = <CatalogImportDraft>[];
      final seenFileKeys = <String>{};
      var skippedFileDuplicates = 0;
      for (final draft in drafts) {
        final key = _importIdentityKey(
          nombre: draft.nombre,
          codigo: draft.codigo,
          precio: draft.precio,
          costo: draft.costo,
          stock: draft.stock,
          categoria: draft.categoria,
        );
        if (!seenFileKeys.add(key)) {
          skippedFileDuplicates += 1;
          continue;
        }
        uniqueDrafts.add(draft);
      }

      final existingByCode = <String, ProductModel>{};
      final existingByIdentity = <String, ProductModel>{};
      for (final product in state.items) {
        final code = _normalizeImportCode(product.codigo);
        if (code.isNotEmpty) {
          existingByCode.putIfAbsent(code, () => product);
        }
        existingByIdentity.putIfAbsent(
          _importIdentityKey(
            nombre: product.nombre,
            precio: product.precio,
            costo: product.costo,
            stock: product.stock ?? 0,
            categoria: product.categoriaLabel,
          ),
          () => product,
        );
      }

      var createdCount = 0;
      var updatedCount = 0;
      var skippedExisting = 0;
      for (var index = 0; index < uniqueDrafts.length; index++) {
        final draft = uniqueDrafts[index];
        onProgress?.call(
          CatalogImportProgress(
            done: index,
            total: uniqueDrafts.length,
            current: draft.nombre,
          ),
        );
        final existing = _findImportMatch(
          draft,
          existingByCode,
          existingByIdentity,
        );
        if (existing != null) {
          if (!updateExisting) {
            skippedExisting += 1;
            continue;
          }
          final fotoUrl = await _resolveImportImageUrl(repo, draft);
          final updated = await repo.updateProduct(
            id: existing.id,
            nombre: draft.nombre,
            codigo: draft.codigo,
            precio: draft.precio,
            costo: draft.costo,
            stock: draft.stock,
            categoria: draft.categoria,
            fotoUrl: fotoUrl ?? existing.fotoUrl,
            operationId: _newProductOperationId(
              'import-update-${updatedCount + 1}',
              productId: existing.id,
            ),
          );
          existingByIdentity.remove(
            _importIdentityKey(
              nombre: existing.nombre,
              precio: existing.precio,
              costo: existing.costo,
              stock: existing.stock ?? 0,
              categoria: existing.categoriaLabel,
            ),
          );
          final updatedCode = _normalizeImportCode(updated.codigo);
          if (updatedCode.isNotEmpty) existingByCode[updatedCode] = updated;
          existingByIdentity[_importIdentityKey(
                nombre: updated.nombre,
                precio: updated.precio,
                costo: updated.costo,
                stock: updated.stock ?? 0,
                categoria: updated.categoriaLabel,
              )] =
              updated;
          updatedCount += 1;
        } else {
          final fotoUrl = await _resolveImportImageUrl(repo, draft);
          final created = await repo.createProduct(
            nombre: draft.nombre,
            codigo: draft.codigo,
            precio: draft.precio,
            costo: draft.costo,
            stock: draft.stock,
            categoria: draft.categoria,
            fotoUrl: fotoUrl,
            operationId: _newProductOperationId('import-create-${index + 1}'),
          );
          final createdCode = _normalizeImportCode(created.codigo);
          if (createdCode.isNotEmpty) existingByCode[createdCode] = created;
          existingByIdentity[_importIdentityKey(
                nombre: created.nombre,
                precio: created.precio,
                costo: created.costo,
                stock: created.stock ?? 0,
                categoria: created.categoriaLabel,
              )] =
              created;
          createdCount += 1;
        }
        onProgress?.call(
          CatalogImportProgress(
            done: index + 1,
            total: uniqueDrafts.length,
            current: draft.nombre,
          ),
        );
      }
      state = state.copyWith(saving: false);
      await load(forceRemote: true);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
      return CatalogImportResult(
        created: createdCount,
        updated: updatedCount,
        skippedExisting: skippedExisting,
        skippedFileDuplicates: skippedFileDuplicates,
      );
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
    String? fotoUrl,
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
      String? uploadedFotoUrl;
      if (newImageBytes != null && newFilename != null) {
        try {
          uploadedFotoUrl = await repo.uploadImage(
            bytes: newImageBytes,
            filename: newFilename,
          );
          final cachedUrl = buildProductImageUrl(
            imageUrl: uploadedFotoUrl,
            baseUrl: Env.apiBaseUrl,
          );
          unawaited(
            FulltechImageCacheManager.putImageBytes(
              url: cachedUrl,
              bytes: newImageBytes,
              filename: newFilename,
            ),
          );
        } catch (e) {
          if (!_canContinueWithoutUploadedImage(e)) rethrow;
        }
      }
      final updated = await repo.updateProduct(
        id: id,
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: uploadedFotoUrl ?? fotoUrl,
        categoria: categoria,
        operationId: saveOperationId,
      );
      final list = state.items
          .map(
            (p) => p.id == id && updated.displayFotoUrl == null
                ? updated.copyWith(
                    fotoUrl: p.fotoUrl,
                    originalFotoUrl: p.originalFotoUrl,
                    imageVersion: p.imageVersion,
                  )
                : (p.id == id ? updated : p),
          )
          .toList();
      state = state.copyWith(items: list, saving: false);
      unawaited(_saveSnapshotSafely(repo, list));
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
    final currentItems = state.items;
    final index = currentItems.indexWhere((product) => product.id == id);
    if (index < 0) return;
    final removed = currentItems[index];
    final nextItems = [
      for (final product in currentItems)
        if (product.id != id) product,
    ];
    state = state.copyWith(
      items: nextItems,
      saving: false,
      clearError: true,
      actionError: null,
    );

    final repo = ref.read(catalogRepositoryProvider);
    unawaited(
      repo
          .deleteProduct(id, skipLoader: true)
          .then((_) async {
            await load(forceRemote: true, silent: true);
            _lastSuccessfulRemoteSyncAt = DateTime.now();
          })
          .catchError((Object e) {
            final current = state.items;
            if (current.any((product) => product.id == id)) return;
            final restored = [...current];
            final safeIndex = index.clamp(0, restored.length);
            restored.insert(safeIndex, removed);
            final message = e is ApiException
                ? e.message
                : 'No se pudo eliminar el producto';
            state = state.copyWith(items: restored, actionError: message);
            unawaited(_saveSnapshotSafely(repo, restored));
          }),
    );
    unawaited(_saveSnapshotSafely(repo, nextItems));
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
