import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
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
