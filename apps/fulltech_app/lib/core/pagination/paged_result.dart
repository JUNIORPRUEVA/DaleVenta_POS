/// Contrato de paginacion unico del backend FULLPOS.
///
/// El backend devuelve siempre la misma envoltura para listas paginadas:
///
/// ```json
/// { "items": [...], "page": 1, "limit": 50, "total": 103,
///   "hasMore": true, "nextPage": 2 }
/// ```
///
/// Reglas que este tipo hace explicitas (evitan el bug de "dataset parcial
/// tratado como completo"):
///  - `items` es SOLO la pagina actual;
///  - `total` es el total DESPUES de filtros y ANTES de paginar (puede ser
///    `null` si el servidor no lo calcula: nunca se inventa);
///  - `hasMore == true` significa que existen mas registros alcanzables con
///    `nextPage`;
///  - una pagina parcial NUNCA debe guardarse como si fuera el dataset
///    completo (ver `isComplete`).
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.hasMore,
    this.total,
    this.nextPage,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int? total;
  final bool hasMore;
  final int? nextPage;

  /// true solo si esta pagina contiene TODO el conjunto (no hay mas paginas).
  bool get isComplete => hasMore != true;

  /// Numero de elementos cargados hasta ahora respecto al total conocido.
  String describeProgress() {
    if (total == null) return '${items.length}';
    return '${items.length}/$total';
  }

  static const PagedResult<Never> empty = PagedResult<Never>(
    items: <Never>[],
    page: 1,
    limit: 0,
    hasMore: false,
    total: 0,
    nextPage: null,
  );

  /// Extrae las filas de una respuesta del backend aceptando tanto la
  /// envoltura nueva como una lista plana (respuestas legacy).
  static List<dynamic> extractRows(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const ['items', 'data', 'products', 'rows']) {
        final candidate = data[key];
        if (candidate is List) return candidate;
      }
    }
    return const <dynamic>[];
  }

  /// Construye el resultado paginado a partir de la respuesta cruda.
  ///
  /// Si la respuesta es una lista plana (cliente/backend legacy) se interpreta
  /// como un conjunto completo de una sola pagina.
  static PagedResult<T> fromResponse<T>(
    dynamic data,
    T Function(Map<String, dynamic> row) parse,
  ) {
    final rows = extractRows(data);
    final items = <T>[];
    for (final row in rows) {
      if (row is Map) {
        items.add(parse(Map<String, dynamic>.from(row)));
      }
    }

    if (data is Map) {
      final page = _asInt(data['page']) ?? 1;
      final limit = _asInt(data['limit']) ?? items.length;
      final total = _asInt(data['total']);
      final hasMore = data['hasMore'] == true;
      final nextPage = _asInt(data['nextPage']) ??
          (hasMore ? page + 1 : null);
      return PagedResult<T>(
        items: items,
        page: page,
        limit: limit,
        total: total,
        hasMore: hasMore,
        nextPage: hasMore ? nextPage : null,
      );
    }

    return PagedResult<T>(
      items: items,
      page: 1,
      limit: items.length,
      total: items.length,
      hasMore: false,
      nextPage: null,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Acumula paginas sin duplicar por id, descartando respuestas obsoletas.
class PagedAccumulator<T> {
  PagedAccumulator({required this.parse});

  final T Function(Map<String, dynamic> row) parse;
  final List<T> _items = <T>[];
  final Set<String> _seenIds = <String>{};

  List<T> get items => List<T>.unmodifiable(_items);
  int get length => _items.length;

  /// Agrega una pagina. `idOf` debe devolver un identificador estable.
  void addPage(PagedResult<T> page, String Function(T item) idOf) {
    for (final item in page.items) {
      if (_seenIds.add(idOf(item))) {
        _items.add(item);
      }
    }
  }

  bool addItem(T item, String Function(T item) idOf) {
    if (_seenIds.add(idOf(item))) {
      _items.add(item);
      return true;
    }
    return false;
  }

  void clear() {
    _items.clear();
    _seenIds.clear();
  }
}
