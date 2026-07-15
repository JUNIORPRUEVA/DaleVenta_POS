// Gallery Content Controller & State Management
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../data/gallery_content_api.dart';
import '../models/gallery_content_model.dart';

// ─── State Model ────────────────────────────────────────────────────────────

class GalleryContentState {
  const GalleryContentState({
    this.allItems = const [],
    this.filteredItems = const [],
    this.selectedItems = const {},
    this.currentFilter = 'todo',
    this.searchQuery = '',
    this.loading = false,
    this.uploading = false,
    this.busy = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
  });

  final List<GalleryContentItem> allItems;
  final List<GalleryContentItem> filteredItems;
  final Set<String> selectedItems;
  final String currentFilter;
  final String searchQuery;
  final bool loading;
  final bool uploading;
  final bool busy;
  final String? error;
  final int page;
  final bool hasMore;

  GalleryContentState copyWith({
    List<GalleryContentItem>? allItems,
    List<GalleryContentItem>? filteredItems,
    Set<String>? selectedItems,
    String? currentFilter,
    String? searchQuery,
    bool? loading,
    bool? uploading,
    bool? busy,
    String? error,
    bool clearError = false,
    int? page,
    bool? hasMore,
  }) {
    return GalleryContentState(
      allItems: allItems ?? this.allItems,
      filteredItems: filteredItems ?? this.filteredItems,
      selectedItems: selectedItems ?? this.selectedItems,
      currentFilter: currentFilter ?? this.currentFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      loading: loading ?? this.loading,
      uploading: uploading ?? this.uploading,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────────

final galleryContentControllerProvider =
    StateNotifierProvider<GalleryContentController, GalleryContentState>((ref) {
      // In a real app, inject Dio via ref.read(dioProvider)
      // For now, this would be wired in your main app setup
      throw UnimplementedError('Provide GalleryContentApi instance');
    });

class GalleryContentController extends StateNotifier<GalleryContentState> {
  GalleryContentController(this._api) : super(const GalleryContentState()) {
    _init();
  }

  final GalleryContentApi _api;

  void _init() {
    loadContent();
  }

  // ─── Load & Refresh ──────────────────────────────────────────────────

  Future<void> loadContent({bool refresh = false}) async {
    if (state.loading) return;

    state = state.copyWith(
      loading: true,
      clearError: refresh,
      page: refresh ? 1 : state.page,
    );

    try {
      final items = await _api.loadAllContent(
        filterId: state.currentFilter == 'todo' ? null : state.currentFilter,
        searchQuery: state.searchQuery.isEmpty ? null : state.searchQuery,
        page: state.page,
        limit: 50,
      );

      final allItems = refresh ? items : [...state.allItems, ...items];
      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        loading: false,
        hasMore: items.length == 50,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: _formatError(error));
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loading) return;
    await loadContent();
    state = state.copyWith(page: state.page + 1);
  }

  // ─── Filter & Search ────────────────────────────────────────────────

  void setFilter(String filterId) {
    state = state.copyWith(
      currentFilter: filterId,
      selectedItems: const {},
      page: 1,
    );
    loadContent(refresh: true);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(
      searchQuery: query,
      selectedItems: const {},
      page: 1,
    );
    loadContent(refresh: true);
  }

  void clearSearch() {
    state = state.copyWith(searchQuery: '', selectedItems: const {}, page: 1);
    loadContent(refresh: true);
  }

  // ─── Selection ──────────────────────────────────────────────────────

  void toggleSelection(String id) {
    final updated = {...state.selectedItems};
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(selectedItems: updated);
  }

  void selectAll() {
    final ids = state.filteredItems.map((item) => item.id).toSet();
    state = state.copyWith(selectedItems: ids);
  }

  void clearSelection() {
    state = state.copyWith(selectedItems: const {});
  }

  bool isSelected(String id) => state.selectedItems.contains(id);

  // ─── Favorites ──────────────────────────────────────────────────────

  Future<void> toggleFavorite(String id) async {
    try {
      final item = state.allItems.firstWhere((i) => i.id == id);
      await _api.toggleFavorite(id, favorite: !item.favorito);

      final updated = state.allItems
          .map((i) => i.id == id ? i.copyWith(favorito: !i.favorito) : i)
          .toList();

      final filtered = _filterItems(updated);

      state = state.copyWith(allItems: updated, filteredItems: filtered);
    } catch (error) {
      state = state.copyWith(error: _formatError(error));
    }
  }

  Future<void> bulkToggleFavorite(bool favorite) async {
    if (state.selectedItems.isEmpty) return;

    try {
      await _api.bulkToggleFavorite(
        state.selectedItems.toList(),
        favorite: favorite,
      );

      final updated = state.allItems
          .map(
            (i) => state.selectedItems.contains(i.id)
                ? i.copyWith(favorito: favorite)
                : i,
          )
          .toList();

      final filtered = _filterItems(updated);

      state = state.copyWith(
        allItems: updated,
        filteredItems: filtered,
        selectedItems: const {},
      );
    } catch (error) {
      state = state.copyWith(error: _formatError(error));
    }
  }

  // ─── Metadata Updates ───────────────────────────────────────────────

  Future<void> updateMetadata(
    String id, {
    String? categoria,
    String? descripcion,
    List<String>? tags,
    List<ContentUsage>? usadoEn,
  }) async {
    try {
      state = state.copyWith(busy: true, clearError: true);

      final updated = await _api.updateMetadata(
        id,
        categoria: categoria,
        descripcion: descripcion,
        tags: tags,
        usadoEn: usadoEn,
      );

      final allItems = state.allItems
          .map((i) => i.id == id ? updated : i)
          .toList();

      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        busy: false,
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _formatError(error));
    }
  }

  // ─── Upload Content ────────────────────────────────────────────────

  Future<void> uploadContent({
    required String filePath,
    required ContentType type,
    required String categoria,
    required String descripcion,
    required List<String> tags,
    required List<ContentUsage> usadoEn,
  }) async {
    try {
      state = state.copyWith(uploading: true, clearError: true);

      final newItem = await _api.uploadContent(
        filePath: filePath,
        type: type,
        categoria: categoria,
        descripcion: descripcion,
        tags: tags,
        usadoEn: usadoEn,
      );

      final allItems = [newItem, ...state.allItems];
      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        uploading: false,
      );
    } catch (error) {
      state = state.copyWith(uploading: false, error: _formatError(error));
    }
  }

