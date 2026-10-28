import 'package:daleventa_pos/core/config/uat_identity.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async {
  final dir = await getDatabasesPath();
  return p.join(dir, UatIdentity.offlineDatabaseFileName());
}

/// Pruebas contra SQLite REAL (no mocks): reserva por operación, auditoría
/// append-only y resolución atómica.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
    await OfflineStore.instance.clearSaleAttemptAuditForTests();
  });

  const company = 'company-a';
  const user = 'user-a';

  PendingSyncAction attempt({
    required String requestId,
    required String fingerprint,
    String? companyId,
    String? userId,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.utc(2026, 10, 27, 12);
    return PendingSyncAction(
      id: 'sales.attempt:$requestId',
      type: 'sales.attempt',
      scope: 'sales',
      companyId: companyId ?? company,
      userId: userId ?? user,
      idempotencyKey: requestId,
      entityId: requestId,
      operationFingerprint: fingerprint,
      payload: const {'expectedTotalSold': 250.0},
      status: 'requires_action',
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  SaleAttemptAuditEntry auditEntry({
    required String pendingActionId,
    required String requestId,
    SaleAttemptDecision decision = SaleAttemptDecision.autoConfirmed,
    String? companyId,
    DateTime? checkedAt,
  }) {
    final when = checkedAt ?? DateTime.utc(2026, 10, 28, 9);
    return SaleAttemptAuditEntry(
      id: '$pendingActionId#${when.millisecondsSinceEpoch}#${decision.code}',
      pendingActionId: pendingActionId,
      clientRequestId: requestId,
      decision: decision,
      checkedAt: when,
      companyId: companyId ?? company,
      userId: user,
      serverStatus: 'CONFIRMED',
      saleId: 'sale-1',
      totalSold: 250,
      mechanism: 'sale-attempt-reconciliation-v1',
    );
  }

  group('reserva por operación (continuidad del POS)', () {
    test('un incidente antiguo NO bloquea una venta independiente', () async {
      // Incidente del 07/10 con resultado desconocido.
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-viejo',
          fingerprint: 'carrito-viejo',
          createdAt: DateTime.utc(2026, 10, 7, 21, 26),
        ),
      );

      // 28/10: el cajero cobra otra cosa. Debe poder.
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-nuevo',
          fingerprint: 'carrito-nuevo',
          createdAt: DateTime.utc(2026, 10, 28, 10),
        ),
      );

      final unresolved = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(unresolved.map((a) => a.idempotencyKey), containsAll(<String>[
        'req-viejo',
        'req-nuevo',
      ]));
    });

    test('repetir el MISMO clientRequestId sí se bloquea', () async {
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-1', fingerprint: 'carrito-1'),
      );

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-1', fingerprint: 'otro-carrito'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Este mismo cobro ya está pendiente'),
          ),
        ),
      );
    });

    test('repetir el MISMO carrito mientras sigue sin resolver se bloquea',
        () async {
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-1',
          fingerprint: 'carrito-1',
          createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        ),
      );

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-2', fingerprint: 'carrito-1'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('mismo contenido'),
          ),
        ),
      );
    });

    test('tras resolver el incidente, el mismo carrito vuelve a permitirse',
        () async {      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);

      // El encargado declara que no se realizó: cierra con rastro.
      final resolved = await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: auditEntry(
          pendingActionId: action.id,
          requestId: 'req-1',
          decision: SaleAttemptDecision.manualNotPerformed,
        ),
      );
      expect(resolved, isTrue);

      // Ahora sí puede cobrarse ese mismo contenido.
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-3', fingerprint: 'carrito-1'),
      );
      final unresolved = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(unresolved.single.idempotencyKey, 'req-3');
    });

    test('otra empresa con el mismo carrito no se ve afectada', () async {      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-a', fingerprint: 'mismo'),
      );

      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-b',
          fingerprint: 'mismo',
          companyId: 'company-b',
          userId: 'user-b',
        ),
      );

      final companyB = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: 'company-b',
        userId: 'user-b',
      );
      expect(companyB.single.idempotencyKey, 'req-b');
    });
  });

  group('dos ventas legítimas iguales', () {
    test('el mismo carrito de hace días NO se bloquea', () async {
      // Caso real: el cliente compra lo mismo otro día. Un intento antiguo del
      // mismo contenido no puede impedirlo.
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-hace-dias',
          fingerprint: 'carrito-repetido',
          createdAt: DateTime.now().toUtc().subtract(const Duration(days: 21)),
        ),
      );

      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-hoy', fingerprint: 'carrito-repetido'),
      );

      final unresolved = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(
        unresolved.map((a) => a.idempotencyKey),
        containsAll(<String>['req-hace-dias', 'req-hoy']),
      );
    });

    test('el mismo carrito fuera de la ventana de repetición se permite',
        () async {
      final justoFuera = DateTime.now()
          .toUtc()
          .subtract(OfflineStore.sameCartBlockWindow + const Duration(minutes: 1));
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-antes',
          fingerprint: 'carrito-igual',
          createdAt: justoFuera,
        ),
      );

      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-despues', fingerprint: 'carrito-igual'),
      );

      final unresolved = await OfflineStore.instance.countUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(unresolved, 2);
    });

    test('una repetición inmediata del mismo carrito sí se detiene', () async {
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-1',
          fingerprint: 'carrito-igual',
          createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
        ),
      );

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-2', fingerprint: 'carrito-igual'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('venta nueva autorizada con el mismo carrito', () {
    test('sin autorización se bloquea; con autorización entra una sola vez',
        () async {
      final action = attempt(
        requestId: 'req-1',
        fingerprint: 'carrito-igual',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
      );
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-2', fingerprint: 'carrito-igual'),
        ),
        throwsA(isA<StateError>()),
      );

      await OfflineStore.instance.grantSameCartOverride(
        companyId: company,
        operationFingerprint: 'carrito-igual',
        actorUserId: 'owner-1',
        actorRole: 'OWNER',
        note: 'El cliente confirmó que es una compra nueva',
      );

      // Primera venta nueva: pasa y consume la autorización.
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(requestId: 'req-2', fingerprint: 'carrito-igual'),
      );

      // Segunda: ya no hay autorización válida, se vuelve a bloquear.
      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-3', fingerprint: 'carrito-igual'),
        ),
        throwsA(isA<StateError>()),
      );

      // El intento original sigue intacto y sin resolver.
      final unresolved = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(
        unresolved.map((a) => a.idempotencyKey),
        containsAll(<String>['req-1', 'req-2']),
      );
    });

    test('una autorización caducada no habilita nada', () async {
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-1',
          fingerprint: 'carrito-igual',
          createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        ),
      );
      await OfflineStore.instance.grantSameCartOverride(
        companyId: company,
        operationFingerprint: 'carrito-igual',
        actorRole: 'OWNER',
      );
      // Simula el paso del tiempo reescribiendo la concesión. Se abre una
      // conexión INDEPENDIENTE (`singleInstance: false`) para no cerrar la que
      // usa OfflineStore.
      final db = await databaseFactoryFfi.openDatabase(
        await _databasePath(),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.update(
        'sale_cart_override',
        {
          'granted_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        },
      );
      await db.close();

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-2', fingerprint: 'carrito-igual'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('la autorización de otra empresa no sirve', () async {
      await OfflineStore.instance.reserveRemoteSaleAttempt(
        attempt(
          requestId: 'req-1',
          fingerprint: 'carrito-igual',
          createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        ),
      );
      await OfflineStore.instance.grantSameCartOverride(
        companyId: 'company-b',
        operationFingerprint: 'carrito-igual',
        actorRole: 'OWNER',
      );

      await expectLater(
        OfflineStore.instance.reserveRemoteSaleAttempt(
          attempt(requestId: 'req-2', fingerprint: 'carrito-igual'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('auditoría en SQLite real', () {
    test('resolver guarda evidencia y retira el aviso en la misma operación',
        () async {
      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);

      final resolved = await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: auditEntry(pendingActionId: action.id, requestId: 'req-1'),
      );

      expect(resolved, isTrue);
      final pending = await OfflineStore.instance.listPendingActions(
        companyId: company,
        userId: user,
      );
      expect(pending, isEmpty);

      final audit = await OfflineStore.instance.listSaleAttemptAudit(
        companyId: company,
      );
      expect(audit, hasLength(1));
      expect(audit.single.decision, SaleAttemptDecision.autoConfirmed);
      expect(audit.single.saleId, 'sale-1');
      expect(audit.single.mechanism, 'sale-attempt-reconciliation-v1');
    });

    test('el rastro sobrevive aunque el intento ya no exista', () async {
      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);
      await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: auditEntry(pendingActionId: action.id, requestId: 'req-1'),
      );

      final byRequest = await OfflineStore.instance.listSaleAttemptAudit(
        clientRequestId: 'req-1',
      );
      expect(byRequest, hasLength(1));
      expect(byRequest.single.pendingActionId, action.id);
    });

    test('resolver dos veces no duplica evidencia ni rompe nada', () async {
      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);
      final entry = auditEntry(
        pendingActionId: action.id,
        requestId: 'req-1',
      );

      final first = await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: entry,
      );
      final second = await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: entry,
      );

      expect(first, isTrue);
      expect(second, isFalse);
      final audit = await OfflineStore.instance.listSaleAttemptAudit(
        companyId: company,
      );
      expect(audit, hasLength(1));
    });

    test('la auditoría está aislada por empresa', () async {
      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);
      await OfflineStore.instance.resolveSaleAttemptAtomically(
        pendingActionId: action.id,
        entry: auditEntry(pendingActionId: action.id, requestId: 'req-1'),
      );

      final otherCompany = await OfflineStore.instance.listSaleAttemptAudit(
        companyId: 'company-b',
      );
      expect(otherCompany, isEmpty);
    });

    test('inspeccionar no resuelve nada: el intento sigue ahí', () async {
      final action = attempt(requestId: 'req-1', fingerprint: 'carrito-1');
      await OfflineStore.instance.reserveRemoteSaleAttempt(action);

      await OfflineStore.instance.appendSaleAttemptAudit(
        auditEntry(
          pendingActionId: action.id,
          requestId: 'req-1',
          decision: SaleAttemptDecision.keptInconclusive,
        ),
      );

      final count = await OfflineStore.instance.countUnresolvedSaleAttempts(
        companyId: company,
        userId: user,
      );
      expect(count, 1);
      final audit = await OfflineStore.instance.listSaleAttemptAudit(
        companyId: company,
      );
      expect(audit.single.decision, SaleAttemptDecision.keptInconclusive);
    });
  });
}
