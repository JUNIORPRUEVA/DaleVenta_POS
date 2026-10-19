import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '48h grant + SQLite reopen + wholesale replay reaches real isolated API once',
    () async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final previousPath = await getDatabasesPath();
      final root = await Directory.systemTemp.createTemp(
        'fullpos-combined144-',
      );
      await databaseFactory.setDatabasesPath(root.path);
      final store = OfflineStore.instance;
      await store.closeForTesting();
      SyncQueueService? queue;
      final headers = await ClientTelemetryHeaders.instance.headers();
      final transport = Dio(
        BaseOptions(baseUrl: 'http://127.0.0.1:46554', headers: headers),
      );
      try {
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final password = 'Uat-$stamp-Aa1!';
        final login =
            (await transport.post(
                  '/auth/register-business',
                  data: {
                    'firstName': 'HTTP',
                    'lastName': 'UAT',
                    'email': 'combined-$stamp@example.test',
                    'phone': '8095550000',
                    'password': password,
                    'confirmPassword': password,
                    'commercialName': 'Combined UAT $stamp',
                    'taxId': '232323232',
                    'businessPhone': '8095551111',
                    'address': 'Disposable local UAT',
                    'country': 'DO',
                  },
                )).data
                as Map;
        final user = UserModel.fromJson(
          Map<String, dynamic>.from(login['user'] as Map),
        );
        await TokenStorage().saveUserSnapshot(user);
        transport.options.headers['authorization'] =
            'Bearer ${login['accessToken']}';
        final grant =
            (await transport.post(
                  '/auth/offline-emergency/authorize',
                  data: {},
                )).data
                as Map;
        await OfflineEmergencyPolicy().recordAuthorizationResponse(
          data: Map<String, dynamic>.from(grant),
          companyId: user.companyId!,
          userId: user.id,
          deviceFingerprint: headers['x-client-device-id']!,
        );
        expect(grant['maxOfflineHours'], 48);
        final cash =
            (await transport.post(
                  '/cash/sessions/open',
                  data: {'openingAmount': 0},
                )).data
                as Map;
        final shift = cash['shiftId'] as String;
        final product =
            (await transport.post(
                  '/products',
                  data: {
                    'nombre': 'Combined $stamp',
                    'codigo': 'combined-$stamp',
                    'categoria': 'UAT',
                    'precio': 100,
                    'costo': 40,
                    'stock': 30,
                  },
                )).data
                as Map;
        await transport.patch(
          '/settings',
          data: {'wholesalePriceListsEnabled': true},
        );
        final list =
            (await transport.post(
                  '/price-lists',
                  data: {'name': 'Combined mayorista $stamp'},
                )).data
                as Map;
        await transport.post(
          '/price-lists/${list['id']}/rules',
          data: {
            'productId': product['id'],
            'mode': 'FIXED_PRICE',
            'fixedPrice': 80,
            'minQuantity': 1,
            'tiers': [
              {'minQuantity': 10, 'mode': 'FIXED_PRICE', 'fixedPrice': 70},
            ],
          },
        );
        queue = SyncQueueService(
          store,
          scopeResolver: () async =>
              OfflineSyncScope(companyId: user.companyId, userId: user.id),
        );
        final adapter = _InterruptedConnection(transport);
        final dio = Dio(BaseOptions(baseUrl: transport.options.baseUrl))
          ..httpClientAdapter = adapter;
        final repository = VentasRepository(
          dio,
          queue,
          WarehouseRepository(dio),
          originCashSessionIdResolver: () async => shift,
          durableSaleAttemptsForTesting: true,
        );
        repository.registerSyncHandlers();
        final requestId = 'combined-$stamp';
        final sale = await repository.createSale(
          clientRequestId: requestId,
          priceListId: list['id'] as String,
          priceListManualOverride: true,
          paymentMethod: 'cash',
          paymentCashAmount: 1050,
          cashReceived: 1050,
          expectedTotalSold: 1050,
          items: [
            SaleDraftItem(
              productId: product['id'] as String,
              name: 'Combined',
              imageUrl: null,
              isExternal: false,
              qty: 15,
              priceSoldUnit: 70,
              costUnitSnapshot: 40,
            ),
          ],
        );
        expect(sale!.id, startsWith('local_'));
        final pending = (await store.listPendingActions(
          companyId: user.companyId,
          userId: user.id,
        )).single;
        expect(pending.payload['priceListId'], list['id']);
        expect(pending.payload['priceListManualOverride'], true);
        expect(pending.payload['originCashSessionId'], shift);
        expect(pending.idempotencyKey, requestId);
        await store.closeForTesting();
        expect(
          (await store.listPendingActions(
            companyId: user.companyId,
            userId: user.id,
          )).single.id,
          pending.id,
        );
        adapter.offline = false;
        await queue.processPending();
        expect(
          await store.listPendingActions(
            companyId: user.companyId,
            userId: user.id,
          ),
          isEmpty,
        );
        expect(adapter.sentSales.single['priceListId'], list['id']);
        expect(adapter.sentSales.single['priceListManualOverride'], true);
        final replay =
            (await transport.post(
                  '/sales',
                  data: adapter.sentSales.single,
                )).data
                as Map;
        expect(replay['priceListId'], list['id']);
        expect(double.parse(replay['totalSold'].toString()), 1050);
        final current =
            (await transport.get('/products/${product['id']}')).data as Map;
        expect(double.parse(current['stock'].toString()), 15);
        final native = await databaseFactory.openDatabase(
          '${root.path}/fulltech_offline.db',
        );
        expect(
          (await native.rawQuery(
            'select sqlite_version()',
          )).single.values.single,
          '3.53.1',
        );
      } finally {
        queue?.dispose();
        transport.close(force: true);
        await store.closeForTesting();
        await databaseFactory.setDatabasesPath(previousPath);
        await root.delete(recursive: true);
        HttpOverrides.global = previousHttp;
      }
    },
    skip: Platform.environment['FULLPOS_COMBINED_HTTP_UAT'] != 'true'
        ? 'Opt-in requires the dedicated disposable API on 127.0.0.1:46554.'
        : false,
  );
}

class _InterruptedConnection implements HttpClientAdapter {
  _InterruptedConnection(this.transport);
  final Dio transport;
  bool offline = true;
  final sentSales = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (offline)
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    if (options.path == '/sales')
      sentSales.add(Map<String, dynamic>.from(options.data as Map));
    final result = await transport.request<dynamic>(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      options: Options(method: options.method),
    );
    return ResponseBody.fromString(
      jsonEncode(result.data),
      result.statusCode!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
