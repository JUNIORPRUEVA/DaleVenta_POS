import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/guardian/guardian_event.dart';
import 'package:daleventa_pos/core/guardian/guardian_machine_transport.dart';

/// Adaptador HTTP falso: no sale ningún tráfico real.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.status, required this.body});

  final int status;
  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

GuardianEvent _event(String id) => GuardianEvent(
  eventId: id,
  severity: 'SEV2',
  module: 'flutter',
  operation: 'GET /selftest',
  occurredAt: DateTime.now(),
);

MachineGuardianTransport _transport({
  required String credential,
  required _FakeAdapter adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return MachineGuardianTransport(
    baseUrl: 'https://guardian.example.com/',
    path: '/guardian/machine/incidents',
    credential: credential,
    dio: dio,
  );
}

void main() {
  test(
    'missing, foreign or conflicting confirmations never acknowledge saved events',
    () {
      final events = [_event('evt-1')];
      expect(parseGuardianIngestResponse({}, events).acked, isEmpty);
      expect(
        parseGuardianIngestResponse({
          'results': [
            {'eventId': 'other', 'status': 'accepted'},
          ],
        }, events).acked,
        isEmpty,
      );
      expect(
        parseGuardianIngestResponse({
          'results': [
            {'eventId': 'evt-1', 'status': 'accepted'},
            {'eventId': 'evt-1', 'status': 'rejected'},
          ],
        }, events).acked,
        isEmpty,
      );
      expect(
        parseGuardianIngestResponse({'results': 'invalid'}, events).retryable,
        isTrue,
      );
    },
  );
  test(
    'disabled monitoring and temporary persistence failure retain retryable events',
    () {
      for (final reason in [
        'COMPANY_GUARDIAN_DISABLED',
        'PERSIST_FAILED',
        'HOURLY_QUOTA_EXCEEDED',
        'COMPANY_SCOPE_MISMATCH',
      ]) {
        final result = parseGuardianIngestResponse(
          {
            'retryAfterSeconds': 600,
            'results': [
              {'eventId': 'evt-1', 'status': 'rejected', 'reason': reason},
            ],
          },
          [_event('evt-1')],
        );
        expect(result.rejected, isEmpty);
        expect(result.retryable, isTrue);
        expect(result.retryAfterMs, 600000);
      }
    },
  );
  group('MachineGuardianTransport — credencial de instalación', () {
    test('envía la credencial de instalación y no un JWT de usuario', () async {
      final adapter = _FakeAdapter(
        status: 202,
        body:
            '{"ok":true,"accepted":1,"duplicates":0,"rejected":0,'
            '"results":[{"eventId":"evt-1","status":"accepted"}]}',
      );
      final transport = _transport(
        credential: 'gmk_clave_de_instalacion',
        adapter: adapter,
      );

      final result = await transport.send(<GuardianEvent>[_event('evt-1')]);

      expect(
        adapter.lastRequest!.headers['x-guardian-key'],
        'gmk_clave_de_instalacion',
      );
      expect(
        adapter.lastRequest!.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(adapter.lastRequest!.headers['x-guardian-ts'], isNotNull);
      expect(
        adapter.lastRequest!.uri.toString(),
        'https://guardian.example.com/guardian/machine/incidents',
      );
      expect(result.acked, <String>['evt-1']);
    });

    test('marca duplicados como durables', () async {
      final adapter = _FakeAdapter(
        status: 202,
        body:
            '{"ok":false,"accepted":0,"duplicates":1,"rejected":0,'
            '"results":[{"eventId":"evt-1","status":"duplicate"}]}',
      );
      final transport = _transport(credential: 'gmk_x', adapter: adapter);

      final result = await transport.send(<GuardianEvent>[_event('evt-1')]);

      expect(result.duplicates, <String>['evt-1']);
      expect(result.rejected, isEmpty);
    });

    test('no reintenta credenciales rechazadas (401/403)', () async {
      for (final status in <int>[401, 403]) {
        final adapter = _FakeAdapter(
          status: status,
          body: '{"code":"MACHINE_KEY_INVALID"}',
        );
        final transport = _transport(credential: 'gmk_x', adapter: adapter);
        final result = await transport.send(<GuardianEvent>[_event('evt-1')]);
        expect(result.retryable, isTrue, reason: 'status $status');
        expect(result.rejected, isEmpty);
      }
    });

    test('un 5xx es recuperable', () async {
      final adapter = _FakeAdapter(status: 503, body: '{}');
      final transport = _transport(credential: 'gmk_x', adapter: adapter);
      final result = await transport.send(<GuardianEvent>[_event('evt-1')]);
      expect(result.retryable, isTrue);
      expect(result.rejected, isEmpty);
    });

    test('sin credencial no envía nada y reintenta después', () async {
      final adapter = _FakeAdapter(status: 202, body: '{}');
      final transport = _transport(credential: '', adapter: adapter);
      final result = await transport.send(<GuardianEvent>[_event('evt-1')]);
      expect(adapter.lastRequest, isNull);
      expect(result.retryable, isTrue);
      expect(result.reason, 'SIN_CREDENCIAL');
    });

    test('un lote vacío no genera tráfico', () async {
      final adapter = _FakeAdapter(status: 202, body: '{}');
      final transport = _transport(credential: 'gmk_x', adapter: adapter);
      await transport.send(<GuardianEvent>[]);
      expect(adapter.lastRequest, isNull);
    });
  });
}
