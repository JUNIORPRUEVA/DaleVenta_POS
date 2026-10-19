// Native Release child, opt-in and isolated from the real FullPOS identity.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('FULLPOS_PHASE16_NATIVE_PROBE') || !Platform.isWindows) exit(70);
  final root = Platform.environment['DALEVENTAS_POS_ROOT'] ?? '';
  check(root == r'C:\src\fullpos-offline-safe-48h\.uat\phase16-native-bank', 'Unsafe root');
  check((await PackageInfo.fromPlatform()).appName == 'FullPOSPhase16NativeUAT', 'Unsafe native identity');
  check(Platform.environment['APP_ENV'] == 'uat' && Platform.environment['UAT_LOCAL_ONLY'] == 'true', 'Not local UAT');
  final stage = Platform.environment['FULLPOS_PHASE16_STAGE'];
  check(stage == 'prepare' || stage == 'verify', 'Invalid stage');
  try { await probe(root, stage!); exit(0); }
  catch (error, stack) {
    await File('$root/$stage-failure.json').writeAsString(jsonEncode({
      'status':'FAIL','type':error.runtimeType.toString(),
      'message':error is StateError ? error.message : 'Probe failed; inspect scoped UAT environment',
      'stack':stack.toString(),
    })); exit(1);
  }
}

Future<void> probe(String root, String stage) async {
  sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
  final transport = Dio(BaseOptions(baseUrl:'http://127.0.0.1:46552'));
  final storage = TokenStorage();
  late UserModel user;
  if (stage == 'prepare') {
    check(!File('$root/committed.json').existsSync(), 'Refusing to overwrite native evidence');
    final login = await transport.post('/auth/login', data:{'email':Platform.environment['UAT_ADMIN_EMAIL'],'password':Platform.environment['UAT_ADMIN_PASSWORD']});
    user = UserModel.fromJson(Map<String,dynamic>.from(login.data['user'] as Map));
    await storage.saveTokens(login.data['accessToken'] as String, login.data['refreshToken'] as String?);
    await storage.saveUserSnapshot(user);
  } else { user = (await storage.getUserSnapshot())!; }
  transport.options.headers['authorization'] = 'Bearer ${await storage.getAccessToken()}';
  final store = OfflineStore.instance;
  await store.readCacheEntry('warmup');
  final db = await databaseFactory.openDatabase('$root/databases/fulltech_offline.db');
  final version = (await db.rawQuery('SELECT sqlite_version()')).single.values.single.toString();
  check(version == '3.52.0', 'Unexpected native SQLite version');
  final queue = SyncQueueService(store, scopeResolver:() async => OfflineSyncScope(companyId:user.companyId,userId:user.id));
  if (stage == 'prepare') {
    final cash = await transport.get('/cash/state');
    final shiftId = cash.data['activeSession']['shiftId'] as String;
    final name = 'phase16-native-${DateTime.now().microsecondsSinceEpoch}';
    final product = await transport.post('/products', data:{'nombre':name,'codigo':name,'categoria':'UAT phase16','precio':100,'costo':40,'stock':0});
    final productId = product.data['id'] as String;
    await transport.patch('/products/$productId/stock', data:{'delta':20,'reason':name});
    final adapter = _CommitPauseAdapter(transport, (options, response) async {
      final pending = await store.listPendingActions(companyId:user.companyId,userId:user.id);
      check(pending.single.type == 'sales.attempt', 'No durable intent before remote commit');
      check(pending.single.idempotencyKey == (options.data as Map)['clientRequestId'], 'Identity mismatch');
      final partial = File('$root/committed.json.part');
      await partial.writeAsString(jsonEncode({'pid':pid,'companyId':user.companyId,'userId':user.id,
        'productId':productId,'shiftId':shiftId,'requestId':pending.single.idempotencyKey,
        'remoteSaleId':(response.data as Map)['id'],'sqliteVersion':version,
        'boundary':'Remote commit returned to transport; before response reaches VentasRepository'}),flush:true);
      await partial.rename('$root/committed.json');
      await Future<void>.delayed(const Duration(minutes:3));
      throw StateError('Native child was not terminated');
    });
    final dio = Dio(BaseOptions(baseUrl:transport.options.baseUrl))..httpClientAdapter=adapter;
    final repo = VentasRepository(dio,queue,WarehouseRepository(dio),originCashSessionIdResolver:() async=>shiftId);
    await repo.createSale(clientRequestId:name,paymentMethod:'cash',paymentCashAmount:400,cashReceived:400,expectedTotalSold:400,
      items:[SaleDraftItem(productId:productId,name:name,imageUrl:null,isExternal:false,qty:4,priceSoldUnit:100,costUnitSnapshot:40)]);
    throw StateError('Prepare unexpectedly completed');
  }
  final original = jsonDecode(await File('$root/committed.json').readAsString()) as Map;
  final attempts = await store.listPendingActions(companyId:user.companyId,userId:user.id);
  check(attempts.single.type == 'sales.attempt', 'Intent lost across native process termination');
  check(attempts.single.idempotencyKey == original['requestId'], 'Original identity lost');
  final adapter = _CommitPauseAdapter(transport, (options,response) async { throw StateError('Independent charge reached HTTP'); });
  final dio = Dio(BaseOptions(baseUrl:transport.options.baseUrl))..httpClientAdapter=adapter;
  final repo = VentasRepository(dio,queue,WarehouseRepository(dio),originCashSessionIdResolver:() async=>original['shiftId'] as String);
  var blocked = false;
  try {
    await repo.createSale(clientRequestId:'independent-${DateTime.now().microsecondsSinceEpoch}',paymentMethod:'cash',paymentCashAmount:400,cashReceived:400,expectedTotalSold:400,
      items:[SaleDraftItem(productId:original['productId'] as String,name:'Fixture',imageUrl:null,isExternal:false,qty:4,priceSoldUnit:100,costUnitSnapshot:40)]);
  } catch (_) { blocked = true; }
  check(blocked && adapter.posts == 0, 'Unknown outcome did not block another charge before POST');
  // Supervised reconciliation of this disposable fixture only, using the exact
  // stored identity/payload. Never reconstruct or reassign its original turn.
  final replay = await transport.post('/sales',data:attempts.single.payload);
  check(replay.data['id'] == original['remoteSaleId'], 'Replay did not recover original remote sale');
  await store.removePendingAction(attempts.single.id);
  await File('$root/verified.json').writeAsString(jsonEncode({'status':'PASS',
    'originalRequestId':original['requestId'],'remoteSaleId':original['remoteSaleId'],
    'independentChargeBlocked':true,'sqliteVersion':version,
    'scope':'Native Release process kill after remote commit; original fixture reconciled by exact replay'}));
  queue.dispose(); await store.closeForTesting(); transport.close(force:true); dio.close(force:true);
}

class _CommitPauseAdapter implements HttpClientAdapter {
  _CommitPauseAdapter(this.transport,this.onSale);
  final Dio transport;
  final Future<void> Function(RequestOptions,Response<dynamic>) onSale;
  int posts=0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,Stream<Uint8List>? requestStream,Future<void>? cancelFuture) async {
    if(options.method=='POST' && options.path=='/sales') posts++;
    final response=await transport.request<dynamic>(options.path,data:options.data,options:Options(method:options.method));
    if(options.method=='POST' && options.path=='/sales') await onSale(options,response);
    return ResponseBody.fromString(jsonEncode(response.data),response.statusCode!,headers:{Headers.contentTypeHeader:['application/json']});
  }
  @override
  void close({bool force=false}) {}
}
