import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_sync_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh cache avoids GET /products', () async {
    final storage = _FakeTokenStorage('company-fresh');
    final dio = _fakeDio((_) async {
      fail('fresh cache should avoid the network');
    });
    final repository = CatalogRepository(
      dio,
      storage,
      null,
      _defaultFreshness,
      _MemoryJsonCache(),
    );
    await repository.saveProductsSnapshot([_product('fresh')]);

    final products = await repository.fetchProducts();

    expect(products.single.id, 'fresh');
  });

  test('stale cache refreshes in background', () async {
    var calls = 0;
    final storage = _FakeTokenStorage('company-stale');
    final dio = _fakeDio((_) async {
      calls++;
      return _jsonResponse([_productJson('remote')]);
    });
    final repository = CatalogRepository(
      dio,
      storage,
      null,
      Duration.zero,
      _MemoryJsonCache(),
    );
    await repository.saveProductsSnapshot([_product('stale')]);

    final products = await repository.fetchProducts(silent: true);

    expect(calls, 1);
    expect(products.single.id, 'remote');
  });

  test('concurrent refreshes use one GET /products', () async {
    final gate = Completer<ResponseBody>();
    var calls = 0;
    final storage = _FakeTokenStorage('company-single-flight');
    final dio = _fakeDio((_) {
      calls++;
      return gate.future;
    });
    final repository = CatalogRepository(
      dio,
      storage,
      null,
      _defaultFreshness,
      _MemoryJsonCache(),
    );

    final first = repository.fetchProducts(forceRefresh: true);
    final second = repository.fetchProducts(forceRefresh: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);

    gate.complete(_jsonResponse([_productJson('remote')]));
    final results = await Future.wait([first, second]);

    expect(results[0].single.id, 'remote');
    expect(results[1].single.id, 'remote');
  });

  test('network failure preserves the offline snapshot', () async {
    final storage = _FakeTokenStorage('company-offline');
    final dio = _fakeDio((options) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    });
    final repository = CatalogRepository(
      dio,
      storage,
      null,
      _defaultFreshness,
      _MemoryJsonCache(),
    );
    await repository.saveProductsSnapshot([_product('offline')]);

    final products = await repository.fetchProducts(forceRefresh: true);

    expect(products.single.id, 'offline');
  });

  test('company namespaces never reuse another company cache', () async {
    final companyA = _FakeTokenStorage('company-a');
    final companyB = _FakeTokenStorage('company-b');
    final repositoryA = CatalogRepository(_fakeDio((_) async {
      fail('company A should use its own cache');
    }), companyA, null, _defaultFreshness, _MemoryJsonCache());
    final repositoryB = CatalogRepository(_fakeDio((_) async {
      fail('company B should use its own cache');
    }), companyB, null, _defaultFreshness, _MemoryJsonCache());
    await repositoryA.saveProductsSnapshot([_product('a')]);
    await repositoryB.saveProductsSnapshot([_product('b')]);

    expect((await repositoryA.fetchProducts()).single.id, 'a');
    expect((await repositoryB.fetchProducts()).single.id, 'b');
  });

  test('force refresh bypasses fresh cache for real invalidation', () async {
    var calls = 0;
    final storage = _FakeTokenStorage('company-invalidation');
    final dio = _fakeDio((_) async {
      calls++;
      return _jsonResponse([_productJson('updated')]);
    });
    final repository = CatalogRepository(
      dio,
      storage,
      null,
      _defaultFreshness,
      _MemoryJsonCache(),
    );
    await repository.saveProductsSnapshot([_product('cached')]);

    final products = await repository.fetchProducts(forceRefresh: true);

    expect(calls, 1);
    expect(products.single.id, 'updated');
  });

  test('equivalent product responses do not require a visual update', () {
    final previous = [_product('same')];
    final next = [_product('same')];
    final changed = [_product('changed')];

    expect(areCatalogProductsEquivalent(previous, next), isTrue);
    expect(areCatalogProductsEquivalent(previous, changed), isFalse);
  });

  test('missing companyId never falls back to an unscoped cache', () async {
    var calls = 0;
    final dio = _fakeDio((_) async {
      calls++;
      return _jsonResponse([_productJson('unexpected')]);
    });
    final repository = CatalogRepository(
      dio,
      _FakeTokenStorage(null),
      null,
      _defaultFreshness,
      _MemoryJsonCache(),
    );

    expect(await repository.fetchProducts(), isEmpty);
    expect(calls, 0);
  });
}

ProductModel _product(String id) {
  return ProductModel(
    id: id,
    nombre: id,
    precio: 10,
    costo: 5,
    stock: 3,
  );
}

Map<String, dynamic> _productJson(String id) => _product(id).toJson();

ResponseBody _jsonResponse(Object data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage(this._companyId);

  final String? _companyId;

  @override
  Future<UserModel?> getUserSnapshot() async {
    if (_companyId == null) return null;
    return UserModel(
      id: 'user-$_companyId',
      email: 'test@example.com',
      nombreCompleto: 'Test',
      telefono: '',
      companyId: _companyId,
    );
  }
}

Dio _fakeDio(Future<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://products.test'));
  dio.httpClientAdapter = _FakeHttpClientAdapter(handler);
  return dio;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

const _defaultFreshness = Duration(minutes: 2);

class _MemoryJsonCache extends LocalJsonCache {
  final Map<String, Map<String, dynamic>> _values = {};
  final Map<String, DateTime> _writtenAt = {};

  @override
  Future<Map<String, dynamic>?> readMap(String key, {Duration? maxAge}) async {
    final value = _values[key];
    if (value == null) return null;
    final age = DateTime.now().difference(_writtenAt[key]!);
    if (maxAge != null && (maxAge <= Duration.zero || age > maxAge)) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = Map<String, dynamic>.from(value);
    _writtenAt[key] = DateTime.now();
  }
}
