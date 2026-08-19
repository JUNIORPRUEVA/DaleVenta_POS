import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
  });

  test('does not process Company A queue while scoped as Company B', () async {
    var currentScope = const OfflineSyncScope(
      companyId: 'company-sync-a',
      userId: 'user-sync-a',
    );
    final service = SyncQueueService(
      OfflineStore.instance,
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
    await OfflineStore.instance.putPendingAction(
      _action(
        id: 'sales.create:company-a-sale',
        companyId: 'company-sync-a',
        userId: 'user-sync-a',
        clientRequestId: 'sale-a',
      ),
    );
    await service.processPending();

    final remainingAfterB = await OfflineStore.instance.listPendingActions(
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

    final remainingAfterA = await OfflineStore.instance.listPendingActions(
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
    await OfflineStore.instance.putPendingAction(
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

    final service = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async => scope,
    );
    var processed = 0;
    service.registerHandler('sales.create', (_) async {
      processed += 1;
    });

    await service.processPending();

    final remaining = await OfflineStore.instance.listPendingActions(
      companyId: 'company-stale-worker',
      userId: 'user-stale-worker',
    );

    expect(processed, 1);
    expect(remaining, isEmpty);
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
