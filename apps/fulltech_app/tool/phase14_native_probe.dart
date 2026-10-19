// Opt-in native UAT entry point. Never used by lib/main.dart or release scripts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String hash(String value) => sha256.convert(utf8.encode(value)).toString();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('FULLPOS_PHASE14_NATIVE_PROBE');
  if (!enabled || !Platform.isWindows) exit(70);
  final root = Platform.environment['DALEVENTAS_POS_ROOT'] ?? '';
  // This entry point must be built with the isolated runner metadata in the runbook.
  final package = await PackageInfo.fromPlatform();
  require(package.appName == 'FullPOSPhase14NativeUAT', 'Unsafe native namespace');
  require(root == r'C:\src\fullpos-offline-safe-48h\.uat\phase14-native-bank', 'Unsafe data root');
  require(Platform.environment['APP_ENV'] == 'uat', 'Not UAT');
  require(Platform.environment['UAT_LOCAL_ONLY'] == 'true', 'Not local');
  final stage = Platform.environment['FULLPOS_PHASE14_STAGE'];
  require(stage == 'A' || stage == 'B', 'Invalid stage');
  try {
    await probe(root, stage!, package.buildNumber);
    exit(0);
  } catch (error, stack) {
    // No HTTP exception body, token, credentials or seal values in evidence.
    await File('$root/native-$stage-failure.json').writeAsString(jsonEncode({
      'status': 'FAIL', 'type': error.runtimeType.toString(),
      'message': error is StateError ? error.message : 'Probe failed; inspect scoped environment',
      'stack': stack.toString(),
    }));
    exit(1);
  }
}

