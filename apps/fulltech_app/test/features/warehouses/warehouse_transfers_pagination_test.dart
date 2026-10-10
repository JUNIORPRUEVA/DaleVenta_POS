import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';

void main() {
  WarehouseRepository buildRepository(
    ResponseBody Function(RequestOptions options) handler,
  ) {
    return WarehouseRepository(
      Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (options) async => handler(options),
        ),
    );
  }

  ResponseBody jsonResponse(dynamic body, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> transferRow({String id = 'transfer-1'}) {
    return {
      'id': id,
      'status': 'COMPLETED',
      'sourceWarehouse': {'name': 'Principal', 'code': 'MAIN'},
      'destinationWarehouse': {'name': 'Bavaro', 'code': 'BAV'},
      'itemCount': 1,
      'items': const [],
      'createdAt': '2026-10-10T00:00:00.000Z',
    };
  }

  test('fetchTransfersPage envia page/limit y conserva metadatos', () async {
    RequestOptions? request;
    final repository = buildRepository((options) {
      request = options;
      return jsonResponse({
        'items': [transferRow()],
        'page': 2,
        'limit': 50,
        'hasMore': true,
        'nextPage': 3,
      });
    });

    final page = await repository.fetchTransfersPage(page: 2, limit: 50);

    expect(request!.queryParameters['page'], 2);
    expect(request!.queryParameters['limit'], 50);
    expect(page.items.single.id, 'transfer-1');
    expect(page.hasMore, isTrue);
    expect(page.nextPage, 3);
  });

  test(
    'fetchTransfers mantiene compatibilidad con lista plana legacy',
    () async {
      final repository = buildRepository((_) => jsonResponse([transferRow()]));

      final transfers = await repository.fetchTransfers();

      expect(transfers, hasLength(1));
      expect(transfers.single.id, 'transfer-1');
    },
  );
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
