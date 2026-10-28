import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation_providers.dart';
import 'package:daleventa_pos/features/offline/sale_attempt_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recorrido E2E de la UI del Centro de recuperación contra SQLite REAL.
///
/// No usa mocks de la base: escribe el intento, abre la pantalla, pulsa los
/// botones de verdad y comprueba el estado final en disco.
class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage(this.user);

  final UserModel? user;

  @override
  Future<UserModel?> getUserSnapshot() async => user;
}

const _company = 'company-a';
const _userId = 'user-a';
const _requestId = 'req-e2e-1';

UserModel _user() => UserModel(
  id: _userId,
  email: 'owner@fullpos.local',
  nombreCompleto: 'Encargado UAT',
  telefono: '8090000000',
  role: 'ADMIN',
  companyId: _company,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String previousPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-e2e-recovery-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
    await OfflineStore.instance.clearSaleAttemptAuditForTests();
    SaleAttemptReconciler.resetInFlightForTests();
  });

  tearDown(() async {
    // Cerrar la conexión antes de borrar el directorio: si queda abierta, el
    // borrado falla en Windows y el siguiente test hereda la base anterior.
    await OfflineStore.instance.closeForTesting();
    await databaseFactory.setDatabasesPath(previousPath);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // El directorio temporal se limpia solo; nunca debe tumbar la prueba.
    }
  });

  Future<void> seedAttempt() async {
    final now = DateTime.utc(2026, 10, 7, 21, 26);
    await OfflineStore.instance.reserveRemoteSaleAttempt(
      PendingSyncAction(
        id: 'sales.attempt:$_requestId',
        type: 'sales.attempt',
        scope: 'sales',
        companyId: _company,
        userId: _userId,
        idempotencyKey: _requestId,
        entityId: _requestId,
        operationFingerprint: 'huella-e2e',
        payload: const {
          'expectedTotalSold': 1305.0,
          'paymentMethod': 'cash',
          'items': [
            {'productId': 'p-1', 'productName': 'Funda UAT', 'qty': 1, 'priceSoldUnit': 1305.0},
          ],
        },
        status: 'requires_action',
        attempts: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  SaleAttemptReconciler buildReconciler({
    required Map<String, dynamic>? Function(String id) response,
  }) {
    SaleAttemptAuditEntry entry({
      required PendingSyncAction action,
      required String clientRequestId,
      required SaleAttemptReconciliationResult result,
      required SaleAttemptDecision decision,
      String? actorUserId,
      String? actorRole,
      String? note,
    }) {
      return SaleAttemptAuditEntry(
        id: '${action.id}#${decision.code}',
        pendingActionId: action.id,
        clientRequestId: clientRequestId,
        decision: decision,
        checkedAt: DateTime.now().toUtc(),
        companyId: action.companyId,
        userId: action.userId,
        serverStatus: result.status.name.toUpperCase(),
        guidance: result.guidance,
        voided: result.voided,
        saleId: result.saleId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        note: note,
        mechanism: SaleAttemptReconciler.mechanism,
      );
    }

    return SaleAttemptReconciler(
      lookup: (id, expected) async => response(id),
      listAttempts: ({companyId, userId}) =>
          OfflineStore.instance.listUnresolvedSaleAttempts(
            companyId: companyId,
            userId: userId,
          ),
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
            await OfflineStore.instance.appendSaleAttemptAudit(
              entry(
                action: action,
                clientRequestId: clientRequestId,
                result: result,
                decision: decision,
                actorUserId: actorUserId,
                actorRole: actorRole,
                note: note,
              ),
            );
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
          }) => OfflineStore.instance.resolveSaleAttemptAtomically(
            pendingActionId: action.id,
            entry: entry(
              action: action,
              clientRequestId: clientRequestId,
              result: result,
              decision: decision,
              actorUserId: actorUserId,
              actorRole: actorRole,
              note: note,
            ),
          ),
      readAudit: ({companyId, clientRequestId, limit = 50}) =>
          OfflineStore.instance.listSaleAttemptAudit(
            companyId: companyId,
            clientRequestId: clientRequestId,
            limit: limit,
          ),
    );
  }

  Widget app(SaleAttemptReconciler reconciler) {
    return ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage(_user())),
        saleAttemptReconcilerProvider.overrideWithValue(reconciler),
      ],
      child: const MaterialApp(home: SaleAttemptRecoveryScreen()),
    );
  }

  /// Espera E/S real (SQLite) y repinta.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Monta la pantalla DENTRO de `runAsync`: así el `initState` crea sus
  /// futuros en la zona real y SQLite puede terminar (si se monta en la zona
  /// simulada, la carga se queda pendiente para siempre).
  Future<void> mount(
    WidgetTester tester,
    SaleAttemptReconciler reconciler,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app(reconciler));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      // `textContaining`: algunos botones añaden contadores («Historial (1)»).
      await tester.tap(find.textContaining(label).first);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('verificar desde la UI cierra la incidencia y deja auditoría',
      (tester) async {
    await tester.runAsync(seedAttempt);

    final reconciler = buildReconciler(
      response: (id) => {
        'status': 'CONFIRMED',
        'clientRequestId': id,
        'retryAllowed': false,
        'assertsPaymentReceived': false,
        'guidance': 'ALREADY_REGISTERED',
        'voided': false,
        'sale': {'id': 'sale-real-1', 'totalSold': 1305.0},
        'movement': null,
      },
    );

    await mount(tester, reconciler);

    // La incidencia se muestra sin revelar secretos.
    expect(find.text('Cobro sin confirmar'), findsOneWidget);
    expect(find.textContaining('1305.00'), findsWidgets);

    // Los detalles internos están detrás de «Detalles».
    expect(find.text('Identificador'), findsNothing);
    await tapAndSettle(tester, 'Detalles');
    expect(find.text('Identificador'), findsOneWidget);
    expect(find.text(_requestId), findsWidgets);

    // Verificar ahora → consulta de solo lectura → resuelve.
    await tapAndSettle(tester, 'Verificar ahora');
    expect(find.text('Resultado de la verificación'), findsOneWidget);
    expect(find.textContaining('sale-real-1'), findsOneWidget);
    await tapAndSettle(tester, 'Entendido');

    // El aviso desaparece de la pantalla...
    expect(find.text('No hay cobros sin confirmar'), findsOneWidget);

    // ...y en disco: intento retirado + evidencia conservada.
    final pendientes = await tester.runAsync(
      () => OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: _company,
        userId: _userId,
      ),
    );
    expect(pendientes, isEmpty);
    final audit = await tester.runAsync(
      () => OfflineStore.instance.listSaleAttemptAudit(companyId: _company),
    );
    expect(audit, hasLength(1));
    expect(audit!.single.decision, SaleAttemptDecision.autoConfirmed);
    expect(audit.single.saleId, 'sale-real-1');
  });

  testWidgets('un resultado ambiguo conserva la incidencia en pantalla',
      (tester) async {
    await tester.runAsync(seedAttempt);

    final reconciler = buildReconciler(
      response: (id) => {
        'status': 'NOT_FOUND',
        'clientRequestId': id,
        'retryAllowed': false,
        'assertsPaymentReceived': false,
        'guidance': 'NOT_REGISTERED',
        'voided': false,
        'sale': null,
        'movement': null,
      },
    );

    await mount(tester, reconciler);
    await tapAndSettle(tester, 'Verificar ahora');
    expect(find.text('Resultado de la verificación'), findsOneWidget);
    expect(find.textContaining('NO demuestra'), findsOneWidget);
    await tapAndSettle(tester, 'Entendido');

    // Sigue visible: no se descarta un cobro sin evidencia.
    expect(find.text('Cobro sin confirmar'), findsOneWidget);
    final pendientes = await tester.runAsync(
      () => OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: _company,
        userId: _userId,
      ),
    );
    expect(pendientes, hasLength(1));
    final audit = await tester.runAsync(
      () => OfflineStore.instance.listSaleAttemptAudit(companyId: _company),
    );
    expect(audit!.single.decision, SaleAttemptDecision.keptInconclusive);
  });

  testWidgets('el historial sobrevive al reinicio de la aplicación',
      (tester) async {
    await tester.runAsync(seedAttempt);

    final reconciler = buildReconciler(
      response: (id) => {
        'status': 'UNKNOWN',
        'clientRequestId': id,
        'retryAllowed': false,
        'assertsPaymentReceived': false,
        'sale': null,
        'movement': null,
      },
    );

    await mount(tester, reconciler);
    await tapAndSettle(tester, 'Verificar ahora');
    await tapAndSettle(tester, 'Entendido');

    // Simula reinicio: árbol nuevo y estado en memoria nuevo.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    SaleAttemptReconciler.resetInFlightForTests();
    await mount(tester, reconciler);

    expect(find.text('Cobro sin confirmar'), findsOneWidget);
    expect(find.textContaining('Última verificación'), findsOneWidget);

    await tapAndSettle(tester, 'Historial');
    expect(find.textContaining('Sin conclusión: conservada'), findsWidgets);
  });

  testWidgets('el reporte para soporte no expone credenciales', (tester) async {
    await tester.runAsync(seedAttempt);

    final reconciler = buildReconciler(
      response: (id) => {
        'status': 'UNKNOWN',
        'clientRequestId': id,
        'retryAllowed': false,
        'assertsPaymentReceived': false,
        'sale': null,
        'movement': null,
      },
    );

    await mount(tester, reconciler);

    await tapAndSettle(tester, 'Solicitar revisión');
    expect(find.text('Reporte para soporte'), findsOneWidget);
    expect(find.textContaining(_requestId), findsWidgets);
    // Sin credenciales: nada que parezca un JWT ni una clave.
    expect(find.textContaining('eyJ'), findsNothing);
    expect(find.textContaining('Bearer'), findsNothing);
    await tapAndSettle(tester, 'Cerrar');
  });
}
