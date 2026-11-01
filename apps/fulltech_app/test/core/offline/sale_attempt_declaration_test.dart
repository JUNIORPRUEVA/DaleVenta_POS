import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_declaration.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

const _requestId = '3f2c1b90-8b1e-4b39-9b0e-6c2f5d7a1e44';

PendingSyncAction _attempt({
  String? idempotencyKey = _requestId,
  Map<String, dynamic> payload = const {
    'expectedTotalSold': 1305.0,
    'paymentMethod': 'cash',
  },
}) {
  final now = DateTime.utc(2026, 10, 7, 21, 26);
  return PendingSyncAction(
    id: 'sales.attempt:$_requestId',
    type: 'sales.attempt',
    scope: 'sales',
    companyId: 'company-a',
    userId: 'user-1',
    idempotencyKey: idempotencyKey,
    entityId: _requestId,
    operationFingerprint: 'fingerprint-1',
    payload: payload,
    status: 'requires_action',
    attempts: 0,
    permanent: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SaleAttemptDeclaration', () {
    SaleAttemptDeclaration build({
      double total = 1305,
      String note = 'Cobrado en caja, no salió ticket',
      DateTime? at,
    }) {
      return SaleAttemptDeclaration(
        clientRequestId: _requestId,
        totalDeclared: total,
        declaredAtUtc: at ?? DateTime.utc(2026, 10, 7, 21, 40, 5, 123),
        paymentMethod: 'cash',
        declaredByUserId: 'user-1',
        declaredByRole: 'OWNER',
        note: note,
        operationFingerprint: 'fingerprint-1',
      );
    }

    test('la identidad local es estable y una corrección es otra declaración', () {
      final first = build();
      final same = build();
      final corrected = build(total: 1400);

      expect(first.localId, same.localId);
      expect(first.contentHash, same.contentHash);
      expect(corrected.localId, isNot(first.localId));
      expect(first.localId, startsWith('sales.declaration:$_requestId:'));
    });

    test('el cuerpo enviado lleva importe numérico a 2 decimales y hora UTC ISO', () {
      final body = build(total: 1305.005).toRequestBody();
      expect(body['totalDeclared'], isA<double>());
      expect(body['declaredAtUtc'], '2026-10-07T21:40:05.123Z');
      expect(body['paymentMethod'], 'cash');
      expect(body['declaredByRole'], 'OWNER');
      expect(body['operationFingerprint'], 'fingerprint-1');
      // Sin contenido del intento no se inventa uno.
      expect(body.containsKey('attemptPayload'), isFalse);
    });

    test('sobrevive el viaje por la cola local (payload ↔ modelo)', () {
      final original = build();
      final restored = SaleAttemptDeclaration.fromQueuePayload(
        original.toQueuePayload(companyId: 'company-a', userId: 'user-1'),
      );
      expect(restored, isNotNull);
      expect(restored!.clientRequestId, _requestId);
      expect(restored.normalizedTotal, '1305.00');
      expect(restored.declaredAtUtc.isUtc, isTrue);
      expect(restored.declaredByRole, 'OWNER');
      expect(restored.contentHash, original.contentHash);
    });

    test('no se considera válida sin importe', () {
      expect(build(total: 0).isValid, isFalse);
      expect(build().isValid, isTrue);
    });
  });

  group('SaleAttemptDeclarationOutbox', () {
    test('encola la declaración como obligación, no como cobro', () async {
      final enqueued = <PendingSyncAction>[];
      final outbox = SaleAttemptDeclarationOutbox(
        enqueueAction: (action) async => enqueued.add(action),
        clock: () => DateTime.utc(2026, 10, 7, 21, 45),
      );

      final declaration = await outbox.declare(
        action: _attempt(),
        totalDeclared: 1305,
        actorUserId: 'user-1',
        actorRole: 'OWNER',
        note: 'Cliente pagó en efectivo',
      );

      expect(declaration, isNotNull);
      expect(enqueued, hasLength(1));
      final action = enqueued.single;
      expect(action.type, 'sales.declaration');
      expect(action.scope, 'sales');
      expect(action.idempotencyKey, declaration!.localId);
      expect(action.entityId, _requestId);
      expect(action.companyId, 'company-a');
      expect(action.payload['clientRequestId'], _requestId);
      expect(action.payload['totalDeclared'], 1305.0);
      expect(action.payload['note'], 'Cliente pagó en efectivo');
      expect(action.attempts, 0);
    });

    test('rechaza un importe no declarable sin encolar nada', () async {
      var calls = 0;
      final outbox = SaleAttemptDeclarationOutbox(
        enqueueAction: (action) async => calls++,
      );
      final declaration = await outbox.declare(
        action: _attempt(),
        totalDeclared: 0,
        actorRole: 'OWNER',
        note: 'sin importe',
      );
      expect(declaration, isNull);
      expect(calls, 0);
    });
  });

  group('SaleAttemptReconciler · declaración de dinero recibido', () {
    setUp(SaleAttemptReconciler.resetInFlightForTests);

    test('registra la obligación ANTES de cerrar la incidencia', () async {
      final order = <String>[];
      final reconciler = SaleAttemptReconciler(
        lookup: (id, expected) async => null,
        listAttempts: ({companyId, userId}) async => const [],
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
              order.add('evidence');
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
              order.add('resolve');
              return true;
            },
        declareMoneyReceived:
            ({
              required action,
              required totalDeclared,
              actorUserId,
              actorRole,
              note,
            }) async {
              order.add('declare:${totalDeclared.toStringAsFixed(2)}');
              return true;
            },
      );

      final resolved = await reconciler.resolveManually(
        action: _attempt(),
        decision: SaleAttemptDecision.manualMoneyReceived,
        actorUserId: 'user-1',
        actorRole: 'OWNER',
        note: 'Cobrado en caja',
      );

      expect(resolved, isTrue);
      expect(order, ['declare:1305.00', 'resolve']);
    });

    test('si la declaración no queda registrada, NO se cierra nada', () async {
      var resolvedCalls = 0;
      final reconciler = SaleAttemptReconciler(
        lookup: (id, expected) async => null,
        listAttempts: ({companyId, userId}) async => const [],
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
              resolvedCalls++;
              return true;
            },
        declareMoneyReceived:
            ({
              required action,
              required totalDeclared,
              actorUserId,
              actorRole,
              note,
            }) async => false,
      );

      final resolved = await reconciler.resolveManually(
        action: _attempt(),
        decision: SaleAttemptDecision.manualMoneyReceived,
        actorRole: 'OWNER',
        note: 'Cobrado en caja',
      );

      expect(resolved, isFalse);
      expect(resolvedCalls, 0);
    });

    test('sin declarador disponible tampoco se resuelve', () async {
      var resolvedCalls = 0;
      final reconciler = SaleAttemptReconciler(
        lookup: (id, expected) async => null,
        listAttempts: ({companyId, userId}) async => const [],
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
              resolvedCalls++;
              return true;
            },
      );

      final resolved = await reconciler.resolveManually(
        action: _attempt(),
        decision: SaleAttemptDecision.manualMoneyReceived,
        actorRole: 'OWNER',
        note: 'Cobrado en caja',
      );

      expect(resolved, isFalse);
      expect(resolvedCalls, 0);
    });

    test('«no se realizó» no crea ninguna obligación', () async {
      var declareCalls = 0;
      final reconciler = SaleAttemptReconciler(
        lookup: (id, expected) async => null,
        listAttempts: ({companyId, userId}) async => const [],
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
            }) async => true,
        declareMoneyReceived:
            ({
              required action,
              required totalDeclared,
              actorUserId,
              actorRole,
              note,
            }) async {
              declareCalls++;
              return true;
            },
      );

      final resolved = await reconciler.resolveManually(
        action: _attempt(),
        decision: SaleAttemptDecision.manualNotPerformed,
        actorRole: 'OWNER',
        note: 'Confirmé con el banco: no hay pago',
      );

      expect(resolved, isTrue);
      expect(declareCalls, 0);
    });
  });
}
