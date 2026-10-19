import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_validation_interceptor.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'historical quote recovery DTO is validated only from a disposable copy',
    () async {
      sqfliteFfiInit();
      final path = File(
        '../../.uat/evidence/phase11-quote-recovery-copy.db',
      ).absolute.path;
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await db.query(
          'pending_actions',
          where: 'id = ?',
          whereArgs: ['quotes.create:local_quote_1791944878261619'],
        );
        final payload = jsonDecode(rows.single['payload'] as String) as Map;
        final quote = CotizacionModel.fromMap(
          Map<String, dynamic>.from(payload['quote'] as Map),
        );
        final dto = quote.toCreateDto();
        expect(dto.containsKey('customerId'), isFalse);
        expect(dto['customerName'], quote.customerName);
        expect(dto['customerPhone'], (quote.customerPhone ?? '').trim());
        expect((dto['items'] as List).length, 3);
        expect(rows.single['status'], 'failed');
        expect(rows.single['attempts'], 41);
        await File(
          '../../.uat/evidence/phase11-quote-recovery-dto.json',
        ).writeAsString(
          jsonEncode({
            'companyId': payload['companyId'],
            'dto': dto,
            'total': 390,
          }),
        );
      } finally {
        await db.close();
      }
    },
    skip: Platform.environment['FULLPOS_PHASE11_UAT'] != 'true',
  );
  test(
    'UAT SQLite reopen and product-entry-sale replay after lost confirmations',
    () async {
      expect(Platform.environment['APP_ENV'], 'uat');
      expect(Platform.environment['UAT_LOCAL_ONLY'], 'true');
      expect(Platform.environment['PORT'], '46548');
      final root = Platform.environment['DALEVENTAS_POS_ROOT'] ?? '';
      expect(root, contains('phase11-flutter-client-'));
      expect(root, isNot(contains('windows-app-root')));
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final transport = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'));
      final login = await transport.post(
        '/auth/login',
        data: {
          'email': Platform.environment['UAT_ADMIN_EMAIL'],
          'password': Platform.environment['UAT_ADMIN_PASSWORD'],
        },
      );
      final user = UserModel.fromJson(
        Map<String, dynamic>.from(login.data['user'] as Map),
      );
      await TokenStorage().saveUserSnapshot(user);
      final headers = await ClientTelemetryHeaders.instance.headers();
      transport.options.headers.addAll(headers);
      transport.options.headers['authorization'] =
          'Bearer ${login.data['accessToken']}';
      final auth = await transport.post(
        '/auth/offline-emergency/authorize',
        data: {},
      );
      await OfflineEmergencyPolicy().recordAuthorizationResponse(
        data: Map<String, dynamic>.from(auth.data as Map),
        companyId: user.companyId!,
        userId: user.id,
        deviceFingerprint: headers['x-client-device-id']!,
      );
      final cash = await transport.get('/cash/state');
      final shiftId = cash.data['activeSession']['shiftId'] as String;
      final adapter = _InterruptedAdapter(transport);
      final dio = Dio(BaseOptions(baseUrl: transport.options.baseUrl))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(OfflineEmergencyValidationInterceptor(
        tokenStorage: TokenStorage(), dio: dio,
      ));
      final store = OfflineStore.instance;
      if (Platform.environment['FULLPOS_PHASE13_RESUME_ONLY'] == 'true') {
        await _resumeUpdatedStore(root, user, store, dio, transport, adapter);
        transport.close(force: true);
        dio.close(force: true);
        return;
      }
      await store.clearAll();
      SyncQueueService queue() => SyncQueueService(
        store,
        scopeResolver: () async =>
            OfflineSyncScope(companyId: user.companyId, userId: user.id),
      );
      var sync = queue();
      var catalog = CatalogRepository(dio, TokenStorage(), sync)
        ..registerSyncHandlers();
      final runId = 'phase11-flutter-${DateTime.now().millisecondsSinceEpoch}';
      final product = await catalog.createProduct(
        nombre: runId,
        codigo: runId,
        precio: 100,
        costo: 40,
        stock: 0,
        categoria: 'UAT phase11',
      );
      await _idle(sync);
      final stocked = await catalog.adjustProductStock(
        id: product.id,
        delta: 20,
        reason: runId,
      );
      expect(stocked.stock, 20);
      await _idle(sync);
      final ventas = VentasRepository(
        dio,
        sync,
        WarehouseRepository(dio),
        originCashSessionIdResolver: () async => shiftId,
      )..registerSyncHandlers();
      final sale = await ventas.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 400,
        cashReceived: 400,
        expectedTotalSold: 400,
        items: [
          SaleDraftItem(
            productId: product.id,
            name: runId,
            imageUrl: null,
            isExternal: false,
            qty: 4,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
          ),
        ],
      );
      await _idle(sync);
      expect(sale?.id, startsWith('local_'));
      final before = await store.listPendingActions(
        companyId: user.companyId,
        userId: user.id,
      );
      expect(before.length, 3);
      if (Platform.environment['FULLPOS_PHASE13_PREPARE_ONLY'] == 'true') {
        await File('$root/update-pending-fixture.json').writeAsString(jsonEncode({
          'companyId': user.companyId, 'userId': user.id,
          'productId': product.id, 'shiftId': shiftId,
          'actions': before.map((action) => {
            'id': action.id, 'payload': action.payload,
            'idempotencyKey': action.idempotencyKey,
          }).toList(),
          'scope': 'Disposable Flutter/SQLite fixture; native UI not operated',
        }));
        sync.dispose();
        await store.closeForTesting();
        transport.close(force: true);
        dio.close(force: true);
        return;
      }
      expect(
        before
            .where((a) => a.type != 'catalog.products.create')
            .every((a) => a.attempts == 0),
        isTrue,
      );
      sync.dispose();
      await store.closeForTesting();
      sync = queue();
      catalog = CatalogRepository(dio, TokenStorage(), sync)
        ..registerSyncHandlers();
      VentasRepository(
        dio,
        sync,
        WarehouseRepository(dio),
        originCashSessionIdResolver: () async => shiftId,
      ).registerSyncHandlers();
      expect((await catalog.getCachedProducts()).single.stock, 20);
      expect(
        (await store.listPendingActions(
          companyId: user.companyId,
          userId: user.id,
        )).map((a) => a.id),
        before.map((a) => a.id),
      );
      adapter.offline = false;
      // Only this disposable test's mocked preferences receive an expired grant.
      // Windows/server clocks and the manual app's grant remain unchanged.
      final expiredAt = DateTime.now().toUtc().subtract(
        const Duration(hours: 49),
      );
      await OfflineEmergencyPolicy().recordServerValidation(
        companyId: user.companyId!,
        userId: user.id,
        deviceFingerprint: headers['x-client-device-id']!,
        serverUtc: expiredAt,
        observedAtUtc: expiredAt,
      );
      final expiredDecision = await OfflineEmergencyPolicy()
          .canStartOfflineSale(
            companyId: user.companyId!,
            userId: user.id,
            deviceFingerprint: headers['x-client-device-id']!,
          );
      expect(expiredDecision.allowed, isFalse);
      expect(expiredDecision.reason, OfflineEmergencyBlockReason.expired);
      expect(
        (await store.listPendingActions(
          companyId: user.companyId,
          userId: user.id,
        )).length,
        3,
      );
      adapter.loseNext.addAll([
        'POST /products',
        'PATCH /products/${product.id}/stock',
        'POST /sales',
      ]);
      for (var attempt = 0; attempt < 4; attempt++) {
        for (final action in await store.listPendingActions(
          companyId: user.companyId,
          userId: user.id,
        )) {
          await store.updatePendingAction(
            action.copyWith(clearNextAttemptAt: true),
          );
        }
        await sync.processPending();
        // Reopen after the server committed and the adapter discarded its ACK.
        // This covers SQLite/service recovery, not a physical process crash.
        sync.dispose();
        await store.closeForTesting();
        sync = queue();
        catalog = CatalogRepository(dio, TokenStorage(), sync)
          ..registerSyncHandlers();
        VentasRepository(
          dio,
          sync,
          WarehouseRepository(dio),
          originCashSessionIdResolver: () async => shiftId,
        ).registerSyncHandlers();
      }
      expect(
        await store.listPendingActions(
          companyId: user.companyId,
          userId: user.id,
        ),
        isEmpty,
      );
      final localSales = await store.listOfflineSales(
        companyId: user.companyId!,
        userId: user.id,
      );
      expect(localSales.single['status'], 'synced');
      final remote = await transport.get('/products/${product.id}');
      expect(double.parse(remote.data['stock'].toString()), 16);
      expect(adapter.lost, 3);
      // No credentials or JWTs enter the evidence artifact.
      final evidence = {
        'status': 'PASS',
        'runId': runId,
        'companyId': user.companyId,
        'productId': product.id,
        'shiftId': shiftId,
        'saleClientRequestId': before
            .singleWhere((a) => a.type == 'sales.create')
            .payload['clientRequestId'],
        'stockOperationId': before
            .singleWhere((a) => a.type == 'catalog.products.stock')
            .payload['operationId'],
        'lostConfirmations': adapter.lost,
        'pending': 0,
        'stock': 16,
        'sqliteReopen': true,
        'reopenAfterLostAck': true,
        'expiredGrantFixturePendingSynced': true,
      };
      await File(
        '$root/integrity-result.json',
      ).writeAsString(jsonEncode(evidence));
      sync.dispose();
      await store.closeForTesting();
      transport.close(force: true);
      dio.close(force: true);
    },
    skip: Platform.environment['FULLPOS_PHASE11_UAT'] != 'true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _idle(SyncQueueService queue) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  while (queue.state.isProcessing) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _resumeUpdatedStore(String root, UserModel user, OfflineStore store,
    Dio dio, Dio transport, _InterruptedAdapter adapter) async {
  expect(root, contains('phase13-update-bench'));
  final fixture = jsonDecode(await File('$root/update-pending-fixture.json').readAsString()) as Map;
  expect(fixture['companyId'], user.companyId);
  expect(fixture['userId'], user.id);
  final productId = fixture['productId'] as String;
  final shiftId = fixture['shiftId'] as String;
  final original = await store.listPendingActions(companyId: user.companyId, userId: user.id);
  expect(original.length, 5);
  for (final expected in fixture['actions'] as List) {
    final actual = original.singleWhere((action) => action.id == expected['id']);
    expect(actual.payload, expected['payload']);
    expect(actual.idempotencyKey, expected['idempotencyKey']);
  }
  final sync = SyncQueueService(store, scopeResolver: () async => OfflineSyncScope(
    companyId: user.companyId, userId: user.id,
  ));
  CatalogRepository(dio, TokenStorage(), sync).registerSyncHandlers();
  VentasRepository(dio, sync, WarehouseRepository(dio),
    originCashSessionIdResolver: () async => shiftId).registerSyncHandlers();
  adapter.offline = false;
  adapter.loseNext.addAll(['POST /products', 'PATCH /products/$productId/stock', 'POST /sales']);
  try {
    for (var attempt = 0; attempt < 4; attempt++) {
      for (final action in await store.listPendingActions(companyId: user.companyId, userId: user.id)) {
        if (!action.permanent) await store.updatePendingAction(action.copyWith(clearNextAttemptAt: true));
      }
      await sync.processPending();
    }
    final remaining = await store.listPendingActions(companyId: user.companyId, userId: user.id);
    expect(remaining.map((action) => action.id).toSet(), {'quotes.create:phase13-permanent', 'phase13-legacy-unknown'});
    for (final action in remaining) {
      final before = original.singleWhere((candidate) => candidate.id == action.id);
      expect(action.payload, before.payload);
      expect(action.idempotencyKey, before.idempotencyKey);
      expect(action.permanent, before.permanent);
      expect(action.attempts, before.attempts);
    }
    expect((await transport.get('/products/$productId')).data['stock'].toString(), anyOf('16', '16.000000'));
    expect((await store.listOfflineSales(companyId: user.companyId!, userId: user.id)).single['status'], 'synced');
    final economic = original.where((action) => (fixture['actions'] as List).any((expected) => expected['id'] == action.id));
    final result = {
      'status': 'PASS', 'companyId': user.companyId, 'productId': productId, 'shiftId': shiftId,
      'saleClientRequestId': economic.singleWhere((action) => action.type == 'sales.create').payload['clientRequestId'],
      'stockOperationId': economic.singleWhere((action) => action.type == 'catalog.products.stock').payload['operationId'],
      'remainingFixtures': remaining.map((action) => action.id).toList(),
      'lostConfirmations': adapter.lost, 'stock': 16,
      'scope': 'Flutter/SQLite queue resumed after real UAT installer file replacement; native GUI sync not asserted',
    };
    await File('$root/update-resume-result.json').writeAsString(jsonEncode(result));
  } finally { sync.dispose(); await store.closeForTesting(); }
}

class _InterruptedAdapter implements HttpClientAdapter {
  _InterruptedAdapter(this.transport);
  final Dio transport;
  bool offline = true;
  final Set<String> loseNext = {};
  int lost = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final response = await transport.request<Object?>(
      options.path,
      data: options.data,
      options: Options(method: options.method),
    );
    if (loseNext.remove('${options.method} ${options.path}')) {
      lost++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.statusCode!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
