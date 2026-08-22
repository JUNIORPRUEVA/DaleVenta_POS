import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keyA = 'taxes_cache_v1:company:company-a';

  test('fresh cache is returned immediately (cache-first) without blocking on network',
      () async {
    final gate = Completer<ResponseBody>();
    final cache = _MemoryJsonCache();
    await cache.writeMap(keyA, {
      'taxes': [
        {'id': 'tA', 'name': 'ITBIS A', 'rate': 0.18, 'isDefault': true},
      ],
    });
    final dio = _fakeDio((_) => gate.future);

    final taxes = await loadActiveTaxes(dio, 'company-a', cache: cache);

    // Devolvió la caché (18%) sin esperar a que la red terminara.
    expect(taxes.single.rate, 0.18);
    expect(taxes.single.id, 'tA');
    // El refresh en background queda pendiente en la compuerta: si la carga
    // hubiera esperado a la red, este test se colgaría.
    gate.complete(
      _jsonResponse([
        {'id': 'tA', 'name': 'ITBIS A', 'rate': 0.18, 'isDefault': true},
      ]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('no cache: GET /taxes una vez y guarda; segunda llamada usa caché', () async {
    var calls = 0;
    final cache = _MemoryJsonCache();
    final dio = _fakeDio((_) async {
      calls++;
      return _jsonResponse([
        {'id': 'tA', 'name': 'ITBIS', 'rate': 0.18, 'isDefault': true},
      ]);
    });

    final first = await loadActiveTaxes(dio, 'company-a', cache: cache);
    expect(first.single.rate, 0.18);
    final callsAfterFirst = calls;
    expect(callsAfterFirst, 1);

    final second = await loadActiveTaxes(dio, 'company-a', cache: cache);
    expect(second.single.rate, 0.18);
    // La segunda carga vino de caché; a lo sumo hay un refresh en background.
    expect(calls - callsAfterFirst, lessThanOrEqualTo(1));
  });

  test('MULTIEMPRESA: la caché de taxes de la empresa A NUNCA contamina a la B',
      () async {
    final cache = _MemoryJsonCache();
    final networkFor = <String>[];
    final dio = _fakeDio((options) async {
      final company = (options.extra['companyKey'] ?? '').toString();
      networkFor.add(company);
      if (company == 'company-b') {
        return _jsonResponse([
          {'id': 'tB', 'name': 'ITBIS B', 'rate': 0.16, 'isDefault': true},
        ]);
      }
      return _jsonResponse([
        {'id': 'tA', 'name': 'ITBIS A', 'rate': 0.18, 'isDefault': true},
      ]);
    });

    // Se precarga SOLO la caché de A con su configuración (18%).
    await cache.writeMap(keyA, {
      'taxes': [
        {'id': 'tA', 'name': 'ITBIS A', 'rate': 0.18, 'isDefault': true},
      ],
    });

    final taxesA = await loadActiveTaxes(dio, 'company-a', cache: cache);
    expect(taxesA.single.id, 'tA');
    expect(taxesA.single.rate, 0.18);

    // B no debe leer la caché de A: consulta red y obtiene SU configuración.
    final taxesB = await loadActiveTaxes(dio, 'company-b', cache: cache);
    expect(taxesB.single.id, 'tB');
    expect(taxesB.single.rate, 0.16);
    expect(networkFor, contains('company-b'));

    // A sigue con su caché aislada, sin contaminación de B.
    final taxesA2 = await loadActiveTaxes(dio, 'company-a', cache: cache);
    expect(taxesA2.single.id, 'tA');
    expect(taxesA2.single.rate, 0.18);
  });

  test('respuesta no-lista devuelve lista vacía (sin romper)', () async {
    final cache = _MemoryJsonCache();
    final dio = _fakeDio((_) async => _jsonResponse({'not': 'a list'}));
    final taxes = await loadActiveTaxes(dio, 'company-a', cache: cache);
    expect(taxes, isEmpty);
  });
}

ResponseBody _jsonResponse(Object data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Dio _fakeDio(Future<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://taxes.test'));
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
