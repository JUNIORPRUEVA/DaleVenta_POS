import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'paged_result.dart';

/// Peticion normalizada que un controlador paginado envia a su fetcher.
class PagedFetchRequest {
  const PagedFetchRequest({
    required this.page,
    required this.limit,
    required this.query,
    required this.filters,
  });

  final int page;
  final int limit;
  final String query;
  final Map<String, dynamic> filters;
}

typedef PagedFetcher<T> = Future<PagedResult<T>> Function(
  PagedFetchRequest request,
);

typedef PagedIdOf<T> = String Function(T item);

/// Estado de una lista paginada por servidor.
class PagedListState<T> {
  const PagedListState({
    this.items = const [],
    this.page = 0,
    this.limit = 50,
    this.total,
    this.hasMore = false,
    this.isInitialLoading = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.error,
    this.query = '',
    this.filters = const <String, dynamic>{},
  });

  final List<T> items;
  final int page;
  final int limit;
  final int? total;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final bool isRefreshing;
  final Object? error;
  final String query;
  final Map<String, dynamic> filters;

  bool get isEmpty => items.isEmpty && !isInitialLoading;
  bool get hasItems => items.isNotEmpty;

  /// Texto de progreso honesto: nunca presenta una pagina parcial como total.
  String get progressLabel {
    if (total == null) return '${items.length}';
    return '${items.length} de $total';
  }

  PagedListState<T> copyWith({
    List<T>? items,
    int? page,
    int? limit,
    int? total,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    bool? isRefreshing,
    Object? error,
    bool clearError = false,
    String? query,
    Map<String, dynamic>? filters,
  }) {
    return PagedListState<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
      query: query ?? this.query,
      filters: filters ?? this.filters,
    );
  }
}

/// Controlador reutilizable para listas paginadas por servidor.
///
/// Reglas que garantiza (base del hotfix Large Dataset):
///  - el camino normal descarga SOLO la primera pagina;
///  - `loadMore()` agrega sin duplicar (dedupe por id);
///  - si `page 2` falla, la pagina 1 se mantiene y se puede reintentar;
///  - respuestas de consultas anteriores no pueden sobrescribir la actual
///    (token de generacion);
///  - cambiar query/filtros reinicia a la pagina 1;
///  - debounce configurable para busqueda interactiva.
///
/// No descarga el dataset completo: para eso existe un snapshot explicito
/// (ver `loadAllProductPages`, reservado a legacy/offline/export).
class PagedListController<T> extends StateNotifier<PagedListState<T>> {
  PagedListController({
    required PagedFetcher<T> fetcher,
    required PagedIdOf<T> idOf,
    int pageSize = 50,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _fetcher = fetcher,
        _idOf = idOf,
        _debounce = debounce,
        super(PagedListState<T>(limit: pageSize));

  final PagedFetcher<T> _fetcher;
  final PagedIdOf<T> _idOf;
  final Duration _debounce;

  /// Se incrementa en cada cambio de contexto (query/filtros/refresh).
  /// Las respuestas con una generacion vieja se descartan.
  int _generation = 0;
  bool _loadingMore = false;
  Timer? _debounceTimer;
  final Set<String> _seenIds = <String>{};

  int get pageSize => state.limit;

  /// Vista publica del estado (StateNotifier.state es @protected).
  PagedListState<T> get snapshot => state;

  /// Carga la primera pagina. No hace nada si ya hay contenido cargado.
  Future<void> loadInitial() async {
    if (state.hasItems || state.isInitialLoading) return;
    await _loadFirstPage();
  }

  /// Recarga desde la pagina 1 conservando los filtros actuales.
  Future<void> refresh() => _loadFirstPage(isRefresh: true);

  /// Carga la siguiente pagina si existe y no hay otra en curso.
  Future<void> loadMore() async {
    if (_loadingMore || !state.hasMore || state.isInitialLoading) return;
    final generation = _generation;
    _loadingMore = true;
    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final nextPage = state.page + 1;
      final result = await _fetcher(
        PagedFetchRequest(
          page: nextPage,
          limit: state.limit,
          query: state.query,
          filters: state.filters,
        ),
      );
      if (!mounted || generation != _generation) return;
      _appendPage(result);
      state = state.copyWith(
        page: result.page,
        hasMore: result.hasMore,
        total: result.total,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      // La pagina 1 se conserva: solo se expone el error para reintentar.
      state = state.copyWith(isLoadingMore: false, error: error);
    } finally {
      _loadingMore = false;
    }
  }

  /// Reintenta la carga adicional que fallo.
  Future<void> retryLoadMore() {
    if (state.error == null) return Future<void>.value();
    state = state.copyWith(clearError: true);
    return loadMore();
  }

  /// Cambia el texto de busqueda (con debounce) y reinicia a la pagina 1.
  void setQuery(String query, {bool immediate = false}) {
    final normalized = query.trim();
    if (normalized == state.query) return;
    state = state.copyWith(query: normalized);
    _scheduleReload(immediate: immediate);
  }

  /// Cambia filtros (categoria, estado...) y reinicia a la pagina 1.
  void setFilters(Map<String, dynamic> filters, {bool immediate = true}) {
    state = state.copyWith(filters: Map<String, dynamic>.unmodifiable(filters));
    _scheduleReload(immediate: immediate);
  }

  void patchFilter(String key, dynamic value, {bool immediate = true}) {
    final next = Map<String, dynamic>.from(state.filters);
    if (value == null || (value is String && value.trim().isEmpty)) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    setFilters(next, immediate: immediate);
  }

  /// Vuelve al estado inicial (sin filtros ni busqueda).
  Future<void> reset() {
    _debounceTimer?.cancel();
    state = PagedListState<T>(limit: state.limit);
    return _loadFirstPage();
  }

  void _scheduleReload({required bool immediate}) {
    _debounceTimer?.cancel();
    if (immediate) {
      unawaited(_loadFirstPage());
      return;
    }
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      unawaited(_loadFirstPage());
    });
  }

