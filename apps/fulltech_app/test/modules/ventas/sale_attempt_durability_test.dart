import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/api/api_offline_cache_interceptor.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_connection_guard.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String previous;
  late SyncQueueService queue;
  final store = OfflineStore.instance;
  setUp(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    previous = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-phase16-attempt-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(UserModel.fromJson({
      'id': 'user-a', 'email': 'fixture@fullpos.test', 'companyId': 'company-a', 'nombreCompleto': 'Fixture',
    }));
    queue = SyncQueueService(store);
  });
  tearDown(() async {
    queue.dispose(); await store.closeForTesting();
    await databaseFactory.setDatabasesPath(previous); await root.delete(recursive: true);
  });
  Future<SaleModel?> charge(VentasRepository repo, String request) => repo.createSale(
    clientRequestId: request, paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
    items: const [SaleDraftItem(productId: 'product-a', name: 'Fixture', imageUrl: null,
      isExternal: false, qty: 4, priceSoldUnit: 100, costUnitSnapshot: 40)]);

  test('explicit Normal retains ordinary offline sale behavior and never creates an electronic request', () async {
    final headers=await ClientTelemetryHeaders.instance.headers();
    final now=DateTime.now().toUtc();
    await OfflineEmergencyPolicy().recordServerValidation(companyId:'company-a',userId:'user-a',
      deviceFingerprint:headers['x-client-device-id']??'',serverUtc:now,observedAtUtc:now);
    final paths=<String>[];
    final dio=Dio()..httpClientAdapter=_Adapter((request) async {
      paths.add(request.path);
      throw DioException(requestOptions:request,type:DioExceptionType.connectionError);
    });
    final repo=VentasRepository(dio,queue,WarehouseRepository(dio),originCashSessionIdResolver:()async=>'turn-a',durableSaleAttemptsForTesting:false);
    final sale=await repo.createSale(clientRequestId:'normal-offline',fiscalVoucherType:'NORMAL',paymentMethod:'cash',
      paymentCashAmount:100,cashReceived:100,expectedTotalSold:100,
      items:const [SaleDraftItem(productId:'product-a',name:'Fixture',imageUrl:null,isExternal:false,qty:1,priceSoldUnit:100,costUnitSnapshot:40)]);
    expect(sale!.isExplicitNormal,isTrue);
    expect(paths.where((path)=>path.contains('/ecf/')||path=='/health'),isEmpty);
    final pending=await store.listPendingActions(companyId:'company-a',userId:'user-a');
    expect(pending.single.payload['fiscalVoucherType'],'NORMAL');
    dio.close(force:true);
  });

  test('a cached healthy response cannot authorize an offline electronic operation', () async {
    var online=true;
    final dio=Dio(BaseOptions(baseUrl:'http://127.0.0.1:3000'));
    dio.interceptors.add(ApiOfflineCacheInterceptor(store:store));
    dio.httpClientAdapter=_Adapter((request) async {
      if(!online) throw DioException(requestOptions:request,type:DioExceptionType.connectionError);
      return ResponseBody.fromString('{"status":"ok"}',200,headers:{Headers.contentTypeHeader:['application/json']});
    });
    await dio.get('/health');
    online=false;
    await expectLater(ensureEcfConnection(dio),throwsA(isA<EcfConnectionException>()));
    dio.close(force:true);
  });

  test('offline electronic returns send and queue nothing; ordinary returns remain visibly pending', () async {
    var posts = 0;
    final dio = Dio()..httpClientAdapter = _Adapter((request) async {
      if(request.method=='POST') posts++;
      throw DioException(requestOptions:request,type:DioExceptionType.connectionError);
    });
    final repo=VentasRepository(dio,queue,WarehouseRepository(dio),originCashSessionIdResolver:()async=>'turn-a');
    await expectLater(repo.returnSale('sale-a',originalSaleCashSessionId:'turn-a',electronic:true),throwsA(isA<EcfConnectionException>()));
    expect(posts,0);
    expect(await store.listPendingActions(companyId:'company-a',userId:'user-a'),isEmpty);
    final ordinary=await repo.returnSale('ordinary-a',originalSaleCashSessionId:'turn-a');
    expect(ordinary.pendingSync,isTrue);
    expect(posts,1);
    final pending=await store.listPendingActions(companyId:'company-a',userId:'user-a');
    expect(pending.single.type,'sales.return');
    dio.close(force:true);
  });

  for (final online in [false, true]) {
    test('electronic sale retains its fiscal intent on an interrupted request: online=$online', () async {
      var posts = 0;
      final dio = Dio()..httpClientAdapter = _Adapter((request) async {
        if (request.path == '/health' && online) {
          return ResponseBody.fromString('{"status":"ok"}', 200, headers: {Headers.contentTypeHeader:['application/json']});
        }
        if (request.path == '/sales') {
          posts++;
          expect(request.data['fiscalVoucherType'], 'E31');
          expect(request.data['sequenceDueDate'], '2028-12-31');
        }
        throw DioException(requestOptions:request, type: DioExceptionType.receiveTimeout);
      });
      final repo = VentasRepository(dio, queue, WarehouseRepository(dio),
        originCashSessionIdResolver: () async=>'turn-a', durableSaleAttemptsForTesting:true);
      Future<SaleModel?> submit(String id)=>repo.createSale(clientRequestId:id,
        paymentMethod:'cash', paymentCashAmount:118, cashReceived:118, expectedTotalSold:118,
        fiscalVoucherType:'E31', sequenceDueDate:'2028-12-31', fiscalCustomerTaxId:'101000001', fiscalCustomerName:'Fixture',
        items:const [SaleDraftItem(productId:'product-a', name:'Fixture',imageUrl:null,isExternal:false,qty:1,priceSoldUnit:100,costUnitSnapshot:40)]);
      await expectLater(submit('electronic-a'),throwsA(isA<EcfConnectionException>().having((e)=>e.uncertain,'uncertain',online)));
      final pending=await store.listPendingActions(companyId:'company-a',userId:'user-a');
      expect(posts,online?1:0);
      expect(await store.listOfflineSales(companyId:'company-a',userId:'user-a'),isEmpty);
      if(online){
        expect(pending.single.type,'sales.attempt');
        expect(pending.single.payload['fiscalVoucherType'],'E31');
        expect(pending.single.payload['sequenceDueDate'],'2028-12-31');
        await expectLater(submit('electronic-b'),throwsA(anything));
        expect(posts,1,reason:'The uncertain financial operation blocks another charge');
      }else{expect(pending,isEmpty);}
      dio.close(force:true);
    });
  }

  for (final mode in ['success', 'timeout', '403', 'scope-change', 'disk-error', 'stock-conflict']) {
    test('Windows release attempt durability: $mode', () async {
      var posts = 0;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) async {
        if (options.path != '/sales') return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: ['application/json']});
        posts++;
        final attempts = await store.listPendingActions(companyId: 'company-a', userId: 'user-a');
        expect(attempts.single.type, 'sales.attempt', reason: 'Intent must be durable before POST');
        expect(attempts.single.idempotencyKey, 'request-a');
        expect(attempts.single.payload['originCashSessionId'], 'turn-a');
        if (mode == 'scope-change') {
          await TokenStorage().saveUserSnapshot(UserModel.fromJson({'id':'user-b','companyId':'company-b','email':'other@fullpos.test'}));
        }
        if (mode == 'timeout' || mode == 'scope-change') {
          throw DioException(requestOptions: options, type: DioExceptionType.receiveTimeout);
        }
        if (mode == '403') return ResponseBody.fromString('{"message":"denied"}', 403, headers: {Headers.contentTypeHeader: ['application/json']});
        if (mode == 'stock-conflict') {
          return ResponseBody.fromString(jsonEncode({
            'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
            'message': 'El stock cambió mientras el dispositivo estaba sin conexión.',
            'details': {'productName': 'Fixture', 'requestedQuantity': 4, 'availableQuantity': 2},
          }), 409, headers: {Headers.contentTypeHeader: ['application/json']});
        }
        return ResponseBody.fromString(jsonEncode({'id':'remote-sale-a','userId':'user-a',
          'totalSold':400,'totalCost':160,'totalProfit':240,'commissionAmount':0,'paymentMethod':'cash','items':[]}), 201,
          headers: {Headers.contentTypeHeader: ['application/json']});
      });
      final repo = VentasRepository(dio, queue, WarehouseRepository(dio),
        originCashSessionIdResolver: () async => 'turn-a', durableSaleAttemptsForTesting: true);
      if (mode == 'disk-error') {
        await store.readCacheEntry('warmup');
        final db = await databaseFactory.openDatabase('${root.path}/fulltech_offline.db');
        await db.execute("CREATE TRIGGER no_attempt BEFORE INSERT ON pending_actions BEGIN SELECT RAISE(ABORT, 'phase16 storage unavailable'); END");
      }
      if (mode == 'success') {
        expect((await charge(repo, 'request-a'))?.id, 'remote-sale-a');
      } else if (mode == 'stock-conflict') {
        await expectLater(charge(repo, 'request-a'), throwsA(isA<ApiException>()
          .having((e) => e.message, 'customer explanation', contains('Cantidad solicitada: 4. Disponible: 2.'))
          .having((e) => e.responseBody, 'original diagnostics', contains('INSUFFICIENT_WAREHOUSE_STOCK'))));
      } else {
        await expectLater(charge(repo, 'request-a'), throwsA(anything));
      }
      final remaining = await store.listPendingActions(companyId:'company-a',userId:'user-a');
      if (mode == 'timeout' || mode == 'scope-change' || mode == 'stock-conflict') {
        expect(remaining.single.type, 'sales.attempt');
        expect(remaining.single.idempotencyKey, 'request-a');
        expect(await store.listOfflineSales(companyId:'company-b',userId:'user-b'), isEmpty);
        await store.closeForTesting();
        if (mode == 'timeout') {
          await expectLater(charge(repo, 'request-b'), throwsA(anything));
          expect(posts, 1, reason: 'Unknown outcome must block an independent second charge');
        }
      } else { expect(remaining, isEmpty); }
      expect(posts, mode == 'disk-error' ? 0 : 1);
      dio.close(force:true);
    });
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => handler(options);
  @override
  void close({bool force=false}) {}
}
