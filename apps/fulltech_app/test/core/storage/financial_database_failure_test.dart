import 'dart:io';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/storage/resilient_local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String previousPath;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-phase16-failure-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await databaseFactory.setDatabasesPath(previousPath);
    await root.delete(recursive: true);
  });

  test('a corrupted financial database is preserved and never recreated as empty', () async {
    const name = 'phase16-corrupt.db';
    final file = File(p.join(root.path, name));
    final original = List<int>.generate(4096, (i) => i % 251);
    await file.writeAsBytes(original, flush: true);
    Object? failure;
    var created = false;
    try {
      final db = await openResilientLocalDatabase(fileName: name, version: 3,
        allowInMemoryFallback: false,
        onCreate: (db, version) async { created = true; await db.execute('CREATE TABLE empty_replacement(id TEXT)'); });
      await db.close();
    } catch (error) { failure = error; }
    expect(failure, isNotNull, reason: 'Opening corrupt financial data must fail closed');
    expect(created, isFalse);
    expect(await file.readAsBytes(), original);
    expect(Directory(p.join(root.path, 'db_recovery')).existsSync(), isFalse);
  });

  test('Windows neither downgrades a future schema nor hides it in preferences', () async {
    const name = 'phase16-newer.db';
    final path = p.join(root.path, name);
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE preserved(id TEXT PRIMARY KEY)');
    await db.insert('preserved', {'id': 'original-economic-operation'});
    await db.setVersion(99);
    await db.close();
    final store = OfflineStore.forTesting(name);
    try {
      await expectLater(store.listPendingActions(), throwsA(anything));
      expect((await SharedPreferences.getInstance()).containsKey('ft_db_pending_actions'), isFalse);
    } finally { await store.closeForTesting(); }
    final preserved = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(readOnly: true));
    try {
      expect(await preserved.getVersion(), 99);
      expect(await preserved.query('preserved'), [{'id': 'original-economic-operation'}]);
    } finally { await preserved.close(); }
  }, skip: !Platform.isWindows);

  test('remote intent survives restart, blocks a new charge and converts atomically', () async {
    final store = OfflineStore.forTesting('phase16-attempt.db');
    final now = DateTime.now().toUtc();
    PendingSyncAction action(String id, String type) => PendingSyncAction(
      id: id, type: type, scope: 'sales', companyId: 'company-a', userId: 'user-a',
      idempotencyKey: 'request-a', payload: {'clientRequestId': 'request-a', 'originCashSessionId': 'turn-a'},
      status: type == 'sales.attempt' ? 'requires_action' : 'pending',
      attempts: 0, createdAt: now, updatedAt: now);
    await store.reserveRemoteSaleAttempt(action('attempt-a', 'sales.attempt'));
    await store.closeForTesting();
    await expectLater(store.reserveRemoteSaleAttempt(action('attempt-b', 'sales.attempt')), throwsStateError);
    final path = p.join(root.path, 'phase16-attempt.db');
    final db = await databaseFactory.openDatabase(path);
    await db.execute("CREATE TRIGGER block_item BEFORE INSERT ON offline_sale_items BEGIN SELECT RAISE(ABORT, 'phase16 injected item failure'); END");
    Future<void> save() => store.saveOfflineSaleAtomically(
      localSaleId: 'local-a', companyId: 'company-a', userId: 'user-a', clientRequestId: 'request-a',
      salePayload: action('sale-a', 'sales.create').payload,
      itemPayloads: [{'productId': 'product-a', 'qty': 4, 'priceSoldUnit': 100}],
      paymentPayload: {'paymentMethod': 'cash', 'paymentCashAmount': 400},
      pendingAction: action('sale-a', 'sales.create'), totalSold: 400, remoteAttemptId: 'attempt-a');
    await expectLater(save(), throwsA(anything));
    expect((await db.query('offline_sales')), isEmpty);
    expect((await store.listPendingActions(companyId: 'company-a', userId: 'user-a')).single.type, 'sales.attempt');
    await db.execute('DROP TRIGGER block_item');
    await save();
    expect((await store.listPendingActions(companyId: 'company-a', userId: 'user-a')).single.type, 'sales.create');
    expect((await db.query('offline_sales')).single['client_request_id'], 'request-a');
    await store.closeForTesting();
    await db.close();
  });

  for (final kind in ['sale', 'product', 'stock', 'ack']) {
    test('real SQLITE_FULL rolls back $kind without discarding previous operations', () async {
      final name = 'phase16-full-$kind.db';
      final store = OfflineStore.forTesting(name);
      await store.writeCacheEntry('original', {'preserved': true});
      final now = DateTime.now().toUtc();
      PendingSyncAction pending(String type, Map<String, dynamic> payload) => PendingSyncAction(
        id: 'original-$kind', type: type, scope: 'sales', companyId: 'company-a', userId: 'user-a',
        idempotencyKey: 'request-a', payload: payload, status: 'pending', attempts: 0, createdAt: now, updatedAt: now);
      Future<void> sale(String note) => store.saveOfflineSaleAtomically(
        localSaleId: 'local-a', companyId: 'company-a', userId: 'user-a', clientRequestId: 'request-a',
        salePayload: {'clientRequestId': 'request-a', 'note': note},
        itemPayloads: [{'productId': 'product-a', 'qty': 4, 'priceSoldUnit': 100}],
        paymentPayload: {'paymentMethod': 'cash', 'paymentCashAmount': 400},
        pendingAction: pending('sales.create', {'clientRequestId': 'request-a'}), totalSold: 400);
      if (kind == 'ack') await sale('original');
      final db = await databaseFactory.openDatabase(p.join(root.path, name));
      final pages = (await db.rawQuery('PRAGMA page_count')).single.values.single as int;
      await db.rawQuery('PRAGMA max_page_count = $pages'); // per disposable database, not host disk
      final large = 'x' * (1024 * 1024);
      Object? failure;
      try {
        if (kind == 'sale') {
          await sale(large);
        } else if (kind == 'ack') {
          // Force an allocation in the real confirmation transaction; the value
          // is a storage stress fixture, not a valid remote UUID.
          await store.markOfflineSaleSynced(companyId: 'company-a', clientRequestId: 'request-a', serverSaleId: large);
        } else {
          await store.putPendingAction(pending('catalog.products.$kind', {'operationId': 'request-a'}),
            cacheKey: 'large', cachePayload: {'value': large}, requireDatabase: true);
        }
      } catch (error) { failure = error; }
      expect(failure.toString().toLowerCase(), contains('full'));
      expect(await store.readCacheEntry('original'), {'preserved': true});
      expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
      final sales = await db.query('offline_sales');
      final outbox = await db.query('pending_actions');
      expect(sales.length, kind == 'ack' ? 1 : 0);
      expect(outbox.length, kind == 'ack' ? 1 : 0);
      if (kind == 'ack') {
        expect(sales.single['status'], 'pending');
        expect(sales.single['server_id'], isNull);
        expect(outbox.single['idempotency_key'], 'request-a');
      }
      await db.rawQuery('PRAGMA max_page_count = 1073741823');
      await store.closeForTesting();
      await db.close();
    });
  }

  test('actual outbox v1 upgrade makes a consistent backup before preserving legacy rows', () async {
    const name = 'phase16-v1.db';
    final db = await databaseFactory.openDatabase(p.join(root.path, name));
    await db.execute('CREATE TABLE cache_entries(cache_key TEXT PRIMARY KEY,payload TEXT,updated_at INTEGER)');
    await db.execute('CREATE TABLE pending_actions(id TEXT PRIMARY KEY,type TEXT,scope TEXT,payload TEXT,status TEXT,attempts INTEGER,error TEXT,created_at INTEGER,updated_at INTEGER)');
    await db.insert('pending_actions', {'id':'legacy-original','type':'legacy.unknown','scope':'sales',
      'payload':'{"original":true}','status':'pending','attempts':0,'created_at':1,'updated_at':1});
    await db.setVersion(1); await db.close();
    final store = OfflineStore.forTesting(name);
    try {
      final pending = await store.listPendingActions(includeUnscoped:true);
      expect(pending.single.id,'legacy-original');
      expect(pending.single.payload,{'original':true});
      final manifests = Directory(p.join(root.path,'local_migration_backups/offline_outbox')).listSync(recursive:true)
        .whereType<File>().where((f)=>p.basename(f.path)=='manifest.json').toList();
      expect(manifests.length,1);
      final backup = await databaseFactoryFfi.openDatabase(p.join(manifests.single.parent.path,name),
        options:OpenDatabaseOptions(readOnly:true));
      try {
        expect(await backup.getVersion(),1);
        expect((await backup.query('pending_actions')).single['id'],'legacy-original');
      } finally {await backup.close();}
    } finally {await store.closeForTesting();}
  });
}
