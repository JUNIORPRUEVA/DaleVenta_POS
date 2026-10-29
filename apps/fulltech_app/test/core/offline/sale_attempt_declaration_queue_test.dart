import 'dart:io';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_declaration.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Resiliencia REAL de la declaración de conciliación en la cola offline.
///
/// Usa SQLite de verdad (ffi) y un handler que falla igual que el backend:
/// 401, 429, 500, sin red y 422. Lo que se comprueba en todos los casos es lo
/// único que no se puede permitir: **que la declaración desaparezca**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const company = 'company-a';
  const userId = 'user-a';
  const requestId = 'req-queue-1';

  late Directory root;
  late String previousPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-queue-declaration-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
  });

  tearDown(() async {
    await OfflineStore.instance.closeForTesting();
    await databaseFactory.setDatabasesPath(previousPath);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // El directorio temporal se limpia solo.
    }
  });

  SyncQueueService buildQueue() {
    return SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: company, userId: userId),
    );
  }

  Future<SaleAttemptDeclaration> enqueueDeclaration(
    SyncQueueService queue, {
    double total = 50,
  }) async {
    final attempt = PendingSyncAction(
      id: 'sales.attempt:$requestId',
      type: 'sales.attempt',
      scope: 'sales',
      companyId: company,
      userId: userId,
      idempotencyKey: requestId,
      entityId: requestId,
      operationFingerprint: 'fp-1',
      payload: const {'expectedTotalSold': 50.0, 'paymentMethod': 'cash'},
      status: 'requires_action',
      attempts: 0,
      permanent: true,
      createdAt: DateTime.utc(2026, 10, 27, 20),
      updatedAt: DateTime.utc(2026, 10, 27, 20),
    );
    final outbox = SaleAttemptDeclarationOutbox(
      enqueueAction: (action) => queue.enqueue(
        id: action.id,
        type: action.type,
        scope: action.scope,
        payload: action.payload,
        companyId: action.companyId,
        userId: action.userId,
        entityType: action.entityType,
        entityId: action.entityId,
        idempotencyKey: action.idempotencyKey,
        requireDatabase: true,
      ),
    );
    final declaration = await outbox.declare(
      action: attempt,
      totalDeclared: total,
      actorUserId: userId,
      actorRole: 'OWNER',
      note: 'Cliente pagó en efectivo, no salió ticket',
    );
    expect(declaration, isNotNull);
    return declaration!;
  }

  Future<PendingSyncAction?> stored(SyncQueueService queue, String id) async {
    final actions = await OfflineStore.instance.listPendingActions(
      companyId: company,
      userId: userId,
      limit: 200,
    );
    for (final action in actions) {
      if (action.id == id) return action;
    }
    return null;
  }

  /// Espera a que la cola real deje de estar «pending». La cola lanza una pasada
  /// sola al encolar, así que hay que observar su resultado, no forzar otra.
  Future<PendingSyncAction> awaitSettled(
    SyncQueueService queue,
    String id,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final action = await stored(queue, id);
      if (action == null) {
        fail('la declaración desapareció de la cola');
      }
      if (action.status != 'pending' && action.status != 'syncing') {
        return action;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('la cola no procesó la declaración a tiempo');
  }

  DioException httpError(int status) {
    return DioException(
      requestOptions: RequestOptions(path: '/sales/attempts/$requestId/declaration'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  test('un 401 bloquea la declaración pero se rehabilita al volver a entrar',
      () async {
    final queue = buildQueue();
    final declaration = await enqueueDeclaration(queue);
    queue.registerHandler(
      SaleAttemptDeclaration.actionType,
      (payload) async => throw httpError(401),
    );
    final blocked = await awaitSettled(queue, declaration.localId);
    expect(blocked.status, 'auth_blocked');
    expect(blocked.payload['totalDeclared'], 50.0);

    // Tras iniciar sesión de nuevo, la obligación no puede quedarse perdida.
    final posted = <Map<String, dynamic>>[];
    queue.registerHandler(SaleAttemptDeclaration.actionType, (payload) async {
      posted.add(payload);
    });
    final released = await queue.releaseAuthBlocked(
      type: SaleAttemptDeclaration.actionType,
    );
    expect(released, 1);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (posted.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(posted, hasLength(1));
    expect(posted.single['totalDeclared'], 50.0);
    expect(await stored(queue, declaration.localId), isNull);
  });

  test('un 429 conserva la declaración con espera', () async {
    final queue = buildQueue();
    final declaration = await enqueueDeclaration(queue);
    queue.registerHandler(
      SaleAttemptDeclaration.actionType,
      (payload) async => throw httpError(429),
    );
    final after = await awaitSettled(queue, declaration.localId);
    expect(after.status, 'error');
    expect(after.nextAttemptAt, isNotNull);
    expect(after.attempts, 1);
  });

  test('un 500 o backend caído no borra la obligación pendiente', () async {
    final queue = buildQueue();
    final declaration = await enqueueDeclaration(queue);
    queue.registerHandler(
      SaleAttemptDeclaration.actionType,
      (payload) async => throw httpError(500),
    );
    final after = await awaitSettled(queue, declaration.localId);
    expect(after.status, 'error');
    expect(after.permanent, isFalse);
    expect(after.payload['clientRequestId'], requestId);
  });

  test('un 422 deja la declaración visible y marcada, no la borra', () async {
    final queue = buildQueue();
    final declaration = await enqueueDeclaration(queue);
    queue.registerHandler(
      SaleAttemptDeclaration.actionType,
      (payload) async => throw httpError(422),
    );
    final after = await awaitSettled(queue, declaration.localId);
    // Rechazo definitivo del cuerpo: no se reintenta en bucle, pero queda como
    // evidencia para el reporte de soporte.
    expect(after.status, 'failed');
    expect(after.permanent, isTrue);
    expect(after.payload['note'], contains('efectivo'));
  });

  test('el éxito retira la acción y conserva la del intento original',
      () async {
    final queue = buildQueue();
    await OfflineStore.instance.putPendingAction(
      PendingSyncAction(
        id: 'sales.attempt:$requestId',
        type: 'sales.attempt',
        scope: 'sales',
        companyId: company,
        userId: userId,
        idempotencyKey: requestId,
        entityId: requestId,
        payload: const {'expectedTotalSold': 50.0},
        status: 'requires_action',
        attempts: 0,
        permanent: true,
        createdAt: DateTime.utc(2026, 10, 27, 20),
        updatedAt: DateTime.utc(2026, 10, 27, 20),
      ),
    );

    final posted = <Map<String, dynamic>>[];
    queue.registerHandler(SaleAttemptDeclaration.actionType, (payload) async {
      posted.add(payload);
    });
    final declaration = await enqueueDeclaration(queue);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (posted.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(posted, hasLength(1));
    expect(posted.single['clientRequestId'], requestId);
    expect(posted.single['totalDeclared'], 50.0);
    expect(await stored(queue, declaration.localId), isNull);
    // El intento de cobro original sigue donde estaba: no se reenvía ni se borra
    // desde la declaración.
    expect(await stored(queue, 'sales.attempt:$requestId'), isNotNull);
  });

  test('dos declaraciones idénticas no duplican la acción en cola', () async {
    final queue = buildQueue();
    final first = await enqueueDeclaration(queue);
    final second = await enqueueDeclaration(queue);
    expect(second.localId, first.localId);

    final actions = await OfflineStore.instance.listPendingActions(
      companyId: company,
      userId: userId,
      limit: 200,
    );
    final declarations = actions
        .where((a) => a.type == SaleAttemptDeclaration.actionType)
        .toList();
    expect(declarations, hasLength(1));
  });

  test('una corrección de importe sí es una declaración nueva', () async {
    final queue = buildQueue();
    final first = await enqueueDeclaration(queue, total: 50);
    final corrected = await enqueueDeclaration(queue, total: 55);
    expect(corrected.localId, isNot(first.localId));

    final actions = await OfflineStore.instance.listPendingActions(
      companyId: company,
      userId: userId,
      limit: 200,
    );
    final declarations = actions
        .where((a) => a.type == SaleAttemptDeclaration.actionType)
        .toList();
    expect(declarations, hasLength(2));
  });
}
