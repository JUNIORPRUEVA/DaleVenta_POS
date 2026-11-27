import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/operation_scope.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';
import 'package:daleventa_pos/core/time/business_time.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String previous;
  late TokenStorage identity;
  late ProviderContainer container;
  late Dio dio;
  late bool disconnected;
  Future<void> Function(RequestOptions)? requestHook;
  late int financialPosts;
  final store = OfflineStore.instance;
  UserModel owner(String name) => UserModel.fromJson({
    'id': 'user-$name',
    'companyId': 'company-$name',
    'email': 'fixture-$name@example.test',
    'nombreCompleto': 'Fixture',
    'role': 'ADMIN',
  });
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    previous = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('fullpos-owner-switch-');
    await databaseFactory.setDatabasesPath(directory.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SerializedSecureStorage.resetForTesting();
    identity = TokenStorage();
    await identity.saveUserSnapshot(owner('a'));
    disconnected = false;
    requestHook = null;
    financialPosts = 0;
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        if (requestHook != null) await requestHook!(request);
        if (request.path == '/sales' && request.method == 'POST') {
          financialPosts++;
        }
        if (request.method == 'POST' && disconnected) {
          if (request.path == '/cash/sessions/open') {
            expect(OperationScope.current?.companyId, 'company-b');
          }
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        if (request.path == '/cash/sessions/open') {
          return {
            'userId': 'user-a',
            'shiftId': (request.data as Map)['clientSessionId'],
            'openingAmount': (request.data as Map)['openingAmount'],
            'status': 'OPEN',
            'openedAt': DateTime.now().toUtc().toIso8601String(),
            'businessDate': '2026-11-20',
          };
        }
        if (request.path == '/cash/state') {
          final actor = OperationScope.current!.userId;
          final now = DateTime.now().toUtc();
          return {
            'businessDate': businessDateKey(now), 'canOperate': true,
            'activeSession': {'userId': actor, 'shiftId': 'shift-${actor.split('-').last}',
              'status': 'OPEN', 'openedAt': now.toIso8601String(), 'businessDate': businessDateKey(now)},
          };
        }
        if (request.path == '/sales') {
          return {
            'id': 'sale-a',
            'userId': 'user-a',
            'clientRequestId': (request.data as Map)['clientRequestId'],
            'totalSold': 50,
            'items': <dynamic>[],
          };
        }
        if (request.path.contains('terminals')) return <dynamic>[];
        return {'inventoryEnabled': false};
      });
    container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(identity),
        dioProvider.overrideWithValue(dio),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    dio.close(force: true);
    await store.closeForTesting();
    await databaseFactory.setDatabasesPath(previous);
    await directory.delete(recursive: true);
  });
  test(
    'the same queue follows the shared authenticated owner after a company switch',
    () async {
      final queue = container.read(syncQueueServiceProvider.notifier);
      final first = await queue.captureScope();
      expect(first?.companyId, 'company-a');
      expect(first?.userId, 'user-a');
      await identity.saveUserSnapshot(owner('b'));
      final second = await queue.captureScope();
      expect(second?.companyId, 'company-b');
      expect(second?.userId, 'user-b');
    },
  );
  test(
    'a reused cash repository records a disconnected opening under the newly authenticated owner',
    () async {
      final repository = container.read(cashRepositoryProvider);
      await repository.openSession(openingAmount: 0);
      await identity.saveUserSnapshot(owner('b'));
      disconnected = true;
      await expectLater(
        repository.openSession(openingAmount: 9),
        throwsException,
      );
      final b = await store.listPendingActions(
        companyId: 'company-b',
        userId: 'user-b',
        limit: null,
      );
      expect(b.single.type, 'cash.open');
      expect(b.single.status, 'requires_action');
      expect(b.single.payload['openingAmount'], 9);
      expect(
        await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
          limit: null,
        ),
        isEmpty,
      );
    },
  );
  test(
    'a reused sales repository reserves an uncertain sale for the new owner',
    () async {
      Future<void> cacheShift(String actor) =>
          LocalJsonCache().writeMap('cash.active.session', {
            'activeSession': {
              'userId': 'user-$actor',
              'shiftId': 'shift-$actor',
              'status': 'OPEN',
              'openedAt': DateTime.now().toUtc().toIso8601String(),
              'businessDate': '2026-11-20',
            },
          });
      await cacheShift('a');
      final repository = container.read(ventasRepositoryProvider);
      Future<SaleModel?> sell(String id) => repository.createSale(
        clientRequestId: id,
        expectedTotalSold: 50,
        paymentMethod: 'cash',
        paymentCashAmount: 50,
        items: const [
          SaleDraftItem(
            productId: null,
            name: 'Synthetic service',
            imageUrl: null,
            isExternal: true,
            qty: 1,
            priceSoldUnit: 50,
            costUnitSnapshot: 0,
          ),
        ],
      );
      await sell('request-a');
      await identity.saveUserSnapshot(owner('b'));
      await cacheShift('b');
      disconnected = true;
      await expectLater(sell('request-b'), throwsException);
      final b = await store.listPendingActions(
        companyId: 'company-b',
        userId: 'user-b',
        limit: null,
      );
      expect(b.single.type, 'sales.attempt');
      expect(b.single.payload['clientRequestId'], 'request-b');
      expect(
        await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
          limit: null,
        ),
        isEmpty,
      );
    },
  );
  test(
    'switching owner during sale preparation cancels before the financial POST',
    () async {
      await LocalJsonCache().writeMap('cash.active.session', {
        'activeSession': {
          'userId': 'user-a',
          'shiftId': 'shift-a',
          'status': 'OPEN',
          'openedAt': DateTime.now().toUtc().toIso8601String(),
        },
      });
      var switched = false;
      requestHook = (request) async {
        if (!switched && request.method == 'GET') {
          switched = true;
          expect(OperationScope.current?.companyId, 'company-a');
          await identity.saveUserSnapshot(owner('b'));
        }
      };
      await expectLater(
        container
            .read(ventasRepositoryProvider)
            .createSale(
              clientRequestId: 'cancel-on-switch',
              expectedTotalSold: 50,
              paymentMethod: 'cash',
              paymentCashAmount: 50,
              items: const [
                SaleDraftItem(
                  productId: null,
                  name: 'Synthetic service',
                  imageUrl: null,
                  isExternal: true,
                  qty: 1,
                  priceSoldUnit: 50,
                  costUnitSnapshot: 0,
                ),
              ],
            ),
        throwsException,
      );
      expect(switched, isTrue);
      expect(financialPosts, 0);
      expect(await store.listPendingActions(limit: null), isEmpty);
    },
  );
  test(
    'switching owner while a sale response is lost retains the original owner incident',
    () async {
      await LocalJsonCache().writeMap('cash.active.session', {
        'activeSession': {
          'userId': 'user-a',
          'shiftId': 'shift-a',
          'status': 'OPEN',
          'openedAt': DateTime.now().toUtc().toIso8601String(),
        },
      });
      requestHook = (request) async {
        if (request.path == '/sales' && request.method == 'POST') {
          expect(OperationScope.current?.companyId, 'company-a');
          await identity.saveUserSnapshot(owner('b'));
          disconnected = true;
        }
      };
      await expectLater(
        container
            .read(ventasRepositoryProvider)
            .createSale(
              clientRequestId: 'lost-during-switch',
              expectedTotalSold: 50,
              paymentMethod: 'cash',
              paymentCashAmount: 50,
              items: const [
                SaleDraftItem(
                  productId: null,
                  name: 'Synthetic service',
                  imageUrl: null,
                  isExternal: true,
                  qty: 1,
                  priceSoldUnit: 50,
                  costUnitSnapshot: 0,
                ),
              ],
            ),
        throwsException,
      );
      expect(financialPosts, 1);
      final a = await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
        limit: null,
      );
      expect(a.single.type, 'sales.attempt');
      expect(a.single.payload['clientRequestId'], 'lost-during-switch');
      expect(
        await store.listPendingActions(
          companyId: 'company-b',
          userId: 'user-b',
          limit: null,
        ),
        isEmpty,
      );
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Future<dynamic> Function(RequestOptions request) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(await reply(options)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}
