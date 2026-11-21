// Review harness only: real recovery widgets, synthetic data, no HTTP.
// This file is never imported by a production entry point.
import 'package:daleventa_pos/core/api/server_connection.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/loading/web_startup_cover.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_declaration.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation_providers.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_recovery_engine.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_recovery_providers.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/theme/app_colors.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/offline/reconciliation_obligations_panel.dart';
import 'package:daleventa_pos/features/offline/recovery_reviews_panel.dart';
import 'package:daleventa_pos/features/offline/sale_attempt_recovery_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RecoveryPreviewCase {
  empty('1. Sin pendientes', 'Estado vacío: no significa que todo el servidor esté sincronizado.'),
  offline('2. Pendientes offline', 'Operaciones guardadas que esperan conexión. No requieren una decisión humana.'),
  uncertain('3. Cobro sin confirmar', 'Primero verifica. Si no se encuentra el registro, aparecen las dos soluciones.'),
  confirmed('4. Registro encontrado', 'Pulsa Verificar ahora: la respuesta ficticia coincide en identidad e importe.'),
  rejected('5. Caja rechazada', 'Comprobar o Eliminar pendiente. El historial y el importe original se conservan.'),
  review('6. Por comprobar', 'Despliega la operación: comprueba su registro o indica que no se realizó. La evidencia se conserva.'),
  money('7. Dinero declarado', 'Una declaración humana pendiente de conciliación no confirma una venta ni un pago.'),
  disconnected('8. Sin respuesta', 'Verificar mantiene la incidencia cuando no hay respuesta. No crea otra venta.'),
  archive('9. Archivo', 'Sin pendientes: Todo en orden. La evidencia finalizada se conserva sin añadir ruido.'),
  cashier('10. Acceso del cajero', 'Acceso reservado al administrador. El cajero no carga las incidencias ni las decisiones.');

  const RecoveryPreviewCase(this.label, this.help);
  final String label;
  final String help;
}

UserModel previewRecoveryUser(RecoveryPreviewCase scenario) => UserModel(
  id: 'preview-owner', companyId: 'preview-company',
  email: 'demo@example.test', nombreCompleto: 'Administrador de demostración',
  telefono: '', role: scenario == RecoveryPreviewCase.cashier ? 'CAJERO' : 'ADMIN',
);

class _Storage extends TokenStorage {
  _Storage(this.user);
  final UserModel user;
  @override
  Future<UserModel?> getUserSnapshot() async => user;
}

class _AuthRepository implements AuthRepository {
  _AuthRepository(this.user);
  final UserModel user;
  @override
  Future<HydratedSession> hydrateSession() async => HydratedSession(hasToken: true, user: user);
  @override
  Future<SessionVerificationResult> verifySession({bool silent = false}) async => SessionVerificationResult.authenticated(user);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Vista previa sin autenticación real.');
}

class _Auth extends AuthController {
  _Auth(super.ref, UserModel user) {
    state = AuthState(initialized: true, isAuthenticated: true, user: user);
  }
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancelFuture) async {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError,
      error: 'Vista previa: las conexiones de red están deshabilitadas.');
  }
  @override
  void close({bool force = false}) {}
}

class _Queue extends SyncQueueService {
  _Queue() : super(OfflineStore.instance);
  @override
  Future<void> processPending() async {
    final rows = await OfflineStore.instance.listPendingActions(limit: null);
    for (final action in rows.where((a) => a.isAutomaticallyRetryable)) {
      await OfflineStore.instance.removePendingAction(action.id);
    }
    await refreshStats();
  }
  @override
  Future<void> refreshStats() async {
    final rows = await OfflineStore.instance.listPendingActions(limit: null);
    state = SyncQueueState(
      pendingCount: rows.where((a) => a.status == 'pending').length,
      errorCount: rows.where((a) => a.status == 'error').length,
      blockedCount: rows.where((a) => a.status == 'failed').length,
      conflictCount: rows.where((a) => a.status == 'requires_action').length,
    );
  }
}

class _Reviews extends RecoveryReviewRepository {
  _Reviews(Dio dio) : super(dio, OfflineStore.instance);
  final rows = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> list() async => rows.map((row) => Map<String, dynamic>.from(row)).toList();
  @override
  Future<void> submit(PendingSyncAction action) async {
    rows.add({
      'id': 'preview-review', 'actionType': action.type,
      'operationId': action.idempotencyKey, 'companyId': 'preview-company',
      'sourceUserId': 'preview-owner', 'sourceActionId': action.id,
      'status': 'OPEN', 'expectedAmount': 7, 'needsIntervention': true, 'version': 1,
    });
    await OfflineStore.instance.updatePendingAction(action.copyWith(status: 'requires_action',
      payload: {...action.payload, 'recoveryReviewId': 'preview-review', 'recoveryReviewStatus': 'OPEN'}));
  }
  @override
  Future<Map<String, dynamic>> prepare(PendingSyncAction action) async {
    if (rows.isEmpty) await submit(action);
    return rows.first;
  }
  @override
  Future<void> verify(String id) async {
    // This synthetic case has no matching financial record: remain OPEN.
  }
  @override
  Future<void> decide(Map<String, dynamic> row, String decision, String note) async {
    final current = rows.singleWhere((item) => item['id'] == row['id']);
    current['status'] = decision == 'NOT_PERFORMED' ? 'RESOLVED_NOT_PERFORMED' : 'REVIEWING';
    current['needsIntervention'] = decision != 'NOT_PERFORMED';
    current['version'] = (current['version'] as int) + 1;
  }
}

