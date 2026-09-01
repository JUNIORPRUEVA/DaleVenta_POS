import 'dart:async';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    databaseCounter += 1;
    store = OfflineStore.forTesting(
      'sync_queue_service_test_$databaseCounter.db',
    );
    await store.clearAll();
  });

  tearDown(() async {
    await store.closeForTesting();
  });

  test('does not process Company A queue while scoped as Company B', () async {
    var currentScope = const OfflineSyncScope(
      companyId: 'company-sync-a',
      userId: 'user-sync-a',
    );
    final service = SyncQueueService(
      store,
      scopeResolver: () async => currentScope,
    );
    var processed = 0;
    service.registerHandler('sales.create', (_) async {
      processed += 1;
    });

    currentScope = const OfflineSyncScope(
      companyId: 'company-sync-b',
      userId: 'user-sync-b',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:company-a-sale',
        companyId: 'company-sync-a',
        userId: 'user-sync-a',
        clientRequestId: 'sale-a',
      ),
    );
    await service.processPending();

    final remainingAfterB = await store.listPendingActions(
      companyId: 'company-sync-a',
      userId: 'user-sync-a',
    );

    expect(processed, 0);
    expect(
      remainingAfterB.where(
        (action) => action.id == 'sales.create:company-a-sale',
      ),
      hasLength(1),
    );

    currentScope = const OfflineSyncScope(
      companyId: 'company-sync-a',
      userId: 'user-sync-a',
    );
    await service.processPending();

    final remainingAfterA = await store.listPendingActions(
      companyId: 'company-sync-a',
      userId: 'user-sync-a',
    );

    expect(processed, 1);
    expect(
      remainingAfterA.where(
        (action) => action.id == 'sales.create:company-a-sale',
      ),
      isEmpty,
    );

    service.dispose();
  });

  test('recovers stale syncing action during processing', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-stale-worker',
      userId: 'user-stale-worker',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:stale-worker',
        companyId: 'company-stale-worker',
        userId: 'user-stale-worker',
        clientRequestId: 'sale-stale-worker',
      ).copyWith(
        status: 'syncing',
        attempts: 1,
        lastAttemptAt: DateTime.now().toUtc().subtract(
          SyncQueueService.staleSyncingAge + const Duration(minutes: 1),
        ),
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    var processed = 0;
    service.registerHandler('sales.create', (_) async {
      processed += 1;
    });

    await service.processPending();

    final remaining = await store.listPendingActions(
      companyId: 'company-stale-worker',
      userId: 'user-stale-worker',
    );

    expect(processed, 1);
    expect(remaining, isEmpty);
    service.dispose();
  });

  test('start automatically processes pending actions', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-startup-sync',
      userId: 'user-startup-sync',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:startup',
        companyId: 'company-startup-sync',
        userId: 'user-startup-sync',
        clientRequestId: 'sale-startup',
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    var processed = 0;
    service.registerHandler('sales.create', (_) async {
      processed += 1;
    });

    service.start();
    await _waitFor(() async => processed == 1);

    final remaining = await store.listPendingActions(
      companyId: 'company-startup-sync',
      userId: 'user-startup-sync',
    );
    expect(remaining, isEmpty);
    expect(service.state.lastSyncedAt, isNotNull);
    service.dispose();
  });

  test('retryable failure preserves action and schedules backoff', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-retry',
      userId: 'user-retry',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:retryable',
        companyId: 'company-retry',
        userId: 'user-retry',
        clientRequestId: 'sale-retryable',
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    service.registerHandler('sales.create', (_) async {
      throw DioException(requestOptions: RequestOptions(path: '/sales'));
    });

    await service.processPending();

    final actions = await store.listPendingActions(
      companyId: 'company-retry',
      userId: 'user-retry',
    );
    expect(actions, hasLength(1));
    expect(actions.single.status, 'error');
    expect(actions.single.nextAttemptAt, isNotNull);
    expect(actions.single.permanent, isFalse);
    expect(service.state.lastError, isNotNull);
    service.dispose();
  });

  test('successful retry clears active error and updates last sync', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-clear-error',
      userId: 'user-clear-error',
    );
    final action = _action(
      id: 'sales.create:clear-error',
      companyId: 'company-clear-error',
      userId: 'user-clear-error',
      clientRequestId: 'sale-clear-error',
    );
    await store.putPendingAction(action);

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    var shouldFail = true;
    service.registerHandler('sales.create', (_) async {
      if (shouldFail) {
        throw DioException(requestOptions: RequestOptions(path: '/sales'));
      }
    });

    await service.processPending();
    expect(service.state.lastError, isNotNull);

    final failed = (await store.listPendingActions(
      companyId: 'company-clear-error',
      userId: 'user-clear-error',
    )).single;
    await store.updatePendingAction(
      failed.copyWith(
        status: 'pending',
        clearError: true,
        clearNextAttemptAt: true,
      ),
    );
    shouldFail = false;

    await service.processPending();

    expect(service.state.lastError, isNull);
    expect(service.state.lastErrorAt, isNull);
    expect(service.state.lastSyncedAt, isNotNull);
    expect(
      await store.listPendingActions(
        companyId: 'company-clear-error',
        userId: 'user-clear-error',
      ),
      isEmpty,
    );
    service.dispose();
  });

  test('last successful sync survives service restart', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-last-sync',
      userId: 'user-last-sync',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:last-sync',
        companyId: 'company-last-sync',
        userId: 'user-last-sync',
        clientRequestId: 'sale-last-sync',
      ),
    );

    final first = SyncQueueService(store, scopeResolver: () async => scope);
    first.registerHandler('sales.create', (_) async {});
    await first.processPending();
    final syncedAt = first.state.lastSyncedAt;
    expect(syncedAt, isNotNull);
    first.dispose();

    final second = SyncQueueService(store, scopeResolver: () async => scope);
    second.start();
    await _waitFor(() async => second.state.lastSyncedAt != null);

    expect(second.state.lastSyncedAt, syncedAt);
    second.dispose();
  });

  test('manual and automatic triggers share one worker', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-concurrent',
      userId: 'user-concurrent',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:concurrent',
        companyId: 'company-concurrent',
        userId: 'user-concurrent',
        clientRequestId: 'sale-concurrent',
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    final completer = Completer<void>();
    var attempts = 0;
    service.registerHandler('sales.create', (_) async {
      attempts += 1;
      await completer.future;
    });

    final first = service.processPending();
    final second = service.processPending();
    await _waitFor(() async => attempts == 1);
    completer.complete();
    await Future.wait([first, second]);

    expect(attempts, 1);
    service.dispose();
  });

  test('marks HTTP 409 as permanent conflict and does not retry', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-conflict',
      userId: 'user-conflict',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:stock-conflict',
        companyId: 'company-conflict',
        userId: 'user-conflict',
        clientRequestId: 'sale-conflict',
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    var attempts = 0;
    service.registerHandler('sales.create', (_) async {
      attempts += 1;
      final requestOptions = RequestOptions(path: '/sales');
      throw DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 409,
          data: const {
            'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
            'message': 'Stock insuficiente',
          },
        ),
      );
    });

    await service.processPending();
    await service.processPending();

    final actions = await store.listPendingActions(
      companyId: 'company-conflict',
      userId: 'user-conflict',
    );
    expect(attempts, 1);
    expect(actions, hasLength(1));
    expect(actions.single.status, 'conflict');
    expect(actions.single.permanent, isTrue);
    expect(actions.single.nextAttemptAt, isNull);
    service.dispose();
  });

  test('marks HTTP 401 as auth blocked and does not retry', () async {
    const scope = OfflineSyncScope(
      companyId: 'company-auth',
      userId: 'user-auth',
    );
    await store.putPendingAction(
      _action(
        id: 'sales.create:auth',
        companyId: 'company-auth',
        userId: 'user-auth',
        clientRequestId: 'sale-auth',
      ),
    );

    final service = SyncQueueService(store, scopeResolver: () async => scope);
    var attempts = 0;
    service.registerHandler('sales.create', (_) async {
      attempts += 1;
      final requestOptions = RequestOptions(path: '/sales');
      throw DioException(
        requestOptions: requestOptions,
        response: Response(requestOptions: requestOptions, statusCode: 401),
      );
    });

    await service.processPending();
    await service.processPending();

    final actions = await store.listPendingActions(
      companyId: 'company-auth',
      userId: 'user-auth',
    );
    expect(attempts, 1);
    expect(actions.single.status, 'auth_blocked');
    expect(actions.single.permanent, isTrue);
    service.dispose();
  });
}

PendingSyncAction _action({
  required String id,
  required String companyId,
  required String userId,
  required String clientRequestId,
}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return PendingSyncAction(
    id: id,
    type: 'sales.create',
    scope: 'sales',
    companyId: companyId,
    userId: userId,
    entityType: 'sale',
    entityId: id,
    idempotencyKey: clientRequestId,
    payload: {'clientRequestId': clientRequestId},
    status: 'pending',
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _waitFor(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition');
}
