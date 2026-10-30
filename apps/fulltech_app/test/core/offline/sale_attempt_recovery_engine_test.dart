import 'dart:math';

import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_recovery_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Motor de recuperación automática: comportamiento verificable sin red real.
///
/// Lo que estas pruebas protegen:
///  - sin pendientes no se hace NI UNA consulta;
///  - un fallo técnico no resuelve nada y solo activa backoff;
///  - dos pasadas simultáneas no duplican consultas;
///  - el 429 con Retry-After se respeta incluso en disparadores manuales;
///  - el estado sobrevive al cierre de la app;
///  - una pasada nunca supera el máximo de consultas.
void main() {
  late List<PendingSyncAction> attempts;
  late int lookups;
  late Map<String, dynamic>? nextResponse;
  late DateTime now;
  late InMemoryRecoveryEngineStore store;

  DateTime clock() => now;

  PendingSyncAction attempt(String requestId, {double total = 50}) {
    return PendingSyncAction(
      id: 'sales.attempt:$requestId',
      type: 'sales.attempt',
      scope: 'sales',
      companyId: 'company-a',
      userId: 'user-a',
      idempotencyKey: requestId,
      operationFingerprint: 'fp-$requestId',
      payload: {'expectedTotalSold': total},
      status: 'requires_action',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  SaleAttemptReconciler buildReconciler() {
    return SaleAttemptReconciler(
      lookup: (requestId, expected) async {
        lookups++;
        return nextResponse;
      },
      listAttempts: ({companyId, userId}) async => List.of(attempts),
      recordEvidence:
          ({
            required action,
            required clientRequestId,
            required result,
            required decision,
            actorUserId,
            actorRole,
            note,
          }) async {},
      resolveAttempt:
          ({
            required action,
            required clientRequestId,
            required result,
            required decision,
            actorUserId,
            actorRole,
            note,
          }) async {
            attempts.removeWhere((a) => a.id == action.id);
            return true;
          },
    );
  }

  SaleAttemptRecoveryEngine buildEngine({
    RecoveryBackoffPolicy? policy,
    int? seed,
  }) {
    return SaleAttemptRecoveryEngine(
      reconciler: buildReconciler(),
      countPending: ({companyId, userId}) async => attempts.length,
      store: store,
      policy: policy ?? const RecoveryBackoffPolicy(),
      clock: clock,
      random: Random(seed ?? 7),
    );
  }

  setUp(() {
    attempts = [];
    lookups = 0;
    nextResponse = null;
    now = DateTime.utc(2026, 10, 29, 12);
    store = InMemoryRecoveryEngineStore();
    SaleAttemptReconciler.resetInFlightForTests();
  });

  test('sin incidencias pendientes no se consulta nada', () async {
    final engine = buildEngine();
    final outcome = await engine.runOnce();
    expect(outcome, RecoveryRunOutcome.idle);
    expect(lookups, 0);
    expect(engine.state.pendingAttempts, 0);
    expect(engine.state.nextRunAt, isNull);
  });

  test('CONFIRMED resuelve el intento automáticamente', () async {
    attempts = [attempt('req-1')];
    nextResponse = {
      'status': 'CONFIRMED',
      'clientRequestId': 'req-1',
      'sale': {'id': 'sale-1', 'totalSold': 50.0, 'paymentMethod': 'cash'},
      'guidance': 'ALREADY_REGISTERED',
    };
    final engine = buildEngine();
    final outcome = await engine.runOnce();
    expect(outcome, RecoveryRunOutcome.completed);
    expect(lookups, 1);
    expect(
      attempts,
      isEmpty,
      reason: 'el intento confirmado se retira del aviso',
    );
    expect(engine.state.pendingAttempts, 0);
    expect(engine.state.consecutiveFailures, 0);
  });

  test('NOT_FOUND conserva el intento y no inventa resolución', () async {
    attempts = [attempt('req-2')];
    nextResponse = {'status': 'NOT_FOUND', 'clientRequestId': 'req-2'};
    final engine = buildEngine();
    final outcome = await engine.runOnce();
    expect(outcome, RecoveryRunOutcome.completed);
    expect(
      attempts,
      hasLength(1),
      reason: 'sin evidencia concluyente no se cierra',
    );
    expect(engine.state.pendingAttempts, 1);
  });

  test('fallo de red: no resuelve, cuenta fallo y programa espera', () async {
    attempts = [attempt('req-3')];
    nextResponse = null; // lookup devuelve null = sin respuesta
    final engine = buildEngine();
    final outcome = await engine.runOnce();
    expect(outcome, RecoveryRunOutcome.partiallyUnreachable);
    expect(attempts, hasLength(1));
    expect(engine.state.consecutiveFailures, 1);
    expect(engine.state.nextRunAt, isNotNull);
    expect(engine.state.suspendedUntil, isNotNull);
  });

  test('el backoff crece y queda acotado por el máximo', () async {
    final policy = RecoveryBackoffPolicy(
      base: const Duration(seconds: 30),
      max: const Duration(minutes: 5),
      jitterRatio: 0,
    );
    expect(policy.delayFor(1, random: Random(1)), const Duration(seconds: 30));
    expect(policy.delayFor(2, random: Random(1)), const Duration(seconds: 60));
    expect(policy.delayFor(3, random: Random(1)), const Duration(seconds: 120));
    expect(
      policy.delayFor(20, random: Random(1)),
      const Duration(minutes: 5),
      reason: 'nunca supera el máximo',
    );
  });

  test(
    'el disparador periódico respeta la espera; la reconexión la adelanta',
    () async {
      attempts = [attempt('req-4')];
      nextResponse = null;
      final engine = buildEngine();
      await engine.runOnce();
      lookups = 0;

      now = now.add(const Duration(seconds: 5));
      expect(engine.shouldRunNow(RecoveryTrigger.periodic), isFalse);
      final deferred = await engine.runOnce(trigger: RecoveryTrigger.periodic);
      expect(deferred, RecoveryRunOutcome.deferred);
      expect(lookups, 0, reason: 'no se consulta antes de tiempo');

      expect(engine.shouldRunNow(RecoveryTrigger.connectivityRestored), isTrue);
      await engine.runOnce(trigger: RecoveryTrigger.connectivityRestored);
      expect(lookups, 1);
    },
  );

  test(
    '429 con Retry-After se respeta aunque el disparador sea manual',
    () async {
      attempts = [attempt('req-5')];
      nextResponse = {'status': 'NOT_FOUND', 'clientRequestId': 'req-5'};
      final engine = buildEngine();
      engine.noteRateLimit(const Duration(minutes: 2));
      final outcome = await engine.runOnce(trigger: RecoveryTrigger.manual);
      expect(outcome, RecoveryRunOutcome.deferred);
      expect(lookups, 0, reason: 'no se martillea el servidor');

      now = now.add(const Duration(minutes: 3));
      expect(engine.shouldRunNow(RecoveryTrigger.manual), isTrue);
      await engine.runOnce(trigger: RecoveryTrigger.manual);
      expect(lookups, 1);
    },
  );

  test('dos pasadas simultáneas no duplican consultas', () async {
    attempts = [attempt('req-6')];
    nextResponse = {'status': 'NOT_FOUND', 'clientRequestId': 'req-6'};
    final engine = buildEngine();
    final results = await Future.wait([engine.runOnce(), engine.runOnce()]);
    expect(
      results.where((r) => r == RecoveryRunOutcome.deferred),
      hasLength(1),
    );
    expect(lookups, 1);
  });

  test('el estado persiste y se restaura tras reabrir la aplicación', () async {
    attempts = [attempt('req-7')];
    nextResponse = null;
    final first = buildEngine();
    await first.runOnce();
    expect(first.state.consecutiveFailures, 1);

    SaleAttemptReconciler.resetInFlightForTests();
    final second = buildEngine();
    await second.restore();
    expect(
      second.state.consecutiveFailures,
      1,
      reason: 'el backoff no se reinicia al abrir la app',
    );
    expect(second.state.nextRunAt, isNotNull);
  });

  test('una pasada nunca supera el máximo de consultas configurado', () async {
    attempts = List.generate(30, (i) => attempt('req-bulk-$i'));
    nextResponse = {'status': 'NOT_FOUND', 'clientRequestId': 'req-bulk'};
    final engine = buildEngine(
      policy: const RecoveryBackoffPolicy(maxAttemptsPerRun: 5),
    );
    await engine.runOnce();
    expect(lookups, 5, reason: 'pasada acotada');
    expect(attempts, hasLength(30), reason: 'lo no procesado sigue pendiente');
  });

  test('un éxito posterior limpia el backoff', () async {
    attempts = [attempt('req-8')];
    nextResponse = null;
    final engine = buildEngine();
    await engine.runOnce();
    expect(engine.state.consecutiveFailures, 1);

    nextResponse = {
      'status': 'CONFIRMED',
      'clientRequestId': 'req-8',
      'sale': {'id': 'sale-8', 'totalSold': 50.0},
    };
    await engine.runOnce(trigger: RecoveryTrigger.connectivityRestored);
    expect(engine.state.consecutiveFailures, 0);
    expect(engine.state.nextRunAt, isNull);
    expect(engine.state.suspendedUntil, isNull);
  });
}