Future<void> probe(String root, String stage, String build) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tokenStorage = TokenStorage();
  final prefs = await SharedPreferences.getInstance();
  const secure = FlutterSecureStorage();
  final policy = OfflineEmergencyPolicy();
  final headers = await ClientTelemetryHeaders.instance.headers();
  final device = headers['x-client-device-id']!;
  final transport = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46552', headers: headers));
  final manifest = File('$root/native-A.json');
  UserModel user;
  Map<String, dynamic>? previous;
  if (stage == 'A') {
    require(!manifest.existsSync(), 'Refusing to overwrite an existing native bank');
    require(await tokenStorage.getAccessToken() == null, 'Native namespace is not empty');
    final login = await transport.post('/auth/login', data: {
      'email': Platform.environment['UAT_ADMIN_EMAIL'],
      'password': Platform.environment['UAT_ADMIN_PASSWORD'],
    });
    user = UserModel.fromJson(Map<String, dynamic>.from(login.data['user'] as Map));
    await tokenStorage.saveTokens(login.data['accessToken'] as String, login.data['refreshToken'] as String?);
    await tokenStorage.saveUserSnapshot(user);
    transport.options.headers['authorization'] = 'Bearer ${await tokenStorage.getAccessToken()}';
    final authorization = await transport.post('/auth/offline-emergency/authorize', data: {});
    await policy.recordAuthorizationResponse(data: Map<String, dynamic>.from(authorization.data as Map),
      companyId: user.companyId!, userId: user.id, deviceFingerprint: device);
  } else {
    previous = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    user = (await tokenStorage.getUserSnapshot())!;
    require(user.id == previous['userId'] && user.companyId == previous['companyId'], 'Native identity changed');
    require(hash(device) == previous['deviceHash'], 'Install identity changed');
    require(hash((await secure.read(key: 'accessToken'))!) == previous['tokenHash'], 'Secure token changed');
    transport.options.headers['authorization'] = 'Bearer ${await tokenStorage.getAccessToken()}';
  }
  final grantKey = 'offline_emergency.v1.company:${user.companyId}.user:${user.id}';
  final grant = prefs.getString(grantKey)!;
  require((await secure.read(key: 'offline_emergency.v1.seal_key'))?.isNotEmpty == true, 'Native HMAC key absent');
  require((await secure.read(key: 'offline_emergency.v1.seal.$grantKey'))?.isNotEmpty == true, 'Native seal absent');
  final grantData = jsonDecode(grant) as Map<String, dynamic>;
  final decision = await policy.canStartOfflineSale(companyId: user.companyId!, userId: user.id, deviceFingerprint: device);
  require(decision.allowed, 'Offline authorization unavailable');
  final expired = await policy.canStartOfflineSale(companyId: user.companyId!, userId: user.id, deviceFingerprint: device,
    nowUtc: DateTime.parse(grantData['observedDeviceUtc'] as String).add(const Duration(hours: 49)));
  require(!expired.allowed && expired.reason == OfflineEmergencyBlockReason.expired, '48h expiry not enforced');
  if (previous != null) require(hash(grant) == previous['grantHash'], 'Grant renewed during installation');
  final store = OfflineStore.instance;
  final adapter = ProbeAdapter(transport);
  final dio = Dio(BaseOptions(baseUrl: transport.options.baseUrl))..httpClientAdapter = adapter;
  dio.interceptors.add(OfflineEmergencyValidationInterceptor(tokenStorage: tokenStorage, dio: dio));
  final sync = ProbeQueue(store, scopeResolver: () async => OfflineSyncScope(companyId: user.companyId, userId: user.id));
  final catalog = CatalogRepository(dio, tokenStorage, sync)..registerSyncHandlers();
  String productId;
  String shiftId;
  if (stage == 'A') {
    require((await store.listPendingActions()).isEmpty, 'Bank already has pending actions');
    final cash = await transport.get('/cash/state');
    shiftId = cash.data['activeSession']['shiftId'] as String;
    final name = 'phase14-native-${DateTime.now().millisecondsSinceEpoch}';
    final product = await catalog.createProduct(nombre: name, codigo: name, precio: 100, costo: 40, stock: 0, categoria: 'UAT phase14');
    productId = product.id;
    await idle(sync);
    await catalog.adjustProductStock(id: productId, delta: 20, reason: name);
    await idle(sync);
    final sales = VentasRepository(dio, sync, WarehouseRepository(dio), originCashSessionIdResolver: () async => shiftId)
      ..registerSyncHandlers();
    await sales.createSale(paymentMethod: 'cash', paymentCashAmount: 400, cashReceived: 400, expectedTotalSold: 400,
      items: [SaleDraftItem(productId: productId, name: name, imageUrl: null, isExternal: false, qty: 4, priceSoldUnit: 100, costUnitSnapshot: 40)]);
    await idle(sync);
  } else {
    productId = previous!['productId'] as String;
    shiftId = previous['shiftId'] as String;
    VentasRepository(dio, sync, WarehouseRepository(dio), originCashSessionIdResolver: () async => shiftId).registerSyncHandlers();
  }
  final pending = await store.listPendingActions(companyId: user.companyId, userId: user.id);
  require(pending.length == 3, 'Expected three dependent pending operations');
  final actions = pending.map((a) => {'id': a.id, 'payload': a.payload, 'idempotencyKey': a.idempotencyKey}).toList();
  if (previous != null) require(jsonEncode(actions) == jsonEncode(previous['actions']), 'Original queue changed');
  final result = <String, dynamic>{'status': 'PASS', 'stage': stage, 'build': build,
    'companyId': user.companyId, 'userId': user.id, 'productId': productId, 'shiftId': shiftId,
    'deviceHash': hash(device), 'tokenHash': hash((await secure.read(key: 'accessToken'))!),
    'grantHash': hash(grant), 'validUntilUtc': grantData['validUntilUtc'],
    'nativeSecureStorageVerified': true, 'nativePreferencesVerified': true, 'expiresAfter48h': true, 'actions': actions};
  await File('$root/native-$stage.json').writeAsString(jsonEncode(result));
  if (stage == 'B') {
    // Separate process B proves offline restoration before any reconnect/auth renewal.
    final signal = File('$root/reconnect.signal');
    for (var i = 0; !signal.existsSync() && i < 600; i++) { await Future<void>.delayed(const Duration(milliseconds: 500)); }
    require(signal.existsSync(), 'Reconnect signal absent');
    adapter.offline = false;
    adapter.loseNext.addAll(['POST /products', 'PATCH /products/$productId/stock', 'POST /sales']);
    for (var i = 0; i < 4; i++) {
      for (final a in await store.listPendingActions(companyId: user.companyId, userId: user.id)) {
        await store.updatePendingAction(a.copyWith(clearNextAttemptAt: true));
      }
      await sync.processPending();
    }
    require((await store.listPendingActions(companyId: user.companyId, userId: user.id)).isEmpty, 'Sync still pending');
    require((await transport.get('/products/$productId')).data['stock'].toString().startsWith('16'), 'Unexpected stock');
    result['lostConfirmations'] = adapter.lost;
    result['stock'] = 16;
    result['saleClientRequestId'] = pending.singleWhere((a) => a.type == 'sales.create').payload['clientRequestId'];
    result['stockOperationId'] = pending.singleWhere((a) => a.type == 'catalog.products.stock').payload['operationId'];
    await File('$root/native-B-synced.json').writeAsString(jsonEncode(result));
  }
  sync.dispose();
  await store.closeForTesting();
  dio.close(force: true);
  transport.close(force: true);
}

class ProbeQueue extends SyncQueueService {
  ProbeQueue(super.store, {super.scopeResolver});
  bool get busy => state.isProcessing;
}

Future<void> idle(ProbeQueue sync) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var i = 0; sync.busy && i < 200; i++) { await Future<void>.delayed(const Duration(milliseconds: 25)); }
  require(!sync.busy, 'Queue did not become idle');
}

class ProbeAdapter implements HttpClientAdapter {
  ProbeAdapter(this.transport);
  final Dio transport;
  bool offline = true;
  final Set<String> loseNext = {};
  int lost = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (offline) throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    final response = await transport.request<Object?>(options.path, data: options.data, options: Options(method: options.method));
    if (loseNext.remove('${options.method} ${options.path}')) {
      lost++;
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(jsonEncode(response.data), response.statusCode!, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}
