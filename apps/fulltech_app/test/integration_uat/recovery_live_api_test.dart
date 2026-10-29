@Tags(['uat'])
library;

import 'dart:io';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_declaration.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integración REAL cliente ↔ servidor (UAT aislado).
///
/// No usa mocks ni de red ni de base: SQLite de verdad en disco y la API NestJS
/// real apuntando a PostgreSQL UAT. Demuestra el ciclo completo del motor y de
/// la conciliación financiera tal como los ejecuta la app.
///
/// Se ejecuta solo si se indica la API:
///   flutter test test/integration_uat/recovery_live_api_test.dart \
///     --dart-define=UAT_API_BASE=http://127.0.0.1:4010
void main() {
  // OJO: no se inicializa `TestWidgetsFlutterBinding` a propósito. Ese binding
  // intercepta todo HttpClient y responde 400 sin abrir socket, así que una
  // prueba contra la API real necesita el entorno Dart puro.
  const apiBase = String.fromEnvironment('UAT_API_BASE');
  final enabled = apiBase.trim().isNotEmpty;

  if (!enabled) {
    test('integración UAT omitida (define UAT_API_BASE)', () {}, skip: true);
    return;
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final api = apiBase.replaceAll(RegExp(r'/+$'), '');
  final run = DateTime.now().microsecondsSinceEpoch.toString();

  late Directory root;
  late String previousPath;
  late Dio dio;
  late String token;
  late String companyId;
  late String userId;
  late String cashSessionId;
  late SyncQueueService queue;

  /// Token vivo para el interceptor (la variable `token` es `late`).
  var authToken = '';

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await dio.post(
      '$api$path',
      data: body,
      options: Options(
        headers: auth ? {'authorization': 'Bearer $token'} : null,
        validateStatus: (_) => true,
      ),
    );
    return {
      'status': res.statusCode,
      'data': res.data is Map
          ? (res.data as Map).cast<String, dynamic>()
          : <String, dynamic>{},
    };
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await dio.get(
      '$api$path',
      options: Options(
        headers: {'authorization': 'Bearer $token'},
        validateStatus: (_) => true,
      ),
    );
    return {
      'status': res.statusCode,
      'data': res.data is List
          ? <String, dynamic>{'items': res.data}
          : res.data is Map
          ? (res.data as Map).cast<String, dynamic>()
          : <String, dynamic>{},
    };
  }

  setUpAll(() async {
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-live-uat-');
    await databaseFactory.setDatabasesPath(root.path);
    await OfflineStore.instance.clearAll();

    dio = Dio(
      BaseOptions(
        // El handler de la cola envía rutas relativas (`/sales/...`), igual que
        // en la app: aquí el baseUrl es la API UAT real.
        baseUrl: api,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    // Igual que el interceptor real de la app: el token viaja en cada envío de
    // la cola. Sin esto el handler de la declaración iría sin autenticar.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (authToken.isNotEmpty) {
            options.headers['authorization'] = 'Bearer $authToken';
          }
          handler.next(options);
        },
      ),
    );

    // Empresa sintética + sesión real.
    final email = 'live.$run@daleventa.local';
    final password = 'Uat-Live-$run!';
    final registered = await post(
      '/auth/register-business',
      {
        'firstName': 'UAT',
        'lastName': 'Live',
        'email': email,
        'phone': '8090000001',
        'password': password,
        'confirmPassword': password,
        'commercialName': 'UAT Live $run',
        'country': 'DO',
        'currency': 'DOP',
      },
      auth: false,
    );
    expect(
      registered['status'],
      anyOf(200, 201),
      reason: 'alta de empresa sintética: ${registered['data']}',
    );
    final login = await post('/auth/login', {
      'identifier': email,
      'password': password,
    }, auth: false);
    final loginData = login['data'] as Map<String, dynamic>;
    token =
        (loginData['accessToken'] ??
                loginData['access_token'] ??
                loginData['token'] ??
                '')
            .toString();
    if (token.isEmpty) {
      fail('No se pudo autenticar en la API UAT: ${login['status']}');
    }
    authToken = token;

    final me = await get('/auth/me');
    final meData = me['data'] as Map<String, dynamic>;
    final user = (meData['user'] ?? meData).cast<String, dynamic>();
    companyId = (user['companyId'] ?? meData['companyId'] ?? '').toString();
    userId = (user['id'] ?? '').toString();
    expect(companyId, isNotEmpty, reason: 'la API debe devolver companyId');

    final opened = await post('/cash/sessions/open', {
      'openingAmount': 0,
      'note': 'UAT integración live',
      'deviceFingerprint': 'live-$run',
    });
    final openedData = opened['data'] as Map<String, dynamic>;
    cashSessionId =
        (openedData['shiftId'] ?? openedData['cashId'] ?? '').toString();
    expect(cashSessionId, isNotEmpty, reason: 'turno de caja abierto');
  });

  tearDownAll(() async {
    await OfflineStore.instance.closeForTesting();
    await databaseFactory.setDatabasesPath(previousPath);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // el temporal se limpia solo
    }
  });

  PendingSyncAction attemptRow(String requestId) {
    final now = DateTime.now().toUtc();
    return PendingSyncAction(
      id: 'sales.attempt:$requestId',
      type: 'sales.attempt',
      scope: 'sales',
      companyId: companyId,
      userId: userId,
      idempotencyKey: requestId,
      entityId: requestId,
      operationFingerprint: 'live-$requestId',
      payload: const {'expectedTotalSold': 50.0, 'paymentMethod': 'cash'},
      status: 'requires_action',
      attempts: 0,
      permanent: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  SaleAttemptReconciler reconciler(Dio client) {
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
        id: '${action.id}#${decision.code}#${DateTime.now().microsecondsSinceEpoch}',
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
        totalSold: result.totalSold,
        actorUserId: actorUserId,
        actorRole: actorRole,
        note: note,
        operationFingerprint: action.operationFingerprint,
        mechanism: SaleAttemptReconciler.mechanism,
      );
    }

    return SaleAttemptReconciler(
      lookup: (clientRequestId, expected) async {
        try {
          final res = await client.get(
            '$api/sales/attempts/$clientRequestId/reconciliation',
            queryParameters: expected == null
                ? null
                : {'expectedTotalSold': expected.toStringAsFixed(2)},
            options: Options(
              headers: {'authorization': 'Bearer $token'},
              validateStatus: (_) => true,
            ),
          );
          if (res.statusCode != 200) return null;
          return res.data is Map
              ? (res.data as Map).cast<String, dynamic>()
              : null;
        } catch (_) {
          return null;
        }
      },
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
      declareMoneyReceived:
          ({
            required action,
            required totalDeclared,
            actorUserId,
            actorRole,
            note,
          }) async {
            final outbox = SaleAttemptDeclarationOutbox(
              enqueueAction: (pending) => queue.enqueue(
                id: pending.id,
                type: pending.type,
                scope: pending.scope,
                payload: pending.payload,
                companyId: pending.companyId,
                userId: pending.userId,
                entityType: pending.entityType,
                entityId: pending.entityId,
                idempotencyKey: pending.idempotencyKey,
                requireDatabase: true,
              ),
              findExisting: (id) async {
                final rows = await OfflineStore.instance.listPendingActions(
                  limit: 200,
                );
                for (final row in rows) {
                  if (row.id == id) return row;
                }
                return null;
              },
            );
            final declaration = await outbox.declare(
              action: action,
              totalDeclared: totalDeclared,
              actorUserId: actorUserId,
              actorRole: actorRole,
              note: note,
            );
            return declaration != null;
          },
    );
  }

  setUp(() async {
    await OfflineStore.instance.clearAll();
    await OfflineStore.instance.clearSaleAttemptAuditForTests();
    SaleAttemptReconciler.resetInFlightForTests();
    queue = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async =>
          OfflineSyncScope(companyId: companyId, userId: userId),
    );
    SaleAttemptDeclarationSyncHandlers(queue, dio).register();
  });

  test('cobro inexistente: la verificación NO cierra el intento', () async {
    final requestId = 'live-unknown-$run';
    await OfflineStore.instance.reserveRemoteSaleAttempt(attemptRow(requestId));

    final result = await reconciler(dio).syncPendingAttempts(
      companyId: companyId,
      userId: userId,
    );
    expect(result.unreachable, 0, reason: 'la API respondió');
    expect(result.confirmed, 0, reason: 'no existe la venta');
    expect(result.inconclusive, 1);

    final stored = await OfflineStore.instance.listUnresolvedSaleAttempts(
      companyId: companyId,
      userId: userId,
    );
    expect(
      stored.where((a) => a.id == 'sales.attempt:$requestId'),
      hasLength(1),
      reason: 'NOT_FOUND nunca resuelve el intento',
    );
  });

  test('cobro confirmado en el servidor: el motor cierra el intento y no '
      'crea nada nuevo', () async {
    final requestId = 'live-confirmed-$run';
    final sale = await post('/sales', {
      'clientRequestId': requestId,
      'note': 'UAT live confirmado',
      'paymentMethod': 'cash',
      'paymentCashAmount': 50,
      'cashReceived': 50,
      'expectedTotalSold': 50,
      'originCashSessionId': cashSessionId,
      'items': [
        {
          'qty': 1,
          'priceSoldUnit': 50,
          'costUnitSnapshot': 30,
          'productName': 'Artículo UAT live',
          'productSource': 'LOCAL',
        },
      ],
    });
    expect(
      sale['status'],
      201,
      reason: 'la venta sintética debe registrarse: ${sale['data']}',
    );

    await OfflineStore.instance.reserveRemoteSaleAttempt(attemptRow(requestId));

    final summary = await reconciler(dio).syncPendingAttempts(
      companyId: companyId,
      userId: userId,
    );
    expect(summary.confirmed, 1);

    final stored = await OfflineStore.instance.listUnresolvedSaleAttempts(
      companyId: companyId,
      userId: userId,
    );
    expect(
      stored.where((a) => a.id == 'sales.attempt:$requestId'),
      isEmpty,
      reason: 'CONFIRMED retira el aviso',
    );

    final audit = await OfflineStore.instance.listSaleAttemptAudit(
      companyId: companyId,
      clientRequestId: requestId,
      limit: 10,
    );
    expect(audit, isNotEmpty);
    expect(audit.first.decision, SaleAttemptDecision.autoConfirmed);

    final sales = await get('/sales?limit=50');
    final rows = (sales['data']?['items'] as List?) ?? const [];
    expect(
      rows.where((row) => row['clientRequestId'] == requestId),
      hasLength(1),
      reason: 'verificar no duplica la venta',
    );
  });

  test('declaración sin red + reintento: la obligación llega a PostgreSQL '
      'una sola vez', () async {
    final requestId = 'live-declared-$run';
    await OfflineStore.instance.reserveRemoteSaleAttempt(attemptRow(requestId));

    final pending = await OfflineStore.instance.listUnresolvedSaleAttempts(
      companyId: companyId,
      userId: userId,
    );
    final action = pending.firstWhere(
      (a) => a.id == 'sales.attempt:$requestId',
    );

    // 1) Sin red: el handler apunta a un puerto muerto → la declaración queda
    //    guardada y NO se cierra la incidencia.
    final deadQueue = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async =>
          OfflineSyncScope(companyId: companyId, userId: userId),
    );
    final deadDio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 2)),
    );
    SaleAttemptDeclarationSyncHandlers(deadQueue, deadDio).register();

    final offlineReconciler = SaleAttemptReconciler(
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
            final outbox = SaleAttemptDeclarationOutbox(
              enqueueAction: (row) => deadQueue.enqueue(
                id: row.id,
                type: row.type,
                scope: row.scope,
                payload: row.payload,
                companyId: row.companyId,
                userId: row.userId,
                entityType: row.entityType,
                entityId: row.entityId,
                idempotencyKey: row.idempotencyKey,
                requireDatabase: true,
              ),
            );
            final declaration = await outbox.declare(
              action: action,
              totalDeclared: totalDeclared,
              actorUserId: actorUserId,
              actorRole: actorRole,
              note: note,
            );
            return declaration != null;
          },
    );

    final declared = await offlineReconciler.resolveManually(
      action: action,
      decision: SaleAttemptDecision.manualMoneyReceived,
      actorUserId: userId,
      actorRole: 'ADMIN',
      note: 'UAT live: cobré en efectivo y no salió ticket',
    );
    expect(declared, isTrue, reason: 'la declaración debe quedar guardada');

    // La API real no conoce todavía esta obligación.
    final before = await get('/sales/reconciliation-obligations?status=PENDING');
    final beforeRows = (before['data']?['items'] as List?) ?? const [];
    expect(
      beforeRows.where((row) => row['clientRequestId'] == requestId),
      isEmpty,
    );

    // La cola intentó enviarla y falló (sin red). Se espera a que termine el
    // intento en curso antes de leer su estado.
    Future<PendingSyncAction?> settledDeclaration() async {
      for (var i = 0; i < 200; i += 1) {
        final rows = await OfflineStore.instance.listPendingActions(
          companyId: companyId,
          userId: userId,
          limit: 200,
        );
        final found = rows
            .where((a) => a.type == SaleAttemptDeclaration.actionType)
            .toList();
        if (found.isEmpty) return null;
        if (found.first.status != 'syncing') return found.first;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('la declaración se quedó en «syncing»');
    }

    SaleAttemptDeclarationSyncHandlers(queue, dio).register();
    final declaration = await settledDeclaration();
    expect(declaration, isNotNull, reason: 'la declaración debe quedar guardada');
    expect(
      declaration!.status,
      anyOf('error', 'pending'),
      reason: 'sin red la declaración queda guardada, no enviada',
    );

    final due = declaration.nextAttemptAt;
    if (due != null) {
      final wait = due.difference(DateTime.now().toUtc());
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait + const Duration(milliseconds: 500));
      }
    }
    await queue.processPending();

    // 3) La obligación existe en PostgreSQL, una sola vez.
    final after = await get('/sales/reconciliation-obligations?status=PENDING');
    final afterRows = (after['data']?['items'] as List?) ?? const [];
    final mine = afterRows
        .where((row) => row['clientRequestId'] == requestId)
        .toList();
    final localRows = await OfflineStore.instance.listPendingActions(
      companyId: companyId,
      userId: userId,
      limit: 200,
    );
    final localState = localRows
        .where((a) => a.type == SaleAttemptDeclaration.actionType)
        .map((a) => '${a.status} err=${a.error} next=${a.nextAttemptAt}')
        .join(' | ');
    expect(
      mine,
      hasLength(1),
      reason: 'una sola obligación, sin duplicados · cola=[$localState] '
          'api=${after['status']}',
    );
    expect((mine.first['totalDeclared'] as num).toDouble(), 50.0);
    expect(mine.first['retryAllowed'], isFalse);
    expect(mine.first['assertsPaymentReceived'], isFalse);

    // 4) Reejecutar la cola no crea una segunda obligación.
    final remaining = await OfflineStore.instance.listPendingActions(
      companyId: companyId,
      userId: userId,
      limit: 200,
    );
    expect(
      remaining.where((a) => a.type == SaleAttemptDeclaration.actionType),
      isEmpty,
      reason: 'la declaración ya se envió y se retiró de la cola',
    );
  });
}
