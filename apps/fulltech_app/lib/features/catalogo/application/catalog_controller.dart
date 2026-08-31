import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/env.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/local_file_bytes.dart';
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
    this.taxTreatment,
    this.taxRate,
    this.taxPriceMode,
  });

  final String nombre;
  final String? codigo;
  final double precio;
  final double costo;
  final double stock;
  final String categoria;
  final String? fotoUrl;
  final String? taxTreatment;
  final double? taxRate;
  final String? taxPriceMode;
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
  int _loadRequestSeq = 0;
  int _mutationSeq = 0;
  final Map<String, _ConfirmedCatalogMutation> _confirmedMutations = {};
  final Set<String> _confirmedDeletedIds = <String>{};

  CatalogController(this.ref) : super(const CatalogState());

  List<ProductModel> _upsertProduct(
    List<ProductModel> items,
    ProductModel product,
  ) {
    final next = <ProductModel>[];
    var replaced = false;
    for (final item in items) {
      if (item.id == product.id) {
        next.add(product);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) {
      next.insert(0, product);
    }
    return next;
  }

  void _rememberConfirmedMutation(ProductModel product) {
    _confirmedDeletedIds.remove(product.id);
    _confirmedMutations[product.id] = _ConfirmedCatalogMutation(
      product: product,
      mutationSeq: _mutationSeq,
    );
  }

  void _markConfirmedDelete(String productId) {
    _confirmedMutations.remove(productId);
    _confirmedDeletedIds.add(productId);
  }

  List<ProductModel> _reconcileFetchedItems(List<ProductModel> fetchedItems) {
    final remoteById = {
      for (final product in fetchedItems)
        if (!_confirmedDeletedIds.contains(product.id)) product.id: product,
    };

    for (final entry in _confirmedMutations.entries) {
      remoteById[entry.key] = entry.value.product;
    }

    final ordered = <ProductModel>[];
    final usedIds = <String>{};

    for (final product in fetchedItems) {
      if (_confirmedDeletedIds.contains(product.id)) continue;
      final resolved = remoteById[product.id];
      if (resolved == null || !usedIds.add(product.id)) continue;
      ordered.add(resolved);
    }

    for (final entry in _confirmedMutations.entries) {
      if (!usedIds.add(entry.key)) continue;
      ordered.insert(0, entry.value.product);
    }

    return ordered;
  }

  void _pruneConfirmedMutations(List<ProductModel> items) {
    final remoteById = {for (final item in items) item.id: item};
    final removable = <String>[];
    for (final entry in _confirmedMutations.entries) {
      final remote = remoteById[entry.key];
      if (remote == null) continue;
      if (areCatalogProductsEquivalent([entry.value.product], [remote])) {
        removable.add(entry.key);
      }
    }
    for (final id in removable) {
      _confirmedMutations.remove(id);
    }
  }

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

  /// Siembra la caché local de la imagen recién subida usando SIEMPRE la
  /// versión optimizada (nunca el original gigante). En móvil la imagen ya
  /// está optimizada (≤1600 px, JPEG), por lo que leer sus bytes para la
  /// caché es seguro y barato.
  Future<void> _seedImageCache({
    required String url,
    List<int>? bytes,
    String? filePath,
    String? filename,
  }) async {
    List<int>? optimized = bytes;
    if (optimized == null && (filePath ?? '').trim().isNotEmpty) {
      try {
        optimized = await readLocalFileBytes(filePath!);
      } catch (_) {
        optimized = null;
      }
    }
    if (optimized == null || optimized.isEmpty) return;
    await FulltechImageCacheManager.putImageBytes(
      url: url,
      bytes: optimized,
      filename: filename,
    );
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
    final loadRequestSeq = ++_loadRequestSeq;
    final loadMutationSeq = _mutationSeq;

    final requestCompanyId =
        ref.read(authStateProvider).user?.companyId?.trim() ?? '';

    final repo = ref.read(catalogRepositoryProvider);
    if (state.items.isEmpty) {
      final cached = await repo.getCachedProducts();
      if (!mounted) return;
      if (loadRequestSeq != _loadRequestSeq ||
          loadMutationSeq != _mutationSeq) {
        return;
      }
      if (cached.isNotEmpty &&
          (requestCompanyId.isEmpty ||
              ref.read(authStateProvider).user?.companyId?.trim() ==
                  requestCompanyId)) {
        final catalogVersion = buildCatalogSyncVersion(cached);
        state = state.copyWith(
          items: applyCatalogSyncVersion(cached, catalogVersion),
          loading: false,
          refreshing: false,
          clearError: true,
        );
      }
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
      final fetched = await repo.fetchProducts(
        forceRefresh: forceRemote,
        silent: silent,
      );
      if (requestCompanyId.isNotEmpty &&
          ref.read(authStateProvider).user?.companyId?.trim() !=
              requestCompanyId) {
        return;
      }
      if (!mounted) return;
      if (loadRequestSeq != _loadRequestSeq) {
        return;
      }
      final shouldReconcile =
          loadMutationSeq != _mutationSeq ||
          _confirmedMutations.isNotEmpty ||
          _confirmedDeletedIds.isNotEmpty;
      final reconciledFetched = shouldReconcile
          ? _reconcileFetchedItems(fetched)
          : fetched;
      final merged = mergeRecoveredCatalogImages(
        previousItems: state.items,
        fetchedItems: reconciledFetched,
      );
      final syncVersion = buildCatalogSyncVersion(merged);
      final items = applyCatalogSyncVersion(merged, syncVersion);
      _pruneConfirmedMutations(fetched);
      if (!areCatalogProductsEquivalent(state.items, items)) {
        state = state.copyWith(items: items, loading: false, refreshing: false);
      } else {
        state = state.copyWith(loading: false, refreshing: false);
      }
      unawaited(_saveSnapshotSafely(repo, items));
      unawaited(
        FulltechImageCacheManager.warmImageUrls(
          items.map((item) => item.displayFotoUrl),
        ),
      );
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar los productos';
      if (!mounted) return;
      if (loadRequestSeq != _loadRequestSeq ||
          loadMutationSeq != _mutationSeq) {
        return;
      }
      // Keep cached/previous items (if any) so UI doesn't go blank.
      if (silent && state.items.isNotEmpty) return;
      state = state.copyWith(loading: false, refreshing: false, error: message);
    }
  }

  Future<ProductModel?> create({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    required String categoria,
    String? fotoUrl,
    List<int>? imageBytes,
    String? imageFilePath,
    String? filename,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
  }) async {
    if (state.saving) return null;
    state = state.copyWith(saving: true, actionError: null);
    final saveOperationId = operationId ?? _newProductOperationId('create');
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? path;
      if ((imageBytes != null || imageFilePath != null) && filename != null) {
        try {
          path = await repo.uploadImage(
            bytes: imageBytes,
            filePath: imageFilePath,
            filename: filename,
          );
          final cachedUrl = buildProductImageUrl(
            imageUrl: path,
            baseUrl: Env.apiBaseUrl,
          );
          // Sembrar la caché SIEMPRE con la versión optimizada (nunca el
          // original gigante). En móvil se lee el archivo optimizado (pequeño).
          unawaited(
            _seedImageCache(
              url: cachedUrl,
              bytes: imageBytes,
              filePath: imageFilePath,
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
        fotoUrl: path ?? fotoUrl,
        categoria: categoria,
        operationId: saveOperationId,
        taxTreatment: taxTreatment,
        taxRate: taxRate,
        taxPriceMode: taxPriceMode,
        unitOfMeasureId: unitOfMeasureId,
        unitOfMeasure: unitOfMeasure,
      );
      _mutationSeq += 1;
      final mutationSeq = _mutationSeq;
      _rememberConfirmedMutation(created);
      final updated = _upsertProduct(state.items, created);
      state = state.copyWith(items: updated, saving: false);
      unawaited(_saveSnapshotSafely(repo, updated));
      unawaited(
        load(forceRemote: true, silent: true).then((_) {
          if (!mounted || _mutationSeq != mutationSeq) return;
          if (state.items.any((item) => item.id == created.id)) return;
          final refreshed = _upsertProduct(state.items, created);
          state = state.copyWith(items: refreshed, saving: false);
          unawaited(_saveSnapshotSafely(repo, refreshed));
        }),
      );
      return created;
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
            taxTreatment: draft.taxTreatment,
            taxRate: draft.taxRate,
            taxPriceMode: draft.taxPriceMode,
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
            taxTreatment: draft.taxTreatment,
            taxRate: draft.taxRate,
            taxPriceMode: draft.taxPriceMode,
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

  Future<ProductModel?> update({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    required String categoria,
    String? fotoUrl,
    List<int>? newImageBytes,
    String? newImageFilePath,
    String? newFilename,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
  }) async {
    if (state.saving) return null;
    state = state.copyWith(saving: true, actionError: null);
    final saveOperationId =
        operationId ?? _newProductOperationId('update', productId: id);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? uploadedFotoUrl;
      if ((newImageBytes != null || newImageFilePath != null) &&
          newFilename != null) {
        try {
          uploadedFotoUrl = await repo.uploadImage(
            bytes: newImageBytes,
            filePath: newImageFilePath,
            filename: newFilename,
          );
          final cachedUrl = buildProductImageUrl(
            imageUrl: uploadedFotoUrl,
            baseUrl: Env.apiBaseUrl,
          );
          // Sembrar la caché SIEMPRE con la versión optimizada (nunca el
          // original gigante). En móvil se lee el archivo optimizado (pequeño).
          unawaited(
            _seedImageCache(
              url: cachedUrl,
              bytes: newImageBytes,
              filePath: newImageFilePath,
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
        taxTreatment: taxTreatment,
        taxRate: taxRate,
        taxPriceMode: taxPriceMode,
        unitOfMeasureId: unitOfMeasureId,
        unitOfMeasure: unitOfMeasure,
      );
      final fallbackFotoUrl =
          (uploadedFotoUrl ?? fotoUrl)?.trim().isNotEmpty == true
          ? (uploadedFotoUrl ?? fotoUrl)!.trim()
          : null;
      final previousProduct = state.items.cast<ProductModel?>().firstWhere(
        (product) => product?.id == id,
        orElse: () => null,
      );
      final resolvedUpdated =
          updated.displayFotoUrl == null &&
              (previousProduct != null || fallbackFotoUrl != null)
          ? updated.copyWith(
              fotoUrl: previousProduct?.fotoUrl ?? fallbackFotoUrl,
              originalFotoUrl:
                  previousProduct?.originalFotoUrl ?? fallbackFotoUrl,
              imageKey: previousProduct?.imageKey,
              imageVersion: previousProduct?.imageVersion,
            )
          : updated;
      final list = state.items
          .map((p) => p.id == id ? resolvedUpdated : p)
          .toList(growable: false);
      _mutationSeq += 1;
      final mutationSeq = _mutationSeq;
      _rememberConfirmedMutation(resolvedUpdated);
      state = state.copyWith(items: list, saving: false);
      unawaited(_saveSnapshotSafely(repo, list));
      unawaited(
        load(forceRemote: true, silent: true).then((_) {
          if (!mounted || _mutationSeq != mutationSeq) return;
          final refreshed = state.items
              .map((p) => p.id == id ? resolvedUpdated : p)
              .toList();
          if (refreshed.any((p) => p.id == id)) {
            state = state.copyWith(items: refreshed, saving: false);
            unawaited(_saveSnapshotSafely(repo, refreshed));
          }
        }),
      );
      return resolvedUpdated;
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
    String? warehouseId,
    double? currentWarehouseStock,
  }) async {
    if (state.saving) return;
    state = state.copyWith(saving: true, actionError: null);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final delta = currentWarehouseStock == null
          ? null
          : stock - currentWarehouseStock;
      final updated = await repo.adjustProductStock(
        id: product.id,
        stock: delta == null ? stock : null,
        delta: delta,
        warehouseId: warehouseId,
        reason: 'Ajuste manual de stock',
      );
      final list = state.items
          .map((item) => item.id == product.id ? updated : item)
          .toList(growable: false);
      _mutationSeq += 1;
      _rememberConfirmedMutation(updated);
      state = state.copyWith(items: list, saving: false);
      unawaited(_saveSnapshotSafely(repo, list));
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo ajustar el stock';
      state = state.copyWith(saving: false, actionError: message);
      rethrow;
    }
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
    _mutationSeq += 1;
    _markConfirmedDelete(id);

    final repo = ref.read(catalogRepositoryProvider);
    unawaited(
      repo
          .deleteProduct(id, skipLoader: true)
          .then((_) async {
            await load(forceRemote: true, silent: true);
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
      _mutationSeq += 1;
      _confirmedMutations.clear();
      _confirmedDeletedIds.clear();
      state = state.copyWith(items: const [], saving: false, clearError: true);
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

class _ConfirmedCatalogMutation {
  const _ConfirmedCatalogMutation({
    required this.product,
    required this.mutationSeq,
  });

  final ProductModel product;
  final int mutationSeq;
}
