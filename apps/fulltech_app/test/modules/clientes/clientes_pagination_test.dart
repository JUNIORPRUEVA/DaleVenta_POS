import 'dart:convert';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/clientes/data/clientes_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regresión del límite de 100 clientes: la lista se quedaba con la primera
/// página y los registros siguientes eran inalcanzables. Ahora el repositorio
/// envía los filtros al servidor y conserva el envelope (`total`/`hasMore`).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('la página expone total/hasMore/nextPage del servidor', () async {
    final server = _ClientsServer(totalClients: 1000, pageSize: 50);
    final repo = _repository(server);

    final page = await repo.listClientsPage(
      ownerId: 'owner-1',
      page: 1,
      pageSize: 50,
    );

    expect(page.items, hasLength(50));
    expect(page.total, 1000);
    expect(page.hasMore, isTrue);
    expect(page.nextPage, 2);
    expect(page.limit, 50);
  });

  test('el cliente #900 es alcanzable cargando páginas siguientes', () async {
    final server = _ClientsServer(totalClients: 1000, pageSize: 50);
    final repo = _repository(server);

    final first = await repo.listClientsPage(ownerId: 'o', page: 1, pageSize: 50);
    final deep = await repo.listClientsPage(ownerId: 'o', page: 18, pageSize: 50);

    expect(first.items.first.nombre, 'Cliente 001');
    expect(
      deep.items.any((cliente) => cliente.nombre == 'Cliente 851'),
      isTrue,
      reason: 'la página 18 debe contener registros fuera de las primeras 100',
    );
  });

  test('los filtros de UI viajan al servidor (correo, propietario, orden)', () async {
    final server = _ClientsServer(totalClients: 200, pageSize: 50);
    final repo = _repository(server);

    await repo.listClientsPage(
      ownerId: 'o',
      page: 2,
      pageSize: 50,
      correoFilter: CorreoFilter.sinCorreo,
      ownerFilter: OwnerFilter.mine,
      order: ClientesOrder.za,
    );

    final query = server.requests.last.queryParameters;
    expect(query['correoFilter'], 'sinCorreo');
    expect(query['ownerFilter'], 'mine');
    expect(query['order'], 'za');
    expect(query['page'], 2);
    expect(query['pageSize'], 50);
  });

  test('sin filtros no se envían parámetros que el servidor no espera', () async {
    final server = _ClientsServer(totalClients: 10, pageSize: 50);
    final repo = _repository(server);

    await repo.listClientsPage(ownerId: 'o');

    final query = server.requests.last.queryParameters;
    expect(query.containsKey('correoFilter'), isFalse);
    expect(query.containsKey('ownerFilter'), isFalse);
    expect(query['order'], 'az');
  });

  test('la última página no ofrece más y devuelve el total real', () async {
    final server = _ClientsServer(totalClients: 120, pageSize: 50);
    final repo = _repository(server);

    final last = await repo.listClientsPage(ownerId: 'o', page: 3, pageSize: 50);

    expect(last.items, hasLength(20));
    expect(last.total, 120);
    expect(last.hasMore, isFalse);
  });
}

ClientesRepository _repository(_ClientsServer server) {
  return ClientesRepository(
    Dio()..httpClientAdapter = _FakeHttpClientAdapter(server.handle),
    SyncQueueService(OfflineStore.instance),
  );
}

class _ClientsServer {
  _ClientsServer({required this.totalClients, required this.pageSize});

  final int totalClients;
  final int pageSize;
  final List<RequestOptions> requests = <RequestOptions>[];

  Future<ResponseBody> handle(RequestOptions options) async {
    if (!options.path.endsWith(ApiRoutes.clients)) {
      return ResponseBody.fromString('{}', 404, headers: _jsonHeaders);
    }
    requests.add(options);
    final page =
        int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    final limit =
        int.tryParse('${options.queryParameters['pageSize'] ?? pageSize}') ??
        pageSize;
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, totalClients);
    final rows = <Map<String, dynamic>>[
      for (var index = start; index < end; index += 1)
        {
          'id': 'client-$index',
          'nombre': 'Cliente ${(index + 1).toString().padLeft(3, '0')}',
          'telefono': '809000${index.toString().padLeft(4, '0')}',
          'ownerId': 'o',
        },
    ];
    final hasMore = end < totalClients;
    return ResponseBody.fromString(
      jsonEncode({
        'items': rows,
        'page': page,
        'limit': limit,
        'total': totalClients,
        'hasMore': hasMore,
        'nextPage': hasMore ? page + 1 : null,
      }),
      200,
      headers: _jsonHeaders,
    );
  }
}

const Map<String, List<String>> _jsonHeaders = {
  Headers.contentTypeHeader: [Headers.jsonContentType],
};

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
