import 'dart:convert';

import 'package:daleventa_pos/features/catalogo/data/product_pages_loader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loadAllProductPages', () {
    for (final total in const [50, 100, 400, 1000]) {
      test('loads all $total products through real pagination', () async {
        final adapter = _PagedProductsAdapter(total: total);
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = adapter;

        final products = await loadAllProductPages(dio);

        expect(products, hasLength(total));
        expect(products.first.id, 'product-1');
        expect(products.last.id, 'product-$total');
        expect(adapter.requests, (total / kProductPagesPageSize).ceil());
      });
    }

    test('deduplicates products by id across pages', () async {
      final adapter = _PagedProductsAdapter(
        total: 205,
        duplicateFirstOnPage2: true,
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;

      final products = await loadAllProductPages(dio);

      expect(products, hasLength(205));
      expect(products.map((product) => product.id).toSet(), hasLength(205));
      expect(adapter.requests, 2);
    });
  });
}

class _PagedProductsAdapter implements HttpClientAdapter {
  _PagedProductsAdapter({
    required this.total,
    this.duplicateFirstOnPage2 = false,
  });

  final int total;
  final bool duplicateFirstOnPage2;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests += 1;
    final page = _asInt(options.queryParameters['page']) ?? 1;
    final limit = _asInt(options.queryParameters['limit']) ?? 200;
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    final items = <Map<String, dynamic>>[];

    for (var index = start; index < end; index += 1) {
      items.add(_product(index + 1));
    }

    if (duplicateFirstOnPage2 && page == 2 && items.isNotEmpty) {
      items.insert(0, _product(1));
    }

    final hasMore = end < total;
    final body = jsonEncode({
      'items': items,
      'page': page,
      'limit': limit,
      'total': total,
      'hasMore': hasMore,
      'nextPage': hasMore ? page + 1 : null,
    });

    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _product(int index) {
    return {
      'id': 'product-$index',
      'nombre': 'Product $index',
      'codigo': 'P-$index',
      'precio': index.toDouble(),
      'costo': 1,
      'stock': 10,
      'categoria': 'General',
      'activo': true,
      'productSource': 'LOCAL',
    };
  }
}
