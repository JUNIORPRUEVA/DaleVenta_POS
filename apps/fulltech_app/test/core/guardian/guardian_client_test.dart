import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/guardian/guardian_client.dart';
import 'package:daleventa_pos/core/guardian/guardian_config.dart';
import 'package:daleventa_pos/core/guardian/guardian_event.dart';
import 'package:daleventa_pos/core/guardian/guardian_store.dart';
import 'package:daleventa_pos/core/guardian/guardian_transport.dart';

class _FakeTransport implements GuardianTransport {
  _FakeTransport(this.handler);

  final Future<GuardianSendResult> Function(List<GuardianEvent> events) handler;
  int calls = 0;
  List<GuardianEvent> lastBatch = const [];

  @override
  Future<GuardianSendResult> send(List<GuardianEvent> events) async {
    calls += 1;
    lastBatch = events;
    return handler(events);
  }
}

GuardianConfig _config({bool enabled = true, int maxEvents = 200}) {
  return GuardianConfig(
    enabled: enabled,
    endpointPath: '/guardian/incidents',
    maxEvents: maxEvents,
    maxBytes: 1024 * 1024,
    batchSize: 20,
    minSeverityToPersist: 'SEV3',
    sampleRateSev3Sev4: 1,
    flushInterval: const Duration(minutes: 2),
  );
}

GuardianEvent _event({
  String? eventId,
  String severity = 'SEV2',
  String module = 'cash',
  String operation = 'closeSession',
  String? exceptionType = 'TimeoutError',
  String? stack = 'at CashService.close (cash.dart:10:3)',
  int attempts = 0,
  int nextAttemptAtMs = 0,
}) {
  return GuardianEvent(
    eventId: eventId ?? 'evt-${DateTime.now().microsecondsSinceEpoch}',
    severity: severity,
    module: module,
    operation: operation,
    occurredAt: DateTime.now(),
    exceptionType: exceptionType,
    platform: 'windows',
    appVersion: '1.0.0+1',
    deviceId: 'dev-1',
    stack: stack,
    message: 'mensaje de prueba',
    attempts: attempts,
    nextAttemptAtMs: nextAttemptAtMs,
  );
}

void main() {
  group('GuardianClient — cola local', () {
    test('desactivado no persiste nada', () async {
      final store = InMemoryGuardianStore();
      final client = GuardianClient(
        store: store,
        transport: _FakeTransport((_) async => const GuardianSendResult()),
        config: _config(enabled: false),
      );

      expect(await client.record(_event()), isFalse);
      expect(await store.count(), 0);
    });

    test('persiste el incidente y deduplica el mismo patrón en ventana corta', () async {
      final store = InMemoryGuardianStore();
      final client = GuardianClient(
        store: store,
        transport: _FakeTransport((_) async => const GuardianSendResult()),
        config: _config(),
      );

      expect(await client.record(_event()), isTrue);
      expect(await client.record(_event()), isFalse);
      expect(await store.count(), 1);
    });

    test('no persiste SEV4 cuando la severidad mínima es SEV3', () async {
      final store = InMemoryGuardianStore();
      final client = GuardianClient(
        store: store,
        transport: _FakeTransport((_) async => const GuardianSendResult()),
        config: _config(),
      );

      expect(await client.record(_event(severity: 'SEV4')), isFalse);
      expect(await store.count(), 0);
    });

    test('un evento solo se borra tras confirmación durable del servidor', () async {
      final store = InMemoryGuardianStore();
      final transport = _FakeTransport((_) async => const GuardianSendResult(retryable: true, reason: 'sin red'));
      final client = GuardianClient(store: store, transport: transport, config: _config());

      final event = _event();
      await client.record(event);
      final summary = await client.flush();

      expect(summary.retried, 1);
      expect(await store.count(), 1, reason: 'sin ACK no se puede borrar');

      final due = await store.dueEvents(limit: 10, now: DateTime.now().add(const Duration(hours: 1)));
      expect(due.single.attempts, 1);
      expect(due.single.nextAttemptAtMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('ACK del servidor limpia la cola y los duplicados también son durables', () async {
      final store = InMemoryGuardianStore();
      var call = 0;
      final transport = _FakeTransport((events) async {
        call += 1;
        if (call == 1) {
          return GuardianSendResult(acked: [events.first.eventId], retryable: false);
        }
        return GuardianSendResult(duplicates: [events.first.eventId], retryable: false);
      });
      final client = GuardianClient(store: store, transport: transport, config: _config());

      await client.record(_event(eventId: 'evt-a', operation: 'op1'));
      await client.flush();
      expect(await store.count(), 0);

      await client.record(_event(eventId: 'evt-b', operation: 'op2'));
      await client.flush();
      expect(await store.count(), 0);
    });

    test('un rechazo permanente se registra como descarte y no se reintenta', () async {
      final store = InMemoryGuardianStore();
      final transport = _FakeTransport(
        (events) async => GuardianSendResult(
          rejected: events.map((event) => event.eventId).toList(),
          retryable: false,
          reason: 'INVALID_OCCURRED_AT',
        ),
      );
      final client = GuardianClient(store: store, transport: transport, config: _config());

      await client.record(_event());
      final summary = await client.flush();

      expect(summary.rejected, 1);
      expect(await store.count(), 0);
      final discards = await store.discards();
      expect(discards.single.reason, 'INVALID_OCCURRED_AT');
    });

    test('respeta el límite de eventos sin descartar nunca SEV1', () async {
      final store = InMemoryGuardianStore();
      final client = GuardianClient(
        store: store,
        transport: _FakeTransport((_) async => const GuardianSendResult()),
        config: _config(maxEvents: 2),
      );

      await client.record(_event(eventId: 'critico', severity: 'SEV1', operation: 'op-critica'));
      for (var index = 0; index < 5; index += 1) {
        await client.record(_event(eventId: 'ruido-$index', severity: 'SEV3', operation: 'op-$index'));
      }

      expect(await store.count(), lessThanOrEqualTo(2));
      final due = await store.dueEvents(limit: 10);
      expect(due.any((event) => event.eventId == 'critico'), isTrue);
      expect((await store.discards()).isNotEmpty, isTrue);
    });

    test('prioriza severidades altas en el siguiente envío', () async {
      final store = InMemoryGuardianStore();
      final transport = _FakeTransport((_) async => const GuardianSendResult(retryable: true));
      final client = GuardianClient(store: store, transport: transport, config: _config());

      await client.record(_event(eventId: 'sev3-1', severity: 'SEV3', operation: 'op3'));
      await client.record(_event(eventId: 'sev1-1', severity: 'SEV1', operation: 'op1'));

      await client.flush();
      expect(transport.lastBatch.first.severity, 'SEV1');
    });
  });
}
