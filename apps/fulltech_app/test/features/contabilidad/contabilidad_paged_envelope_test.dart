import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/contabilidad/data/contabilidad_repository.dart';
import 'package:daleventa_pos/features/contabilidad/models/deposit_order_model.dart';

/// Contrato de listados de contabilidad: el backend devuelve un sobre paginado
/// `{ items: [...], page, limit, hasMore, nextPage }`. El repositorio debe
/// desenvolverlo y seguir aceptando la lista plana antigua.
void main() {
  ContabilidadRepository buildRepository(
    ResponseBody Function(RequestOptions) handler,
  ) {
    return ContabilidadRepository(
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

  Map<String, dynamic> closeRow({String id = 'close-1'}) {
    return {
      'id': id,
      'type': 'pos',
      'date': '2026-10-01',
      'status': 'closed',
      'cash': 100,
      'transfer': 0,
      'card': 0,
      'totalIncome': 100,
      'netTotal': 100,
      'difference': 0,
    };
  }

  Map<String, dynamic> paymentRow({String id = 'pay-1'}) {
    return {
      'id': id,
      'serviceId': 'svc-1',
      'amount': 25,
      'paidAt': '2026-10-01T10:00:00.000Z',
      'createdAt': '2026-10-01T10:00:00.000Z',
    };
  }

  Map<String, dynamic> depositRow({String id = 'dep-1'}) {
    return {
      'id': id,
      'windowFrom': '2026-10-01T00:00:00.000Z',
      'windowTo': '2026-10-01T23:59:59.999Z',
      'bankName': 'Banco Popular',
      'reserveAmount': 0,
      'totalAvailableCash': 100,
      'depositTotal': 100,
      'closesCountByType': {'pos': 1},
      'depositByType': {'pos': 100},
      'accountByType': {'pos': '001'},
      'status': 'PENDING',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'updatedAt': '2026-10-01T10:00:00.000Z',
    };
  }

  Map<String, dynamic> invoiceRow({String id = 'invoice-1'}) {
    return {
      'id': id,
      'kind': 'SALE',
      'invoiceDate': '2026-10-01T00:00:00.000Z',
      'imageUrl': '/uploads/invoice.jpg',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'updatedAt': '2026-10-01T10:00:00.000Z',
    };
  }

  Map<String, dynamic> serviceRow({String id = 'svc-1'}) {
    return {
      'id': id,
      'title': 'Renta',
      'providerKind': 'COMPANY',
      'providerName': 'Proveedor',
      'frequency': 'MONTHLY',
      'defaultAmount': 100,
      'nextDueDate': '2026-10-15T00:00:00.000Z',
      'active': true,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'updatedAt': '2026-10-01T10:00:00.000Z',
      'payments': [],
    };
  }

  group('listCloses', () {
    test('desenvuelve el sobre paginado { items: [...] }', () async {
      final repository = buildRepository(
        (_) => jsonResponse({
          'items': [closeRow()],
          'page': 1,
          'limit': 50,
          'hasMore': false,
          'nextPage': null,
        }),
      );

      final closes = await repository.listCloses(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );

      expect(
        closes,
        hasLength(1),
        reason:
            'un sobre paginado debe aportar sus items; devolver una lista '
            'vacía dejaría la pantalla de cierres en blanco',
      );
      expect(closes.single.id, 'close-1');
      expect(closes.single.cash, 100);
    });

    test('sigue aceptando la lista plana (compatibilidad)', () async {
      final repository = buildRepository((_) => jsonResponse([closeRow()]));

      final closes = await repository.listCloses(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );

      expect(closes, hasLength(1));
      expect(closes.single.id, 'close-1');
    });

    test('conserva metadatos y envia page/limit cuando se pide pagina', () async {
      RequestOptions? request;
      final repository = buildRepository((options) {
        request = options;
        return jsonResponse({
          'items': [closeRow()],
          'page': 2,
          'limit': 50,
          'hasMore': true,
          'nextPage': 3,
        });
      });

      final page = await repository.listClosesPage(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        page: 2,
        limit: 50,
      );

      expect(request!.queryParameters['page'], 2);
      expect(request!.queryParameters['limit'], 50);
      expect(page.items.single.id, 'close-1');
      expect(page.page, 2);
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 3);
    });
  });

  group('listPayablePayments', () {
    test('desenvuelve el sobre paginado { items: [...] }', () async {
      final repository = buildRepository(
        (_) => jsonResponse({
          'items': [paymentRow()],
          'page': 1,
          'limit': 50,
          'hasMore': true,
          'nextPage': 2,
        }),
      );

      final payments = await repository.listPayablePayments();

      expect(
        payments,
        hasLength(1),
        reason: 'el historial de pagos por pagar usa el mismo sobre paginado',
      );
      expect(payments.single.id, 'pay-1');
      expect(payments.single.amount, 25);
    });

    test('sigue aceptando la lista plana (compatibilidad)', () async {
      final repository = buildRepository((_) => jsonResponse([paymentRow()]));

      final payments = await repository.listPayablePayments();

      expect(payments, hasLength(1));
      expect(payments.single.id, 'pay-1');
    });
  });

  group('listDepositOrders', () {
    test('desenvuelve pagina y envia filtros remotos', () async {
      RequestOptions? request;
      final repository = buildRepository((options) {
        request = options;
        return jsonResponse({
          'items': [depositRow()],
          'page': 2,
          'limit': 50,
          'hasMore': false,
          'nextPage': null,
        });
      });

      final page = await repository.listDepositOrdersPage(
        status: DepositOrderStatus.pending,
        page: 2,
        limit: 50,
      );

      expect(request!.queryParameters['status'], 'PENDING');
      expect(request!.queryParameters['page'], 2);
      expect(request!.queryParameters['limit'], 50);
      expect(page.items.single.id, 'dep-1');
      expect(page.hasMore, isFalse);
    });
  });

  group('listFiscalInvoices', () {
    test('desenvuelve pagina y conserva metadatos', () async {
      final repository = buildRepository(
        (_) => jsonResponse({
          'items': [invoiceRow()],
          'page': 1,
          'limit': 50,
          'hasMore': true,
          'nextPage': 2,
        }),
      );

      final page = await repository.listFiscalInvoicesPage(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        page: 1,
        limit: 50,
      );

      expect(page.items.single.id, 'invoice-1');
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 2);
    });
  });

  group('listPayableServices', () {
    test('desenvuelve pagina de servicios activos', () async {
      RequestOptions? request;
      final repository = buildRepository((options) {
        request = options;
        return jsonResponse({
          'items': [serviceRow()],
          'page': 1,
          'limit': 50,
          'hasMore': false,
          'nextPage': null,
        });
      });

      final page = await repository.listPayableServicesPage(
        active: true,
        page: 1,
        limit: 50,
      );

      expect(request!.queryParameters['active'], isTrue);
      expect(request!.queryParameters['page'], 1);
      expect(page.items.single.id, 'svc-1');
    });
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