  // ─── Import Operations ──────────────────────────────────────────────

  Future<void> importFromProducts(List<String> productIds) async {
    if (productIds.isEmpty) return;

    try {
      state = state.copyWith(busy: true, clearError: true);

      final imported = await _api.importFromProducts(productIds: productIds);

      final allItems = [...imported, ...state.allItems];
      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        busy: false,
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _formatError(error));
    }
  }

  Future<void> importFromGlobalGallery(List<String> mediaIds) async {
    if (mediaIds.isEmpty) return;

    try {
      state = state.copyWith(busy: true, clearError: true);

      final imported = await _api.importFromGlobalGallery(mediaIds: mediaIds);

      final allItems = [...imported, ...state.allItems];
      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        busy: false,
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _formatError(error));
    }
  }

  // ─── Bulk Deletion ──────────────────────────────────────────────────

  Future<void> deleteSelected() async {
    if (state.selectedItems.isEmpty) return;

    try {
      state = state.copyWith(busy: true, clearError: true);

      await _api.bulkDelete(state.selectedItems.toList());

      final allItems = state.allItems
          .where((i) => !state.selectedItems.contains(i.id))
          .toList();

      final filtered = _filterItems(allItems);

      state = state.copyWith(
        allItems: allItems,
        filteredItems: filtered,
        selectedItems: const {},
        busy: false,
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _formatError(error));
    }
  }

  // ─── Filtering Logic ────────────────────────────────────────────────

  List<GalleryContentItem> _filterItems(List<GalleryContentItem> items) {
    var filtered = items;

    // Apply filter
    if (state.currentFilter != 'todo') {
      filtered = _applyFilter(filtered, state.currentFilter);
    }

    // Apply search
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (item) =>
                item.descripcion.toLowerCase().contains(query) ||
                item.categoria.toLowerCase().contains(query) ||
                item.tags.any((t) => t.toLowerCase().contains(query)),
          )
          .toList();
    }

    return filtered;
  }

  List<GalleryContentItem> _applyFilter(
    List<GalleryContentItem> items,
    String filterId,
  ) {
    switch (filterId) {
      case 'imagenes':
        return items.where((i) => i.isImage).toList();
      case 'videos':
        return items.where((i) => i.isVideo).toList();
      case 'productos':
        return items.where((i) => i.origen == ContentOrigin.producto).toList();
      case 'instalaciones':
        return items
            .where(
              (i) =>
                  i.categoria.toLowerCase().contains('instalación') ||
                  i.tags.any((t) => t.toLowerCase().contains('instalación')),
            )
            .toList();
      case 'estados_publicados':
        return items
            .where(
              (i) => i.publicado && i.usadoEn.contains(ContentUsage.estados),
            )
            .toList();
      case 'campanas_publicadas':
        return items
            .where(
              (i) => i.publicado && i.usadoEn.contains(ContentUsage.campanas),
            )
            .toList();
      case 'marketplace_publicado':
        return items
            .where(
              (i) =>
                  i.publicado && i.usadoEn.contains(ContentUsage.marketplace),
            )
            .toList();
      case 'favoritos':
        return items.where((i) => i.favorito).toList();
      case 'recientes':
        final now = DateTime.now();
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return items.where((i) => i.fecha.isAfter(sevenDaysAgo)).toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));
      default:
        return items;
    }
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      return error.message.isNotEmpty ? error.message : 'Error en galería';
    }
    return 'No se pudo completar la operación';
  }
}
