import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
    await TokenStorage().saveUserSnapshot(
      UserModel(
        id: 'user-products',
        email: 'products@test.local',
        nombreCompleto: 'Inventario',
        telefono: '',
        companyId: 'company-products',
      ),
    );
    final headers = await ClientTelemetryHeaders.instance.headers();
    await OfflineEmergencyPolicy().recordServerValidation(
      companyId: 'company-products',
      userId: 'user-products',
      deviceFingerprint: headers['x-client-device-id']!,
      serverUtc: DateTime.now().toUtc(),
      advancedProtocolVerified: true,
      allowedOperations: [
        'sales.create',
        'catalog.products.create',
        'catalog.products.stock',
      ],
    );
  });

  tearDown(() async {
    await OfflineStore.instance.clearAll();
  });

  SyncQueueService syncQueue() {
    return SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async => const OfflineSyncScope(
        companyId: 'company-products',
        userId: 'user-products',
      ),
    );
  }

  test('createProduct offline queues product with full payload', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
    final queue = syncQueue();
    final repository = CatalogRepository(dio, TokenStorage(), queue);
    repository.registerSyncHandlers();

    final local = await repository.createProduct(
      nombre: 'Producto Offline',
      codigo: 'OFF-1',
      precio: 120,
      costo: 70,
      stock: 9,
      categoria: 'UAT',
      operationId: 'product-create-offline-1',
      itemType: 'PRODUCT',
      trackInventory: true,
    );

    expect(local.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(local.nombre, 'Producto Offline');
    final pending = await OfflineStore.instance.listPendingActions(
      companyId: 'company-products',
      userId: 'user-products',
    );
    expect(pending.single.type, 'catalog.products.create');
    expect(
      pending.single.payload,
      containsPair('operationId', 'product-create-offline-1'),
    );
    expect(pending.single.payload, containsPair('itemType', 'PRODUCT'));
    expect(pending.single.payload, containsPair('trackInventory', true));
  });

  test(
    'adjustProductStock offline queues adjustment and returns local stock',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        });
      final queue = syncQueue();
      final repository = CatalogRepository(dio, TokenStorage(), queue);
      repository.registerSyncHandlers();
      await repository.saveProductsSnapshot([
        ProductModel(
          id: 'product-stock',
          nombre: 'Producto Stock',
          precio: 100,
          costo: 50,
          stock: 4,
          categoria: 'UAT',
        ),
      ]);

      final local = await repository.adjustProductStock(
        id: 'product-stock',
        delta: 8,
        reason: 'Ajuste offline UAT',
      );

      expect(local.id, 'product-stock');
      expect(local.stock, 12);
      final pending = await OfflineStore.instance.listPendingActions(
        companyId: 'company-products',
        userId: 'user-products',
      );
      expect(pending.single.type, 'catalog.products.stock');
      expect(pending.single.payload, containsPair('delta', 8));
      expect(pending.single.payload['operationId'], isA<String>());
      expect(
        pending.single.payload,
        containsPair('reason', 'Ajuste offline UAT'),
      );
    },
  );

  test(
    'stock keeps the first request operationId after a lost response and persists on reopen',
    () async {
      final sent = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          sent.add((options.data as Map)['operationId'].toString());
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        });
      final queue = syncQueue();
      final repository = CatalogRepository(dio, TokenStorage(), queue);
      await repository.saveProductsSnapshot([
        ProductModel(
          id: 'product-durable',
          nombre: 'Durable',
          precio: 100,
          costo: 50,
          stock: 0,
        ),
      ]);
      await repository.adjustProductStock(
        id: 'product-durable',
        delta: 20,
        operationId: 'stable-entry-id',
      );
      final action = (await OfflineStore.instance.listPendingActions()).single;
      expect(sent.single, 'stable-entry-id');
      expect(action.idempotencyKey, sent.single);
      expect(action.payload['operationId'], sent.single);
      final replay = await repository.adjustProductStock(
        id: 'product-durable',
        delta: 20,
        operationId: 'stable-entry-id',
      );
      expect(replay.stock, 20);
      await expectLater(
        repository.adjustProductStock(
          id: 'product-durable',
          delta: 21,
          operationId: 'stable-entry-id',
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        (await OfflineStore.instance.listPendingActions())
            .single
            .payload['delta'],
        20,
      );
      while (queue.state.isProcessing) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      queue.dispose();
      await OfflineStore.instance.closeForTesting();
      expect((await repository.getCachedProducts()).single.stock, 20);
      expect(
        (await OfflineStore.instance.listPendingActions()).single.id,
        action.id,
      );
    },
  );

  test(
    'offline absolute stock and deletion do not enqueue new operations',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        });
      final queue = syncQueue();
      final repository = CatalogRepository(dio, TokenStorage(), queue);
      await expectLater(
        repository.adjustProductStock(id: 'product-1', stock: 9),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.deleteProduct('product-1'),
        throwsA(isA<Exception>()),
      );
      expect(await OfflineStore.instance.listPendingActions(), isEmpty);
      queue.dispose();
    },
  );

  test('product creation needs its own authorization category', () async {
    final headers = await ClientTelemetryHeaders.instance.headers();
    await OfflineEmergencyPolicy().recordServerValidation(
      companyId: 'company-products',
      userId: 'user-products',
      deviceFingerprint: headers['x-client-device-id']!,
      serverUtc: DateTime.now().toUtc(),
    );
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
    final queue = syncQueue();
    final repository = CatalogRepository(dio, TokenStorage(), queue);
    await expectLater(
      repository.createProduct(
        nombre: 'No autorizado',
        precio: 100,
        costo: 40,
        stock: 0,
        categoria: 'UAT',
      ),
      throwsA(isA<Exception>()),
    );
    expect(await OfflineStore.instance.listPendingActions(), isEmpty);
    queue.dispose();
  });

  test(
    'a session switch during network failure cannot move a mutation to the new tenant',
    () async {
      final storage = TokenStorage();
      final originalUser = await storage.getUserSnapshot();
      final headers = await ClientTelemetryHeaders.instance.headers();
      await OfflineEmergencyPolicy().recordServerValidation(
        companyId: 'other-company',
        userId: 'other-user',
        deviceFingerprint: headers['x-client-device-id']!,
        serverUtc: DateTime.now().toUtc(),
        advancedProtocolVerified: true,
        allowedOperations: [
          'catalog.products.create',
          'catalog.products.stock',
        ],
      );
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          await storage.saveUserSnapshot(
            UserModel(
              id: 'other-user',
              email: 'other@test.local',
              nombreCompleto: 'Otra empresa',
              telefono: '',
              companyId: 'other-company',
            ),
          );
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        });
      final queue = syncQueue();
      final repository = CatalogRepository(dio, storage, queue);
      await expectLater(
        repository.createProduct(
          nombre: 'Producto original',
          precio: 100,
          costo: 40,
          stock: 0,
          categoria: 'UAT',
        ),
        throwsA(isA<Exception>()),
      );
      await storage.saveUserSnapshot(originalUser!);
      await expectLater(
        repository.adjustProductStock(id: 'product-original', delta: 20),
        throwsA(isA<Exception>()),
      );
      expect(await OfflineStore.instance.listPendingActions(), isEmpty);
      queue.dispose();
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
