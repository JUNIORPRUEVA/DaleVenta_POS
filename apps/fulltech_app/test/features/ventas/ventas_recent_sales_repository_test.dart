import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';

void main() {
  late List<RequestOptions> captured;

  setUp(() {
    captured = <RequestOptions>[];
  });

  VentasRepository buildRepository(ResponseBody Function(RequestOptions) h) {
    return VentasRepository(
      Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          captured.add(options);
          return h(options);
        }),
      SyncQueueService(OfflineStore.instance),
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

  Map<String, dynamic> saleRow({String id = 'sale-1'}) {
    return {
      'id': id,
      'userId': 'user-1',
      'totalSold': 100,
      'totalCost': 50,
      'totalProfit': 50,
      'commissionAmount': 0,
      'paymentMethod': 'cash',
      'paymentCashAmount': 100,
      'paymentTransferAmount': 0,
      'creditAmount': 0,
      'creditPaidAmount': 0,
      'creditBalance': 0,
      'creditStatus': 'none',
      'isDeleted': false,
      'items': <dynamic>[],
    };
  }

  test('listSales envía limit cuando se provee y no cuando no', () async {
    final repository = buildRepository(
      (options) => jsonResponse([saleRow()]),
    );

    final withLimit = await repository.listSales(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 20),
      limit: 20,
    );
    expect(captured.last.queryParameters['limit'], 20);
    expect(withLimit, hasLength(1));

    await repository.listSales(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 20),
    );
    expect(captured.last.queryParameters.containsKey('limit'), isFalse);
  });

  test('listInvoices envía limit cuando se provee', () async {
    final repository = buildRepository(
      (options) => jsonResponse([saleRow()]),
    );

    await repository.listInvoices(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 20),
      includeDeleted: true,
      limit: 20,
    );

    expect(captured.last.path, '/sales/invoices');
    expect(captured.last.queryParameters['limit'], 20);
    expect(captured.last.queryParameters['includeDeleted'], 'true');
  });

  test('timeout en listSales termina en error (nunca cuelga)', () async {
    final repository = buildRepository(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );

    await expectLater(
      repository.listSales(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 20),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('respuesta que no es lista no cuelga y devuelve vacío', () async {
    final repository = buildRepository(
      (options) => jsonResponse({'message': 'ok', 'items': [saleRow()]}),
    );

    final rows = await repository.listSales(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 20),
    );

    // La respuesta es un Map (no List): se trata como vacía sin colgarse.
    expect(rows, isEmpty);
  });

  test('mapeo tolerante: una venta con campos null no rompe la lista', () async {
    final repository = buildRepository(
      (options) => jsonResponse([
        {
          'id': 'sale-null',
          'userId': null,
          'totalSold': null,
          'items': null,
        },
      ]),
    );

    final rows = await repository.listSales(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 20),
    );

    expect(rows, hasLength(1));
    expect(rows.single.id, 'sale-null');
    expect(rows.single.totalSold, 0);
  });
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
