// Opt-in child process. The orchestrator terminates only this test process.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/storage/resilient_local_database.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Driver boundary injection is test-only and pinned to sqflite_common 2.5.6.
// ignore: implementation_imports
import 'package:sqflite_common/src/internals.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/mixin/factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['FULLPOS_PHASE16_CHILD'] == 'true';
  test('phase16 child', () async {
    final root = Platform.environment['DALEVENTAS_POS_ROOT']!;
    expect(root.toLowerCase(), startsWith(r'c:\src\fullpos-offline-safe-48h\.uat\phase16-process-bench\'));
    expect(root, isNot(contains('windows-app-root')));
    final fixture = jsonDecode(await File('$root/fixture.json').readAsString()) as Map<String, dynamic>;
    final stage = fixture['stage'] as String;
    final kind = fixture['kind'] as String;
    expect(fixture['nonce'], Platform.environment['FULLPOS_PHASE16_NONCE']);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    final native = createDatabaseFactoryFfi();
    var armed = false;
    Future<void> stop(String boundary) async {
      final marker = File('$root/boundary.json.part');
      await marker.writeAsString(jsonEncode({
        'pid': pid, 'nonce': fixture['nonce'], 'stage': stage, 'kind': kind, 'boundary': boundary,
      }), flush: true);
      await marker.rename('$root/boundary.json');
      await Future<void>.delayed(const Duration(minutes: 3));
      fail('Orchestrator did not terminate the controlled child');
    }
    databaseFactory = buildDatabaseFactory(tag: 'phase16-child', invokeMethod: (method, [arguments]) async {
      final sql = arguments is Map ? (arguments['sql'] ?? '').toString().replaceAll('"', '').toUpperCase() : '';
      if (armed && stage == 'A' && sql.startsWith('BEGIN')) await stop('before BEGIN');
      if (armed && stage == 'F' && sql == 'COMMIT') await stop('before COMMIT');
      final result = await native.internalsInvokeMethod<dynamic>(method, arguments);
      if (armed) {
        if (stage == 'B' && sql.startsWith('BEGIN')) await stop('after BEGIN');
        if (stage == 'C' && sql.contains('INTO OFFLINE_SALES')) await stop('after sale INSERT');
        if (stage == 'D' && sql.contains('INTO OFFLINE_SALE_ITEMS')) await stop('after item INSERT');
        if (stage == 'E' && sql.contains('INTO PENDING_ACTIONS')) await stop('after outbox INSERT');
        if (stage == 'G' && sql == 'COMMIT') await stop('after COMMIT returned');
        if (stage == 'J' && method == 'openDatabase') await stop('reopen: native open returned, before validation');
      }
      return result;
    });
    final store = OfflineStore.instance;
    if (Platform.environment['FULLPOS_PHASE16_RESUME'] == 'true') {
      HttpOverrides.global = null;
      final transport = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46552'));
      final login = await transport.post('/auth/login', data: {
        'email': Platform.environment['UAT_ADMIN_EMAIL'], 'password': Platform.environment['UAT_ADMIN_PASSWORD'],
      });
      final user = UserModel.fromJson(Map<String, dynamic>.from(login.data['user'] as Map));
      expect(user.companyId, fixture['companyId']);
      expect(user.id, fixture['userId']);
      await TokenStorage().saveUserSnapshot(user);
      transport.options.headers['authorization'] = 'Bearer ${login.data['accessToken']}';
      final adapter = _LostAckAdapter(transport);
      final dio = Dio(BaseOptions(baseUrl: transport.options.baseUrl))..httpClientAdapter = adapter;
      final queue = SyncQueueService(store, scopeResolver: () async => OfflineSyncScope(companyId: user.companyId, userId: user.id));
      CatalogRepository(dio, TokenStorage(), queue).registerSyncHandlers();
      VentasRepository(dio, queue, WarehouseRepository(dio)).registerSyncHandlers();
      for (var round = 0; round < 3; round++) {
        for (final pending in await store.listPendingActions(companyId: user.companyId, userId: user.id)) {
          await store.updatePendingAction(pending.copyWith(clearNextAttemptAt: true));
        }
        await queue.processPending();
      }
      expect(await store.listPendingActions(companyId: user.companyId, userId: user.id), isEmpty);
      expect(adapter.lost, 1);
      await File('$root/resumed.json').writeAsString(jsonEncode({'status': 'PASS', 'lostAcknowledgments': adapter.lost}));
      queue.dispose();
      await store.closeForTesting();
      transport.close(force: true);
      dio.close(force: true);
      return;
    }
    await store.readCacheEntry('warmup'); // create real schema before arming
    final db = await databaseFactory.openDatabase('$root/databases/fulltech_offline.db');
    final pragmas = <String, dynamic>{};
    for (final name in ['journal_mode','synchronous','foreign_keys','busy_timeout','locking_mode','wal_autocheckpoint','user_version']) {
      pragmas[name] = (await db.rawQuery('PRAGMA $name')).single.values.single;
    }
    pragmas['sqlite_version'] = (await db.rawQuery('SELECT sqlite_version()')).single.values.single;
    await File('$root/pragmas.json').writeAsString(jsonEncode(pragmas));
    expect(pragmas['journal_mode'], 'wal');
    expect(pragmas['synchronous'], 2);
    expect(pragmas['foreign_keys'], 1);
    if (stage == 'K') {
      await store.closeForTesting();
      final path = '$root/databases/migration.db';
      final old = await native.openDatabase(path, options: OpenDatabaseOptions(version: 1,
        onCreate: (db, version) async { await db.execute('CREATE TABLE original(id TEXT PRIMARY KEY)'); await db.insert('original', {'id': 'preserved'}); }));
      await old.close();
      await openResilientLocalDatabase(fileName: 'migration.db', version: 2,
        onCreate: (db, version) async {}, onUpgrade: (db, before, after) async {
          await db.execute('ALTER TABLE original ADD COLUMN new_column TEXT');
          await db.insert('original', {'id': 'uncommitted'});
          await stop('inside real sqflite migration transaction');
        }, allowInMemoryFallback: false);
      return;
    }
    await store.writeCacheEntry('phase16-product', {'stock': kind == 'sale' ? 20 : 0});
    final now = DateTime.now().toUtc();
    final payload = Map<String, dynamic>.from(fixture['payload'] as Map);
    final action = PendingSyncAction(id: '${fixture['type']}:${fixture['operationId']}',
      type: fixture['type'] as String, scope: 'phase16', companyId: fixture['companyId'] as String,
      userId: fixture['userId'] as String, entityId: fixture['productId'] as String,
      idempotencyKey: fixture['operationId'] as String, payload: payload, status: 'pending',
      attempts: 0, createdAt: now, updatedAt: now);
    armed = !['H','I','J','L'].contains(stage);
    if (kind == 'sale') {
      await store.saveOfflineSaleAtomically(localSaleId: 'local_${fixture['operationId']}',
        companyId: fixture['companyId'] as String, userId: fixture['userId'] as String,
        clientRequestId: fixture['operationId'] as String, salePayload: payload,
        itemPayloads: (payload['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        paymentPayload: {'paymentMethod': 'cash', 'paymentCashAmount': 400}, pendingAction: action, totalSold: 400);
    } else {
      await store.putPendingAction(action, cacheKey: 'phase16-product',
        cachePayload: {'stock': kind == 'stock' ? 20 : 0}, requireDatabase: true);
    }
    if (stage == 'H') await stop('save future completed; before success callback');
    if (stage == 'I') {
      await File('$root/success-callback.json').writeAsString('{"acknowledged":true}', flush: true);
      await stop('after simulated success callback (not POS UI)');
    }
    if (stage == 'J') {
      await store.closeForTesting(); armed = true; await store.readCacheEntry('reopen');
    }
    if (stage == 'L') {
      final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
      await File('$root/checkpoint.json').writeAsString(jsonEncode(checkpoint));
      await stop('after PASSIVE checkpoint returned, not in-flight I/O');
    }
    fail('Requested boundary was not reached');
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 4)));
}

class _LostAckAdapter implements HttpClientAdapter {
  _LostAckAdapter(this.transport);
  final Dio transport;
  int lost = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final response = await transport.request<Object?>(options.path, data: options.data, options: Options(method: options.method));
    if (lost == 0 && (options.method == 'POST' || options.method == 'PATCH')) {
      lost++;
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(jsonEncode(response.data), response.statusCode!, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}
