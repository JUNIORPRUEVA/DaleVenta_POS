import 'dart:io';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/application/product_search_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Inventario usa ProductSearchController sin carga completa interactiva',
    () {
      final source = File(
        'lib/features/products/ui/inventory_module_pages.dart',
      ).readAsStringSync();
      final kardexSource = File(
        'lib/features/warehouses/ui/inventory_kardex_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('late final ProductSearchController _productSearch'),
      );
      expect(source, contains('_productSearch.loadInitial()'));
      expect(source, contains('_productSearch.loadMore()'));
      expect(source, contains('_productSearch.setQuery(value)'));
      expect(
        source,
        isNot(contains('catalogControllerProvider.notifier).load')),
      );
      expect(source, isNot(contains('loadAllProductPages')));

      expect(kardexSource, contains('ProductSearchController'));
      expect(kardexSource, contains('_productSearch.loadMore()'));
      expect(
        kardexSource,
        isNot(contains('catalogControllerProvider.notifier).load')),
      );
    },
  );

  test(
    'ProductSearchController cubre page1, busqueda profunda, loadMore y stock decimal',
    () async {
      final products = List<ProductModel>.generate(56, (index) {
        final number = index + 1;
        return ProductModel(
          id: 'inv-$number',
          nombre: 'Producto inventario $number',
          codigo: 'INV-$number',
          categoria: number.isEven ? 'Ferreteria' : 'Servicios',
          precio: 100,
          costo: 40,
          stock: number == 55 ? 12.375 : number.toDouble(),
          stockDecimal: number == 55 ? '12.375' : '$number',
        );
      });
      final controller = ProductSearchController(dio: _fakeDio(products));
      addTearDown(controller.dispose);

      await controller.loadInitial();
      expect(controller.snapshot.items.length, 50);
      expect(controller.snapshot.hasMore, isTrue);
      expect(
        controller.snapshot.items.any((p) => p.codigo == 'INV-55'),
        isFalse,
      );

      controller.setQuery('INV-55', immediate: true);
      await _waitForIdle(controller);
      expect(controller.snapshot.items.single.codigo, 'INV-55');
      expect(controller.snapshot.items.single.stock, 12.375);
      expect(controller.snapshot.items.single.stockDecimal, '12.375');

      controller.setQuery('', immediate: true);
      await _waitForIdle(controller);
      await controller.loadMore();
      expect(
        controller.snapshot.items.any((p) => p.codigo == 'INV-55'),
        isTrue,
      );
    },
  );

  test(
    'ProductSearchController no duplica ids en inventario al cargar mas',
    () async {
      final base = List<ProductModel>.generate(56, (index) {
        final number = index + 1;
        return ProductModel(
          id: 'inv-dedupe-$number',
          nombre: 'Inventario dedupe $number',
          codigo: 'IDP-$number',
          precio: 100,
          costo: 40,
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
  final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
  final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
  final filtered = products.where((product) {
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