  Future<void> _loadFirstPage({bool isRefresh = false}) async {
    _debounceTimer?.cancel();
    _generation += 1;
    final generation = _generation;
    final hadItems = state.hasItems;

    state = state.copyWith(
      isInitialLoading: !hadItems,
      isRefreshing: hadItems,
      clearError: true,
    );

    try {
      final result = await _fetcher(
        PagedFetchRequest(
          page: 1,
          limit: state.limit,
          query: state.query,
          filters: state.filters,
        ),
      );
      if (!mounted || generation != _generation) return;
      _seenIds.clear();
      final items = <T>[];
      for (final item in result.items) {
        if (_seenIds.add(_idOf(item))) items.add(item);
      }
      state = state.copyWith(
        items: items,
        page: result.page,
        hasMore: result.hasMore,
        total: result.total,
        isInitialLoading: false,
        isRefreshing: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        // Si ya habia datos, se conservan (no se vacia la pantalla).
        items: hadItems ? state.items : const [],
        isInitialLoading: false,
        isRefreshing: false,
        error: error,
      );
    }
  }

  void _appendPage(PagedResult<T> result) {
    final merged = List<T>.from(state.items);
    for (final item in result.items) {
      if (_seenIds.add(_idOf(item))) merged.add(item);
    }
    state = state.copyWith(items: merged);
  }

  /// Permite a la UI registrar mutaciones locales sin perder la pagina.
  void upsertLocal(T item) {
    final id = _idOf(item);
    final index = state.items.indexWhere((existing) => _idOf(existing) == id);
    final next = List<T>.from(state.items);
    if (index >= 0) {
      next[index] = item;
    } else {
      _seenIds.add(id);
      next.insert(0, item);
    }
    state = state.copyWith(items: next);
  }

  void removeLocal(String id) {
    _seenIds.remove(id);
    state = state.copyWith(
      items: state.items.where((item) => _idOf(item) != id).toList(),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