PendingSyncAction previewRecoveryAction(String id, String type, String status, {
  Map<String, dynamic>? payload, String? error,
}) => PendingSyncAction(
  id: id, type: type, scope: 'sales', companyId: 'preview-company', userId: 'preview-owner',
  idempotencyKey: id, entityId: id, operationFingerprint: 'preview-cart',
  status: status, permanent: status == 'failed', error: error, attempts: 0,
  createdAt: DateTime.utc(2026, 11, 20, 14), updatedAt: DateTime.utc(2026, 11, 20, 14),
  payload: payload ?? const {'expectedTotalSold': 1305.0, 'paymentMethod': 'cash',
    'items': [{'productName': 'Artículo de demostración', 'qty': 1, 'priceSoldUnit': 1305.0}]},
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) throw UnsupportedError('Ejecuta esta galería con Flutter Web; nunca usa una base de datos nativa.');
  dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
  // In-memory preferences: never read or clear a real customer profile.
  SharedPreferences.setMockInitialValues({});
  runApp(const RecoveryDesignPreview());
}

class RecoveryDesignPreview extends StatefulWidget {
  const RecoveryDesignPreview({super.key});
  @override
  State<RecoveryDesignPreview> createState() => _RecoveryDesignPreviewState();
}

class _RecoveryDesignPreviewState extends State<RecoveryDesignPreview> {
  RecoveryPreviewCase scenario = RecoveryPreviewCase.uncertain;
  double? width;
  ProviderContainer? container;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => completeWebStartup());
  }

  Future<void> _load() async {
    final generation = ++revision;
    final old = container;
    setState(() => container = null);
    // Removing the mounted screen before replacing its synthetic providers
    // avoids disposing a container while widgets are still subscribed.
    await WidgetsBinding.instance.endOfFrame;
    old?.dispose();
    // All rows exist only in the mock preferences created by main().
    for (final row in await OfflineStore.instance.listPendingActions(limit: null)) {
      await OfflineStore.instance.removePendingAction(row.id);
    }
    await OfflineStore.instance.clearSaleAttemptAuditForTests();
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'))..httpClientAdapter = _NoNetwork();
    final reviews = _Reviews(dio);
    final audit = <SaleAttemptAuditEntry>[];
    final obligations = <ReconciliationObligation>[];
    final user = previewRecoveryUser(scenario);
    final sale = previewRecoveryAction('preview-sale', 'sales.attempt', 'requires_action');
    final movement = previewRecoveryAction('preview-movement', 'cash.movement', 'failed',
      payload: const {'amount': 7, 'operationId': 'preview-movement', 'sessionId': 'preview-shift', 'type': 'IN'},
      error: 'El turno original está cerrado. Revisa este movimiento.');
    final actions = <PendingSyncAction>[];
    switch (scenario) {
      case RecoveryPreviewCase.empty: break;
      case RecoveryPreviewCase.offline:
        actions.add(previewRecoveryAction('preview-offline', 'sales.create', 'pending'));
      case RecoveryPreviewCase.uncertain || RecoveryPreviewCase.confirmed || RecoveryPreviewCase.disconnected || RecoveryPreviewCase.cashier:
        actions.add(sale);
      case RecoveryPreviewCase.rejected:
        actions.add(movement);
      case RecoveryPreviewCase.review:
        await OfflineStore.instance.putPendingAction(movement);
        await reviews.submit(movement);
      case RecoveryPreviewCase.money:
        obligations.add(ReconciliationObligation(id: 'preview-obligation', clientRequestId: 'preview-sale',
          totalDeclared: 1305, currency: 'DOP', status: 'PENDING', declaredAtUtc: DateTime.utc(2026, 11, 20, 14),
          note: 'Declaración ficticia para revisar la pantalla.'));
      case RecoveryPreviewCase.archive:
        actions.add(movement.copyWith(status: 'review_resolved', payload: {
          ...movement.payload, 'recoveryReviewId': 'preview-review', 'recoveryReviewStatus': 'RESOLVED_REGISTERED'}));
        reviews.rows.add({'id': 'preview-review', 'actionType': 'cash.movement', 'operationId': movement.id,
          'status': 'RESOLVED_REGISTERED', 'expectedAmount': 7, 'needsIntervention': false});
    }
    for (final action in actions) {
      await OfflineStore.instance.putPendingAction(action);
    }
    final reconciler = SaleAttemptReconciler(
      lookup: (id, amount) async => scenario == RecoveryPreviewCase.disconnected ? null : {
        'status': scenario == RecoveryPreviewCase.confirmed ? 'CONFIRMED' : 'NOT_FOUND',
        'clientRequestId': id, 'matchesExpected': scenario == RecoveryPreviewCase.confirmed,
        'retryAllowed': false, 'assertsPaymentReceived': false,
        'guidance': scenario == RecoveryPreviewCase.confirmed ? 'ALREADY_REGISTERED' : 'NOT_REGISTERED',
        if (scenario == RecoveryPreviewCase.confirmed) 'sale': {'id': 'preview-registered-sale', 'totalSold': amount},
      },
      listAttempts: ({companyId, userId}) => OfflineStore.instance.listUnresolvedSaleAttempts(companyId: companyId, userId: userId),
      recordEvidence: ({required action, required clientRequestId, required result, required decision, actorUserId, actorRole, note}) async {
        audit.add(SaleAttemptAuditEntry(id: 'preview-event-${audit.length}', pendingActionId: action.id,
          clientRequestId: clientRequestId, decision: decision, checkedAt: DateTime.now().toUtc(),
          serverStatus: result.status.name, note: note));
      },
      resolveAttempt: ({required action, required clientRequestId, required result, required decision, actorUserId, actorRole, note}) async {
        await OfflineStore.instance.updatePendingAction(action.copyWith(status: 'review_resolved'));
        return true;
      },
      readAudit: ({companyId, clientRequestId, limit = 50}) async => audit,
      declareMoneyReceived: ({required action, required totalDeclared, actorUserId, actorRole, note}) async {
        await OfflineStore.instance.putPendingAction(previewRecoveryAction('preview-declaration', SaleAttemptDeclaration.actionType, 'pending',
          payload: {'totalDeclared': totalDeclared, 'clientRequestId': 'preview-sale', 'note': note}));
        return true;
      },
    );
    final next = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      tokenStorageProvider.overrideWithValue(_Storage(user)),
      authRepositoryProvider.overrideWithValue(_AuthRepository(user)),
      authStateProvider.overrideWith((ref) => _Auth(ref, user)),
      syncQueueServiceProvider.overrideWith((ref) => _Queue()),
      serverConnectionProvider.overrideWith((ref) => scenario == RecoveryPreviewCase.offline || scenario == RecoveryPreviewCase.disconnected
        ? ServerConnection.unreachable : ServerConnection.reachable),
      recoveryEngineStateProvider.overrideWith((ref) => Stream.value(const RecoveryEngineState())),
      recoveryReviewRepositoryProvider.overrideWithValue(reviews),
      recoveryReviewsProvider.overrideWith((ref) => reviews.list()),
      reconciliationObligationsProvider.overrideWith((ref, company) async => obligations),
      reconciliationResolutionProvider.overrideWith((ref) => (obligation, decision, note) async {
        if (decision == 'CHECK') throw ApiException('No hay una venta coincidente. La declaración sigue pendiente.');
        obligations.removeWhere((row) => row.id == obligation.id);
      }),
      saleAttemptReconcilerProvider.overrideWithValue(reconciler),
    ]);
    if (!mounted || generation != revision) { next.dispose(); return; }
    setState(() => container = next);
  }

  @override
  void dispose() { container?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, theme: AppTheme.light,
    home: Scaffold(backgroundColor: AppColors.background,
      body: SafeArea(child: Column(children: [
        Container(color: Colors.white, padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Centro de recuperación · vista previa', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Interfaz en revisión · datos ficticios · sin conexión a API', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<RecoveryPreviewCase>(value: scenario,
                items: [for (final value in RecoveryPreviewCase.values) DropdownMenuItem(value: value, child: Text(value.label))],
                onChanged: container == null ? null : (value) { scenario = value!; _load(); }),
              DropdownButton<double>(value: width ?? 0,
                items: const [DropdownMenuItem(value: 0, child: Text('Adaptable')), DropdownMenuItem(value: 390, child: Text('Móvil · 390')), DropdownMenuItem(value: 1280, child: Text('Escritorio · 1280'))],
                onChanged: (value) => setState(() => width = value == 0 ? null : value)),
              TextButton(onPressed: container == null ? null : _load, child: const Text('Reiniciar ejemplo')),
            ]),
            Text(scenario.help, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ])),
        Expanded(child: container == null ? const Center(child: CircularProgressIndicator()) : Center(
          child: SizedBox(width: width, child: UncontrolledProviderScope(container: container!, child: MaterialApp(
            key: ValueKey(revision), debugShowCheckedModeBanner: false, theme: AppTheme.light,
            home: const SaleAttemptRecoveryScreen(),
          ))),
        )),
      ])),
    ),
  );
}
