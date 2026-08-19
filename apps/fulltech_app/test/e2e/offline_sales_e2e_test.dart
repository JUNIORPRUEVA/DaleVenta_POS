import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  late TokenStorage tokenStorage;
  late OfflineStore store;
  var blockSalePosts = false;

  Dio newDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.getAccessToken();
          if ((token ?? '').isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (blockSalePosts &&
              options.method.toUpperCase() == 'POST' &&
              options.path == ApiRoutes.sales) {
            return handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'offline-sales-e2e forced connection loss',
              ),
            );
          }
          return handler.next(options);
        },
      ),
    );
    return dio;
  }

  Future<SyncQueueService> newSyncQueue() async {
    final service = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async {
        final user = await tokenStorage.getUserSnapshot();
        return OfflineSyncScope(companyId: user?.companyId, userId: user?.id);
      },
    );
    await service.refreshStats();
    return service;
  }

  Future<Map<String, dynamic>> registerBusiness(Dio dio, String suffix) async {
    final res = await dio.post(
      ApiRoutes.registerBusiness,
      data: {
        'firstName': 'Offline',
        'lastName': 'E2E $suffix',
        'email': 'offline-e2e-$suffix@example.test',
        'phone': '+1809555${suffix.padLeft(4, '0')}',
        'password': 'Offline12345!',
        'confirmPassword': 'Offline12345!',
        'commercialName': 'Offline E2E $suffix',
        'legalName': 'Offline E2E $suffix SRL',
        'country': 'DO',
        'currency': 'DOP',
        'timezone': 'America/Santo_Domingo',
        'locale': 'es-DO',
      },
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<UserModel> persistSession(Map<String, dynamic> auth) async {
    final accessToken = auth['accessToken']?.toString() ?? '';
    final refreshToken = auth['refreshToken']?.toString();
    final userJson = ((auth['user'] as Map?) ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    final activeCompany =
        ((auth['activeCompany'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>();
    final user = UserModel.fromJson({
      ...userJson,
      'companyId': userJson['companyId'] ?? activeCompany['id'],
      'companyName':
          userJson['companyName'] ??
          activeCompany['name'] ??
          activeCompany['commercialName'],
    });
    await tokenStorage.saveTokens(accessToken, refreshToken);
    await tokenStorage.saveUserSnapshot(user);
    return user;
  }

  Future<ProductModel> createProduct(Dio dio, String suffix) async {
    final res = await dio.post(
      ApiRoutes.products,
      data: {
        'nombre': 'Producto Offline E2E $suffix',
        'codigo': 'OFF-E2E-$suffix',
        'precio': 100,
        'costo': 40,
        'stock': 10,
        'categoria': 'E2E',
        'taxTreatment': 'EXEMPT',
        'taxPriceMode': 'NO_TAX',
      },
    );
    return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<ProductModel> fetchProduct(Dio dio, String id) async {
    final res = await dio.get(ApiRoutes.productDetail(id));
    return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tokenStorage = TokenStorage();
    store = OfflineStore.instance;
    await tokenStorage.clearTokens();
    await store.clearAll();
    blockSalePosts = false;
  });

  tearDown(() async {
    blockSalePosts = false;
    await tokenStorage.clearTokens();
    await store.clearAll();
    await OfflineStore.instance.closeForTesting();
  });

  test(
    'offline non-fiscal sale survives restart and syncs once to the real API',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final bootstrapDio = newDio();

      final companyAAuth = await registerBusiness(bootstrapDio, 'a-$suffix');
      final companyAUser = await persistSession(companyAAuth);
      final product = await createProduct(bootstrapDio, suffix);
      await bootstrapDio.post(
        ApiRoutes.cashOpenSession,
        data: {'openingAmount': 500, 'note': 'offline e2e'},
      );

      var syncQueue = await newSyncQueue();
      var ventas = VentasRepository(newDio(), syncQueue)
        ..registerSyncHandlers();

      final loadedProducts = await ventas.fetchProducts(forceRefresh: true);
      expect(loadedProducts.map((item) => item.id), contains(product.id));

      blockSalePosts = true;
      final localSale = await ventas.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 200,
        expectedTotalSold: 200,
        note: 'offline e2e non fiscal sale',
        items: [
          SaleDraftItem(
            product: product,
            productId: product.id,
            name: product.nombre,
            imageUrl: product.displayFotoUrl,
            isExternal: false,
            qty: 2,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
          ),
        ],
      );
      expect(localSale, isNotNull);
      expect(localSale!.id, startsWith('local_sale_req_'));

      final pendingBeforeRestart = await store.listPendingActions(
        companyId: companyAUser.companyId,
        userId: companyAUser.id,
      );
      expect(pendingBeforeRestart, hasLength(1));
      expect(pendingBeforeRestart.single.type, 'sales.create');
      expect(pendingBeforeRestart.single.idempotencyKey, isNotEmpty);

      final aggregateBeforeRestart = await store.getOfflineSaleAggregate(
        companyId: companyAUser.companyId!,
        localSaleId: localSale.id,
      );
      expect(aggregateBeforeRestart, isNotNull);
      expect(aggregateBeforeRestart!['status'], 'pending');
      expect(aggregateBeforeRestart['items'], hasLength(1));
      expect(aggregateBeforeRestart['payments'], hasLength(1));
      expect(aggregateBeforeRestart['inventoryIntents'], hasLength(1));
      expect(
        (aggregateBeforeRestart['inventoryIntents'] as List).single['status'],
        'pending',
      );

      syncQueue.dispose();
      await OfflineStore.instance.closeForTesting();

      store = OfflineStore.instance;
      final aggregateAfterRestart = await store.getOfflineSaleAggregate(
        companyId: companyAUser.companyId!,
        localSaleId: localSale.id,
      );
      expect(aggregateAfterRestart, isNotNull);
      expect(aggregateAfterRestart!['clientRequestId'], isNotEmpty);

      final companyBAuth = await registerBusiness(bootstrapDio, 'b-$suffix');
      await persistSession(companyBAuth);
      final companyBQueue = await newSyncQueue();
      VentasRepository(newDio(), companyBQueue).registerSyncHandlers();
      blockSalePosts = false;
      await companyBQueue.processPending();
      companyBQueue.dispose();

      final pendingWhileCompanyBActive = await store.listPendingActions(
        companyId: companyAUser.companyId,
        userId: companyAUser.id,
      );
      expect(pendingWhileCompanyBActive, hasLength(1));

      await persistSession(companyAAuth);
      syncQueue = await newSyncQueue();
      ventas = VentasRepository(newDio(), syncQueue)..registerSyncHandlers();
      await syncQueue.processPending();

      final pendingAfterSync = await store.listPendingActions(
        companyId: companyAUser.companyId,
        userId: companyAUser.id,
      );
      expect(pendingAfterSync, isEmpty);

      final syncedAggregate = await store.getOfflineSaleAggregate(
        companyId: companyAUser.companyId!,
        localSaleId: localSale.id,
      );
      expect(syncedAggregate, isNotNull);
      expect(syncedAggregate!['status'], 'synced');
      expect(syncedAggregate['serverId'], isNotEmpty);
      expect(
        (syncedAggregate['inventoryIntents'] as List).single['status'],
        'synced',
      );

      await syncQueue.processPending();

      final syncedSales = await ventas.listSales(
        from: DateTime(2020, 1, 1),
        to: DateTime(2099, 12, 31),
      );
      expect(syncedSales, hasLength(1));
      expect(syncedSales.single.id, syncedAggregate['serverId']);
      expect(syncedSales.single.userId, companyAUser.id);
      expect(syncedSales.single.items, hasLength(1));
      expect(syncedSales.single.items.single.productId, product.id);
      expect(syncedSales.single.items.single.qty, 2);
      expect(syncedSales.single.totalSold, 200);
      expect(syncedSales.single.paymentMethod, 'cash');

      final syncedProduct = await fetchProduct(newDio(), product.id);
      expect(syncedProduct.stock, 8);

      syncQueue.dispose();
    },
    skip: _apiBaseUrl.isEmpty
        ? 'Set API_BASE_URL to run the real Flutter/API offline E2E.'
        : false,
  );
}
