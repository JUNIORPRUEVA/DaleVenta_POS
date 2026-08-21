import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/features/contabilidad/data/contabilidad_repository.dart';

void main() {
  late List<RequestOptions> captured;

  setUp(() {
    captured = <RequestOptions>[];
  });

  ContabilidadRepository buildRepository(
    ResponseBody Function(RequestOptions) h,
  ) {
    return ContabilidadRepository(
      Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          captured.add(options);
          return h(options);
        }),
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

  test('createNcfSequence posts voucher payload to /ncf/sequences', () async {
    final repository = buildRepository(
      (options) => jsonResponse({
        'id': 'seq-1',
        'voucherType': 'B01',
        'prefix': 'B01',
        'startNumber': 1,
        'nextNumber': 1,
        'endNumber': 100000,
        'validUntil': null,
        'active': true,
      }),
    );

    final model = await repository.createNcfSequence(
      voucherType: 'b01',
      startNumber: 1,
      endNumber: 100000,
      active: true,
    );

    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/ncf/sequences');
    final data = captured.single.data as Map<String, dynamic>;
    expect(data['voucherType'], 'B01');
    expect(data['prefix'], 'B01');
    expect(data['startNumber'], 1);
    expect(data['endNumber'], 100000);
    expect(data['active'], true);
    expect(data.containsKey('validUntil'), isFalse);
    expect(model.id, 'seq-1');
    expect(model.voucherType, 'B01');
  });

  test('createNcfSequence sends validUntil when provided', () async {
    final repository = buildRepository(
      (options) => jsonResponse({
        'id': 'seq-2',
        'voucherType': 'B02',
        'prefix': 'B02',
        'startNumber': 1,
        'nextNumber': 1,
        'endNumber': 5000,
        'validUntil': null,
        'active': true,
      }),
    );

    await repository.createNcfSequence(
      voucherType: 'B02',
      startNumber: 1,
      endNumber: 5000,
      validUntil: DateTime.utc(2026, 12, 31),
      active: true,
    );

    final data = captured.single.data as Map<String, dynamic>;
    expect(data['validUntil'], '2026-12-31T00:00:00.000Z');
  });

  test('updateNcfSequence patches only the provided fields', () async {
    final repository = buildRepository(
      (options) => jsonResponse({
        'id': 'seq-1',
        'voucherType': 'B01',
        'prefix': 'B01',
        'startNumber': 1,
        'nextNumber': 42,
        'endNumber': 99999,
        'validUntil': null,
        'active': true,
      }),
    );

    final model = await repository.updateNcfSequence(
      'seq-1',
      endNumber: 99999,
      active: true,
    );

    expect(captured.single.method, 'PATCH');
    expect(captured.single.path, '/ncf/sequences/seq-1');
    final data = captured.single.data as Map<String, dynamic>;
    expect(data['endNumber'], 99999);
    expect(data['active'], true);
    expect(data.containsKey('validUntil'), isFalse);
    expect(model.endNumber, 99999);
    expect(model.active, isTrue);
  });

  test('listNcfSequences parses the array response', () async {
    final repository = buildRepository(
      (options) => jsonResponse([
        {
          'id': 'seq-1',
          'voucherType': 'B01',
          'prefix': 'B01',
          'startNumber': 1,
          'nextNumber': 42,
          'endNumber': 100000,
          'validUntil': null,
          'active': true,
          'status': 'ACTIVE',
        },
      ]),
    );

    final rows = await repository.listNcfSequences();

    expect(rows, hasLength(1));
    expect(rows.single.voucherType, 'B01');
    expect(rows.single.possibleNextNcf, 'B0100000042');
    expect(rows.single.status, 'ACTIVE');
  });

  test('createNcfSequence surfaces ApiException with backend message', () async {
    final repository = buildRepository(
      (options) => jsonResponse({
        'message': 'Rango solapado con otra secuencia.',
      }, 400),
    );

    await expectLater(
      repository.createNcfSequence(
        voucherType: 'B01',
        startNumber: 1,
        endNumber: 10,
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Rango solapado'),
        ),
      ),
    );
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
