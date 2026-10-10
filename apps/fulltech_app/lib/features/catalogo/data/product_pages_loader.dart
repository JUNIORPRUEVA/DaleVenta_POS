import 'package:dio/dio.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/models/product_model.dart';
import '../../../core/pagination/paged_result.dart';

/// Tamano de pagina usado al recorrer el catalogo completo.
const int kProductPagesPageSize = 200;

/// Tope de seguridad del recorrido: 50 x 200 = 10.000 productos.
/// No es un limite funcional: evita un bucle sin fin si el backend devolviera
/// `hasMore` de forma inconsistente. Si se alcanza, se registra como aviso.
const int kProductPagesMaxPages = 50;

/// Pide UNA pagina de `/products` respetando el envelope estandar
/// `{ items, page, limit, total, hasMore, nextPage }`.
Future<PagedResult<ProductModel>> fetchProductsPage(
  Dio dio, {
  required int page,
  required int limit,
  String? search,
  String? category,
  List<String>? categories,
  String? warehouseId,
  bool includeArchived = false,
  bool silent = true,
  Map<String, dynamic>? extra,
}) async {
  final normalizedSearch = search?.trim();
  final normalizedCategory = category?.trim();
  final normalizedCategories = (categories ?? const <String>[])
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final normalizedWarehouse = warehouseId?.trim();

  final res = await dio.get(
    ApiRoutes.catalogProducts,
    queryParameters: <String, dynamic>{
      'page': page,
      'limit': limit,
      if (normalizedSearch != null && normalizedSearch.isNotEmpty)
        'search': normalizedSearch,
      if (normalizedCategory != null && normalizedCategory.isNotEmpty)
        'category': normalizedCategory,
      if (normalizedCategories.isNotEmpty)
        'categories': normalizedCategories.join(','),
      if (normalizedWarehouse != null && normalizedWarehouse.isNotEmpty)
        'warehouseId': normalizedWarehouse,
      if (includeArchived) 'includeArchived': 'true',
    },
    options: Options(
      headers: const {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
      extra: extra ?? (silent ? const {'silent': true} : null),
    ),
  );

  return PagedResult.fromResponse(res.data, ProductModel.fromJson);
}

/// Filtra un snapshot local COMPLETO por texto y categorias.
///
/// Se usa como camino offline (sin conexion) y como fallback cuando la red
/// falla: busca por nombre, nombre parcial y codigo. Nunca se usa para
/// "simular" un dataset completo a partir de una pagina parcial.
List<ProductModel> filterProductSnapshot(
  List<ProductModel> snapshot, {
  String query = '',
  String? category,
  List<String> categories = const <String>[],
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final categorySet = <String>{
    if (category != null && category.trim().isNotEmpty) category.trim(),
    ...categories.map((value) => value.trim()).where((v) => v.isNotEmpty),
  };

  return snapshot.where((product) {
    if (categorySet.isNotEmpty &&
        !categorySet.contains(product.categoriaLabel)) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    final name = product.nombre.toLowerCase();
    final code = (product.codigo ?? '').trim().toLowerCase();
    // Mismo criterio que el servidor: nombre, codigo y categoria.
    final categoryLabel = product.categoriaLabel.toLowerCase();
    return name.contains(normalizedQuery) ||
        (code.isNotEmpty && code.contains(normalizedQuery)) ||
        categoryLabel.contains(normalizedQuery);
  }).toList(growable: false);
}

/// Recorre TODAS las paginas de `/products` y devuelve el conjunto completo.
///
/// Motivo (incidente P0 "faltan productos"): el backend paso a paginar por
/// defecto (50) mientras varios consumidores del cliente seguian leyendo solo
/// `items`, de modo que el catalogo real (103 productos) se mostraba como 50.
/// Cualquier consumidor que necesite operar sobre el catalogo completo debe
/// usar esta funcion en lugar de una unica llamada sin parametros: asi el
/// dataset local es COMPLETO y no una pagina parcial.
///
/// Para listas grandes con UI propia es preferible paginar en la pantalla
/// (`fetchProductsPage` + loadMore) y buscar en el servidor.
Future<List<ProductModel>> loadAllProductPages(
  Dio dio, {
  String? search,
  String? category,
  List<String>? categories,
  String? warehouseId,
  bool includeArchived = false,
  int pageSize = kProductPagesPageSize,
  int maxPages = kProductPagesMaxPages,
  bool silent = true,
  Map<String, dynamic>? extra,
  void Function(int loaded, int? total)? onProgress,
}) async {
  final accumulator = PagedAccumulator<ProductModel>(
    parse: ProductModel.fromJson,
  );

  var page = 1;
  var pagesVisited = 0;
  var hasMore = true;

  while (hasMore && pagesVisited < maxPages) {
    final result = await fetchProductsPage(
      dio,
      page: page,
      limit: pageSize,
      search: search,
      category: category,
      categories: categories,
      warehouseId: warehouseId,
      includeArchived: includeArchived,
      silent: silent,
      extra: extra,
    );

    accumulator.addPage(result, (product) => product.id);
    onProgress?.call(accumulator.length, result.total);

    hasMore = result.hasMore;
    pagesVisited += 1;

    final next = result.nextPage;
    if (next == null || next <= page) break;
    page = next;
  }

  return accumulator.items;
}
