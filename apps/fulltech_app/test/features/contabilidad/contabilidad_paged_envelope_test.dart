import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/contabilidad/data/contabilidad_repository.dart';

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
