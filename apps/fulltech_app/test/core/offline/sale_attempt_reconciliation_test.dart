import 'dart:async';

import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

const _requestId = '3f2c1b90-8b1e-4b39-9b0e-6c2f5d7a1e44';

PendingSyncAction _attempt({
  String id = 'sales.attempt:$_requestId',
  String type = 'sales.attempt',
  String? idempotencyKey = _requestId,
  Map<String, dynamic> payload = const {'expectedTotalSold': 1305.0},
}) {
  final now = DateTime.utc(2026, 10, 7, 21, 26);
  return PendingSyncAction(
    id: id,
    type: type,
    scope: 'sales',
    companyId: 'company-a',
    userId: 'user-1',
    idempotencyKey: idempotencyKey,
    entityId: _requestId,
    operationFingerprint: 'fingerprint-1',
    payload: payload,
    status: 'requires_action',
    attempts: 0,
    error: 'No pudimos confirmar el resultado de este cobro.',
    permanent: true,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _response(
  String status, {
  Map<String, dynamic>? sale,
  String? guidance,
  bool voided = false,
}) {
  return {
    'status': status,
    'clientRequestId': _requestId,
    'retryAllowed': false,
    'assertsPaymentReceived': false,
    'guidance': guidance,
    'voided': voided,
    'sale': sale,
    'movement': null,
  };
}

/// Registro de lo que el reconciliador pidió persistir.
class _Recorder {
  final List<SaleAttemptDecision> decisions = [];
  final List<String> resolvedIds = [];
  final List<String?> notes = [];
  final List<String?> roles = [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Recorder recorder;

  setUp(() {
    SaleAttemptReconciler.resetInFlightForTests();
    recorder = _Recorder();
  });

  SaleAttemptReconciler build({
    required Future<Map<String, dynamic>?> Function(
      String clientRequestId,
      double? expectedTotalSold,
    )
    lookup,
    List<PendingSyncAction>? pending,
  }) {
    return SaleAttemptReconciler(
      lookup: lookup,
      listAttempts: ({companyId, userId}) async =>
          pending ?? <PendingSyncAction>[],
      recordEvidence:
          ({
            required action,
            required clientRequestId,
            required result,
            required decision,
            actorUserId,
            actorRole,
            note,
          }) async {
            recorder.decisions.add(decision);
            recorder.notes.add(note);
            recorder.roles.add(actorRole);
          },
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
            recorder.decisions.add(decision);
            recorder.notes.add(note);
            recorder.roles.add(actorRole);
            recorder.resolvedIds.add(action.id);
            return true;
          },
    );
  }

  test('CONFIRMED retira el aviso y no reenvía nada', () async {
    var calls = 0;
    final reconciler = build(
      lookup: (String id, double? expected) async {
        calls++;
        expect(id, _requestId);
        expect(expected, 1305.0);
        return _response(
          'CONFIRMED',
          sale: {'id': 'sale-1', 'totalSold': 1305.0},
        );
      },
    );

    final result = await reconciler.verify(_attempt());

    expect(result?.status, SaleAttemptReconciliationStatus.confirmed);
    expect(result?.saleId, 'sale-1');
    expect(recorder.resolvedIds, ['sales.attempt:$_requestId']);
    expect(recorder.decisions.single, SaleAttemptDecision.autoConfirmed);
    expect(calls, 1);
  });

  test('una venta anulada se registra como anulada, no como rechazo', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response(
        'CONFIRMED',
        sale: {'id': 'sale-2', 'totalSold': 1305.0},
        guidance: 'REGISTERED_THEN_VOIDED',
        voided: true,
      ),
    );

    final result = await reconciler.verify(_attempt());

    expect(result?.voided, isTrue);
    expect(result?.guidance, 'REGISTERED_THEN_VOIDED');
    expect(
      recorder.decisions.single,
      SaleAttemptDecision.autoRegisteredThenVoided,
    );
  });

  test('DEFINITIVELY_REJECTED NO retira el aviso sin revisión', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async =>
          _response('DEFINITIVELY_REJECTED'),
    );

    final result = await reconciler.verify(_attempt());

    expect(
      result?.status,
      SaleAttemptReconciliationStatus.definitivelyRejected,
    );
    expect(recorder.resolvedIds, isEmpty);
    expect(recorder.decisions.single, SaleAttemptDecision.keptInconclusive);
  });

  test('NOT_FOUND conserva el intento intacto', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('NOT_FOUND'),
    );

    final result = await reconciler.verify(_attempt());

    expect(result?.status, SaleAttemptReconciliationStatus.notFound);
    expect(recorder.resolvedIds, isEmpty);
    expect(recorder.decisions.single, SaleAttemptDecision.keptInconclusive);
  });

  test('UNKNOWN conserva el intento intacto', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('UNKNOWN'),
    );

    final result = await reconciler.verify(_attempt());

    expect(result?.status, SaleAttemptReconciliationStatus.unknown);
    expect(recorder.resolvedIds, isEmpty);
  });

  test('sin respuesta del backend no se resuelve nada', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => null,
    );

    final result = await reconciler.verify(_attempt());

    expect(result, isNull);
    expect(recorder.resolvedIds, isEmpty);
    expect(recorder.decisions, isEmpty);
  });

  test('un error de red no resuelve nada', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async =>
          throw StateError('sin conexión'),
    );

    final result = await reconciler.verify(_attempt());

    expect(result, isNull);
    expect(recorder.resolvedIds, isEmpty);
  });

  test('quita el prefijo sales.attempt: antes de consultar', () async {
    String? consultado;
    final reconciler = build(
      lookup: (String id, double? expected) async {
        consultado = id;
        return _response('NOT_FOUND');
      },
    );

    await reconciler.verify(_attempt(idempotencyKey: 'sales.attempt:$_requestId'));

    expect(consultado, _requestId);
  });

  test('dos verificaciones simultáneas solo consultan una vez', () async {
    var calls = 0;
    final gate = Completer<void>();
    final reconciler = build(
      lookup: (String id, double? expected) async {
        calls++;
        await gate.future;
        return _response('NOT_FOUND');
      },
    );
    final action = _attempt();

    final first = reconciler.verify(action);
    final second = await reconciler.verify(action);
    gate.complete();
    await first;

    expect(second, isNull);
    expect(calls, 1);
  });

  test('ignora operaciones que no son intentos de cobro', () async {
    var calls = 0;
    final reconciler = build(
      lookup: (String id, double? expected) async {
        calls++;
        return _response('CONFIRMED');
      },
    );

    final result = await reconciler.verify(_attempt(type: 'sale.create'));

    expect(result, isNull);
    expect(calls, 0);
  });

  test('el barrido cuenta resueltos, dudosos e inalcanzables', () async {
    final reconciler = build(
      pending: [
        _attempt(id: 'a', idempotencyKey: 'req-a'),
        _attempt(id: 'b', idempotencyKey: 'req-b'),
        _attempt(id: 'c', idempotencyKey: 'req-c'),
      ],
      lookup: (String id, double? expected) async {
        if (id == 'req-a') return _response('CONFIRMED');
        if (id == 'req-b') return _response('NOT_FOUND');
        return null;
      },
    );

    final summary = await reconciler.syncPendingAttempts(companyId: 'company-a');

    expect(summary.confirmed, 1);
    expect(summary.inconclusive, 1);
    expect(summary.unreachable, 1);
    expect(summary.hasChanges, isTrue);
  });

  test('guarda evidencia incluso cuando resuelve el aviso', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async =>
          _response('CONFIRMED', sale: {'id': 'sale-9'}),
    );

    await reconciler.verify(_attempt());

    // La evidencia se pide SIEMPRE, y el aviso solo se retira después.
    expect(recorder.decisions, isNotEmpty);
    expect(recorder.resolvedIds, isNotEmpty);
  });

  test('la resolución manual del encargado cierra con rastro del actor',
      () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('NOT_FOUND'),
    );

    final resolved = await reconciler.resolveManually(
      action: _attempt(),
      decision: SaleAttemptDecision.manualNotPerformed,
      actorUserId: 'owner-1',
      actorRole: 'OWNER',
      note: 'Se revisó el datáfono: no hubo cargo.',
    );

    expect(resolved, isTrue);
    expect(recorder.resolvedIds, ['sales.attempt:$_requestId']);
    expect(recorder.roles.single, 'OWNER');
    expect(recorder.notes.single, contains('no hubo cargo'));
  });

  test('escalar a revisión deja el intento intacto', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('UNKNOWN'),
    );

    final resolved = await reconciler.resolveManually(
      action: _attempt(),
      decision: SaleAttemptDecision.manualEscalated,
      actorUserId: 'owner-1',
      actorRole: 'OWNER',
    );

    expect(resolved, isFalse);
    expect(recorder.resolvedIds, isEmpty);
    expect(recorder.decisions.single, SaleAttemptDecision.manualEscalated);
  });

  test('una decisión automática no se puede aplicar a mano', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('CONFIRMED'),
    );

    final resolved = await reconciler.resolveManually(
      action: _attempt(),
      decision: SaleAttemptDecision.autoConfirmed,
    );

    expect(resolved, isFalse);
    expect(recorder.resolvedIds, isEmpty);
  });

  test('declarar dinero recibido cierra la incidencia con decisión propia',
      () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('UNKNOWN'),
    );

    final resolved = await reconciler.resolveManually(
      action: _attempt(),
      decision: SaleAttemptDecision.manualMoneyReceived,
      actorRole: 'OWNER',
      note: 'El comprobante del banco coincide con el importe.',
    );

    expect(resolved, isTrue);
    expect(
      recorder.decisions.single,
      SaleAttemptDecision.manualMoneyReceived,
    );
  });

  test('autorizar una venta nueva NO cierra la incidencia', () async {
    final reconciler = build(
      lookup: (String id, double? expected) async => _response('UNKNOWN'),
    );

    final resolved = await reconciler.resolveManually(
      action: _attempt(),
      decision: SaleAttemptDecision.manualAuthorizedNewSale,
      actorRole: 'OWNER',
      note: 'Compra nueva del mismo cliente',
    );

    expect(resolved, isFalse);
    expect(recorder.resolvedIds, isEmpty);
    expect(
      recorder.decisions.single,
      SaleAttemptDecision.manualAuthorizedNewSale,
    );
  });
}
