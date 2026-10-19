import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/api/api_offline_circuit_breaker.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_validation_interceptor.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const capabilities = {
  'protocolVersion': 2, 'minimumClientProtocol': 2,
  'productOperationId': true, 'productPayloadHash': true,
  'inventoryOperationId': true, 'inventoryPayloadHash': true,
  'stableProductIdentity': true, 'dependentSync': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late _Backend adapter;
  late String device;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(UserModel(
      id: 'user-a', email: 'uat@test.local', nombreCompleto: 'UAT',
      telefono: '', companyId: 'company-a',
    ));
    device = (await ClientTelemetryHeaders.instance.headers())['x-client-device-id']!;
    adapter = _Backend(device);
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(OfflineEmergencyValidationInterceptor(
      tokenStorage: TokenStorage(), dio: dio,
    ));
  });
  tearDown(() { dio.close(force: true); });

  test('explicit protocol preserves the complete operation payload', () async {
    adapter.capabilities = capabilities;
    final payload = {'operationId': 'operation-a', 'delta': 20, 'reason': 'UAT'};
    await dio.patch('/products/product-a/stock', data: payload);
    expect(adapter.mutations.single.data, payload);
    expect(adapter.authorizations, 1);
  });

  test('legacy grant blocks advanced dispatch and offline admission', () async {
    final reachability = ApiOfflineCircuitState();
    dio.interceptors.add(ApiOfflineCircuitBreaker(state: reachability));
    await expectLater(dio.patch('/products/product-a/stock', data: {
      'operationId': 'operation-a', 'delta': 20,
    }), throwsA(isA<DioException>().having((e) => e.response?.data['code'], 'code', 'OFFLINE_PROTOCOL_UNSUPPORTED')));
    expect(adapter.mutations, isEmpty);
    expect(reachability.isOfflineFastFailActive, isFalse);
    await expectLater(OfflineEmergencyPolicy().assertOperationAllowed(
      companyId: 'company-a', userId: 'user-a', deviceFingerprint: device,
      operation: 'catalog.products.stock',
    ), throwsStateError);
    expect((await OfflineEmergencyPolicy().canStartOfflineSale(
      companyId: 'company-a', userId: 'user-a', deviceFingerprint: device,
    )).allowed, isTrue);
  });

  test('missing endpoint revokes advanced evidence without extending 48h', () async {
    final policy = OfflineEmergencyPolicy();
    final old = DateTime.now().toUtc().subtract(const Duration(hours: 47));
    await policy.recordServerValidation(companyId: 'company-a', userId: 'user-a',
      deviceFingerprint: device, serverUtc: old, observedAtUtc: old,
      allowedOperations: ['sales.create', 'catalog.products.stock'], advancedProtocolVerified: true);
    adapter.authorizationStatus = 404;
    await expectLater(dio.patch('/products/product-a/stock', data: {'operationId': 'original-id', 'delta': 20}), throwsA(isA<DioException>()));
    final decision = await policy.canStartOfflineSale(companyId: 'company-a', userId: 'user-a', deviceFingerprint: device);
    expect(decision.lastServerValidationUtc, old);
    expect(adapter.mutations, isEmpty);
    await expectLater(policy.assertOperationAllowed(companyId: 'company-a', userId: 'user-a', deviceFingerprint: device,
      operation: 'catalog.products.stock'), throwsStateError);
  });

  test('wrong company evidence cannot enable mutation', () async {
    adapter.capabilities = capabilities;
    adapter.companyId = 'company-b';
    await expectLater(dio.post('/products', data: {'operationId': 'same-id', 'nombre': 'UAT'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)));
    expect(adapter.mutations, isEmpty);
  });

  test('legacy online paths do not negotiate or change payloads', () async {
    await dio.get('/products');
    await dio.post('/sales', data: {'originCashSessionId': 'turn-a'});
    await dio.patch('/products/product-a/stock', data: {'delta': 20});
    expect(adapter.authorizations, 0);
    expect(adapter.mutations.last.data, {'delta': 20});
  });

  test('incompatible backend preserves pending identity until compatible', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final store = OfflineStore.forTesting('phase13-compatibility-pending.db');
    await store.clearAll();
    const payload = {'operationId': 'original-operation', 'delta': 20, 'reason': 'original'};
    final now = DateTime.now().toUtc();
    await store.putPendingAction(PendingSyncAction(id: 'original-outbox', type: 'catalog.products.stock',
      scope: 'catalog.company-a', companyId: 'company-a', userId: 'user-a',
      entityId: 'product-a', idempotencyKey: 'original-operation', payload: payload,
      status: 'pending', attempts: 0, createdAt: now, updatedAt: now));
    final queue = SyncQueueService(store, scopeResolver: () async => const OfflineSyncScope(companyId: 'company-a', userId: 'user-a'));
    queue.registerHandler('catalog.products.stock', (data) async { await dio.patch('/products/product-a/stock', data: data); });
    try {
      await queue.processPending();
      final preserved = (await store.listPendingActions(companyId: 'company-a', userId: 'user-a')).single;
      expect(preserved.id, 'original-outbox');
      expect(preserved.payload, payload);
      expect(preserved.idempotencyKey, 'original-operation');
      expect(preserved.permanent, isFalse);
      expect(preserved.status, 'error');
      expect(adapter.mutations, isEmpty);
      adapter.capabilities = capabilities;
      await store.updatePendingAction(preserved.copyWith(clearNextAttemptAt: true));
      await queue.processPending();
      expect(adapter.mutations.single.data, payload);
      expect(await store.listPendingActions(companyId: 'company-a', userId: 'user-a'), isEmpty);
    } finally { queue.dispose(); await store.closeForTesting(); }
  });
}

class _Backend implements HttpClientAdapter {
  _Backend(this.device);
  final String device;
  Object? capabilities;
  int authorizationStatus = 200;
  String companyId = 'company-a';
  int authorizations = 0;
  final List<RequestOptions> mutations = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object body = {'id': 'product-a'};
    var status = 200;
    if (options.path == '/auth/offline-emergency/authorize') {
      authorizations++;
      status = authorizationStatus;
      final now = DateTime.now().toUtc();
      body = {'authorized': true, 'policyVersion': OfflineEmergencyPolicy.policyVersion,
        'companyId': companyId, 'userId': 'user-a', 'deviceFingerprint': device,
        'serverUtc': now.toIso8601String(), 'validUntilUtc': now.add(const Duration(hours: 48)).toIso8601String(),
        'allowedOperations': ['sales.create', 'catalog.products.create', 'catalog.products.stock'],
        if (capabilities != null) 'capabilities': capabilities};
    } else if (options.method != 'GET') { mutations.add(options); }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}
