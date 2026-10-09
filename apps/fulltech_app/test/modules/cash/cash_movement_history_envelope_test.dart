import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';

/// `GET /cash/movements/history` responde con un sobre paginado
/// `{ items: [...], page, limit, hasMore, nextPage }`. El historial de caja
/// debe desenvolverlo; antes devolvía una lista vacía.
void main() {
  late List<RequestOptions> captured;

  setUp(() {
    captured = <RequestOptions>[];
  });

  CashRepository buildRepository(
    ResponseBody Function(RequestOptions) handler,
  ) {
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        captured.add(options);
        return handler(options);
      });
    return CashRepository(dio, SyncQueueService(OfflineStore.instance));
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

  Map<String, dynamic> movementRow({String id = 'mv-1'}) {
    return {
      'id': id,
      'sessionId': 'session-1',
      'type': 'expense',
      'amount': 50,
      'reason': 'Compra de hielo',
      'movementType': 'expense',
      'affectsProfit': false,
      'createdAt': '2026-10-01T10:00:00.000Z',
    };
  }

  test('movementHistory desenvuelve el sobre paginado { items: [...] }', () async {
    final repository = buildRepository(
      (_) => jsonResponse({
        'items': [movementRow()],
        'page': 1,
        'limit': 50,
        'hasMore': false,
        'nextPage': null,
      }),
    );

    final rows = await repository.movementHistory();

    expect(captured.single.method, 'GET');
    expect(
      captured.single.queryParameters.containsKey('take'),
      isTrue,
      reason: 'el historial se pide acotado, no completo',
    );
    expect(
      rows,
      hasLength(1),
      reason:
          'un sobre paginado debe aportar sus items; devolver una lista vacía '
          'dejaría el historial de caja en blanco',
    );
    expect(rows.single.id, 'mv-1');
    expect(rows.single.amount, 50);
  });

  test('movementHistory sigue aceptando la lista plana (compatibilidad)', () async {
    final repository = buildRepository((_) => jsonResponse([movementRow()]));

    final rows = await repository.movementHistory();

    expect(rows, hasLength(1));
    expect(rows.single.id, 'mv-1');
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
