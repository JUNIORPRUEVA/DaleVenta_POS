import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a session change stops sending the previous tenant outbox', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final store = OfflineStore.forTesting('phase11-scope-switch.db');
    await store.clearAll();
    var scope = const OfflineSyncScope(
      companyId: 'company-a',
      userId: 'user-a',
    );
    final now = DateTime.now().toUtc();
    for (var i = 1; i <= 2; i++) {
      await store.putPendingAction(
        PendingSyncAction(
          id: 'scope-action-$i',
          type: 'scope-check',
          scope: 'catalog.company-a',
          companyId: 'company-a',
          userId: 'user-a',
          payload: {'index': i},
          status: 'pending',
          attempts: 0,
          createdAt: now.add(Duration(milliseconds: i)),
          updatedAt: now,
        ),
      );
    }
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    final sent = <int>[];
    queue.registerHandler('scope-check', (payload) async {
      sent.add(payload['index'] as int);
      scope = const OfflineSyncScope(companyId: 'company-b', userId: 'user-b');
    });
    await queue.processPending();
    expect(sent, [1]);
    final remaining = await store.listPendingActions(
      companyId: 'company-a',
      userId: 'user-a',
    );
    expect(remaining.single.id, 'scope-action-2');
    expect(remaining.single.attempts, 0);
    expect(remaining.single.status, 'pending');
    queue.dispose();
    await store.closeForTesting();
  });
}
