import 'dart:io';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/application/product_search_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/modules/compras/compras_screen.dart').readAsStringSync();
  });

  test('Compras usa selector remoto paginado y categorias de servidor', () {
    expect(
      source,
      contains('late final ProductSearchController _productSearch'),
    );
    expect(source, contains('_productSearch.loadInitial()'));
    expect(source, contains('_productSearch.loadMore()'));
    expect(source, contains('_productSearch.setQuery(_searchCtrl.text)'));
    expect(
      source,
      contains("_productSearch.patchFilter('category', category)"),
    );
    expect(source, contains('fetchProductCategories()'));
    expect(source, isNot(contains('.fetchProducts(silent: true)')));
    expect(source, isNot(contains('loadAllProductPages')));
  });

  test(
    'ProductSearchController cubre page1, busqueda profunda y loadMore',
    () async {
      final products = List<ProductModel>.generate(56, (index) {
        final number = index + 1;
        return ProductModel(
          id: 'p-$number',
          nombre: 'Producto compra $number',
          codigo: 'COMP-$number',
          categoria: number.isEven ? 'Insumos' : 'Repuestos',
          precio: 10,
          costo: 5,
        );
      });
      final controller = ProductSearchController(dio: _fakeDio(products));
      addTearDown(controller.dispose);

      await controller.loadInitial();
      expect(controller.snapshot.items.length, 50);
      expect(controller.snapshot.hasMore, isTrue);
      expect(
        controller.snapshot.items.any((p) => p.nombre == 'Producto compra 55'),
        isFalse,
      );

      controller.setQuery('Producto compra 55', immediate: true);
      await _waitForIdle(controller);
      expect(controller.snapshot.items.single.nombre, 'Producto compra 55');

      controller.setQuery('', immediate: true);
      await _waitForIdle(controller);
      await controller.loadMore();
      expect(
        controller.snapshot.items.any((p) => p.nombre == 'Producto compra 55'),
        isTrue,
      );
    },
  );

  test(
    'ProductSearchController no duplica ids al cargar mas compras',
    () async {
      final base = List<ProductModel>.generate(56, (index) {
        final number = index + 1;
        return ProductModel(
          id: 'p-$number',
          nombre: 'Compra dedupe $number',
          codigo: 'DED-$number',
          precio: 10,
          costo: 5,
        );
      });
      final controller = ProductSearchController(
        dio: _fakeDio([...base.take(50), base.first, ...base.skip(50)]),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.loadMore();

      final ids = controller.snapshot.items
          .map((product) => product.id)
          .toList();
      expect(ids.length, ids.toSet().length);
      expect(ids.length, 56);
    },
  );
}

Dio _fakeDio(List<ProductModel> products) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path != ApiRoutes.catalogProducts) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
            ),
          );
          return;
        }
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: _page(products, options.queryParameters),
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, dynamic> _page(
  List<ProductModel> products,
  Map<String, dynamic> query,
) {
  final search = '${query['search'] ?? ''}'.trim().toLowerCase();
  final category = '${query['category'] ?? ''}'.trim();
  final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
  final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
  final filtered = products.where((product) {
    if (category.isNotEmpty && product.categoriaLabel != category) return false;
    if (search.isEmpty) return true;
    return product.nombre.toLowerCase().contains(search) ||
        (product.codigo ?? '').toLowerCase().contains(search) ||
        product.categoriaLabel.toLowerCase().contains(search);
  }).toList();
  final start = (page - 1) * limit;
  final end = (start + limit).clamp(0, filtered.length);
  final items = start >= filtered.length
      ? const <ProductModel>[]
      : filtered.sublist(start, end);
  return {
    'items': items.map((product) => product.toJson()).toList(),
    'page': page,
    'limit': limit,
    'total': filtered.length,
    'hasMore': end < filtered.length,
    'nextPage': end < filtered.length ? page + 1 : null,
  };
}

Future<void> _waitForIdle(ProductSearchController controller) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final state = controller.snapshot;
    if (!state.isInitialLoading && !state.isRefreshing) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('El controlador no quedo idle');
}
