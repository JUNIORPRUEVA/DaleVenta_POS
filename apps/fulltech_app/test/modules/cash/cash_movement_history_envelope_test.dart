import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  test(
    'movementHistory desenvuelve el sobre paginado { items: [...] }',
    () async {
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
        isFalse,
        reason: 'el cliente moderno no usa take legacy en históricos paginados',
      );
      expect(
        captured.single.queryParameters['page'],
        1,
        reason: 'el historial se pide con paginación explícita',
      );
      expect(
        captured.single.queryParameters['limit'],
        160,
        reason: 'movementHistory conserva su límite legacy vía limit explícito',
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
    },
  );

  test('movementHistoryPage expone metadata y filtros remotos', () async {
    final repository = buildRepository(
      (_) => jsonResponse({
        'items': [movementRow(id: 'mv-2')],
        'page': 2,
        'limit': 50,
        'total': 101,
        'hasMore': true,
        'nextPage': 3,
      }),
    );

    final page = await repository.movementHistoryPage(
      type: 'OUT',
      movementType: 'expense',
      search: 'hielo',
      page: 2,
      limit: 50,
    );

    expect(captured.single.queryParameters, {
      'type': 'OUT',
      'movementType': 'expense',
      'search': 'hielo',
      'page': 2,
      'limit': 50,
    });
    expect(page.items.single.id, 'mv-2');
    expect(page.page, 2);
    expect(page.total, 101);
    expect(page.hasMore, isTrue);
    expect(page.nextPage, 3);
  });

  test('closedSessionsPage usa contrato paginado explícito', () async {
    final repository = buildRepository(
      (_) => jsonResponse({
        'items': [
          {
            'id': 'session-1',
            'userName': 'Caja',
            'businessDate': '2026-10-01',
            'openedAt': '2026-10-01T10:00:00.000Z',
            'closedAt': '2026-10-01T18:00:00.000Z',
            'initialAmount': 100,
            'closingAmount': 150,
            'expectedAmount': 150,
            'difference': 0,
            'status': 'CLOSED',
          },
        ],
        'page': 1,
        'limit': 50,
        'total': 501,
        'hasMore': true,
        'nextPage': 2,
      }),
    );

    final page = await repository.closedSessionsPage(search: 'caja');

    expect(captured.single.queryParameters['search'], 'caja');
    expect(captured.single.queryParameters['page'], 1);
    expect(captured.single.queryParameters['limit'], 50);
    expect(page.items.single.id, 'session-1');
    expect(page.total, 501);
    expect(page.hasMore, isTrue);
  });

  test('pantallas historicas conservan page1 si page2 falla', () async {
    final source = await File(
      'lib/modules/cash/cash_management_screens.dart',
    ).readAsString();

    expect(source, contains('Future<void> _loadMoreMovements() async'));
    expect(source, contains('Future<void> _loadMoreExpenses() async'));
    expect(source, contains('Future<void> _loadMoreTurns() async'));
    expect(source, contains('_error = error;'));
    expect(source, contains('_loadingMore = false;'));
    expect(source, contains('_rows = byId.values.toList(growable: false);'));
  });

  test('historiales de caja no usan limites hardcoded de 220/260', () async {
    final source = await File(
      'lib/modules/cash/cash_management_screens.dart',
    ).readAsString();

    expect(source, isNot(contains('take: 220')));
    expect(source, isNot(contains('take: 260')));
    expect(source, contains('movementHistoryPage('));
    expect(source, contains('closedSessionsPage('));
    expect(source, contains('_cashHistoryPageSize = 50'));
  });

  test('backend conserva orden deterministico y filtros remotos', () async {
    final source = await File('../api/src/cash/cash.service.ts').readAsString();

    expect(
      source,
      contains('orderBy: [{ createdAt: "desc" }, { id: "desc" }]'),
    );
    expect(source, contains('orderBy: [{ closedAt: "desc" }, { id: "desc" }]'));
    expect(source, contains('query.search ?? query.q'));
    expect(source, contains('movementDateRange(query.from, query.to)'));
    expect(source, contains('sessionBusinessDateRange(query.from, query.to)'));
  });

  test(
    'movementHistory sigue aceptando la lista plana (compatibilidad)',
    () async {
      final repository = buildRepository((_) => jsonResponse([movementRow()]));

      final rows = await repository.movementHistory();

      expect(rows, hasLength(1));
      expect(rows.single.id, 'mv-1');
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
