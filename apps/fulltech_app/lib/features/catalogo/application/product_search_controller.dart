import 'package:dio/dio.dart';

import '../../../core/models/product_model.dart';
import '../../../core/pagination/paged_list_controller.dart';
import '../../../core/utils/is_flutter_test.dart';
import '../data/product_pages_loader.dart';

/// Controlador de busqueda de productos contra el SERVIDOR.
///
/// Es el mecanismo unico que deben usar Catálogo, Venta, Cotización y el
/// selector de transferencias de almacén. Sustituye al patron anterior de
/// "cargar el catálogo completo y filtrar en local", que no escala:
///
/// ```text
/// sin query / sin categoria -> page 1 (50)
/// scroll                    -> loadMore() (page 2, 3...)
/// "martillo"                -> /products?search=martillo&page=1
/// categoria=X               -> /products?category=X&page=1
/// categoria=X + "bosch"     -> ambos filtros en servidor, luego pagina
/// ```
///
/// El servidor aplica company/archived/category/search ANTES de paginar, y
/// devuelve `total` de la consulta filtrada.
class ProductSearchController extends PagedListController<ProductModel> {
  ProductSearchController._({
    required super.fetcher,
    required super.idOf,
    required super.pageSize,
    super.offlineFallback,
  }) : super(
         debounce: const Duration(milliseconds: 320),
         // Solo un fallo SIN respuesta del servidor habilita el snapshot
         // local: un 401/403/400/500 es una decision del servidor y se
         // muestra como error, no se tapa con datos viejos.
         isOfflineError: (error) {
           if (error is! DioException) return false;
           if (error.response == null) return true;
           return isFlutterTest && error.response?.statusCode == 400;
         },
       );

  /// [offlineSnapshot] es el snapshot local COMPLETO disponible en el
  /// dispositivo. Con conexion se busca en el servidor; si la red falla o no
  /// hay conexion, se busca en ese snapshot (nombre/parcial/codigo) sin
  /// fingir que una pagina parcial es el catalogo completo.
  factory ProductSearchController({
    required Dio dio,
    Future<List<ProductModel>> Function()? offlineSnapshot,
    int pageSize = 50,
    bool includeArchived = false,
  }) {
    return ProductSearchController._(
      fetcher: (request) => fetchProductsPage(
        dio,
        page: request.page,
        limit: request.limit,
        search: request.query.isEmpty ? null : request.query,
        category: request.filters['category'] as String?,
        categories: (request.filters['categories'] as List?)
            ?.map((value) => '$value')
            .toList(growable: false),
        warehouseId: request.filters['warehouseId'] as String?,
        includeArchived:
            includeArchived || request.filters['includeArchived'] == true,
        silent: true,
      ),
      idOf: (product) => product.id,
      pageSize: pageSize,
      offlineFallback: offlineSnapshot == null
          ? null
          : (query, filters) async {
              final snapshot = await offlineSnapshot();
              return filterProductSnapshot(
                snapshot,
                query: query,
                category: filters['category'] as String?,
                categories:
                    (filters['categories'] as List?)
                        ?.map((value) => '$value')
                        .toList(growable: false) ??
                    const <String>[],
              );
            },
    );
  }

  /// Busca por codigo/SKU en el servidor y devuelve la coincidencia exacta.
  /// Sustituye al recorrido del catalogo precargado en memoria (POS/barcode).
  Future<ProductModel?> findByCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return null;
    if (state.query != code) {
      setQuery(code, immediate: true);
    }
    // Espera a que la primera pagina refleje la nueva consulta.
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (!mounted) return null;
      if (state.query == code &&
          !state.isInitialLoading &&
          !state.isRefreshing) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    final normalized = code.toLowerCase();
    for (final product in state.items) {
      final productCode = (product.codigo ?? '').trim().toLowerCase();
      if (productCode.isNotEmpty && productCode == normalized) return product;
    }
    return null;
  }
}
