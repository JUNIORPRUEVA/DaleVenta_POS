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
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = OfflineStore.instance;
  late Directory root;
  late String oldPath;
  late SyncQueueService queue;
  late Dio dio;
  late VentasRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    oldPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-credit-test-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(
      UserModel.fromJson({
        'id': 'user-a',
        'email': 'synthetic@example.test',
        'companyId': 'company-a',
        'nombreCompleto': 'Prueba',
      }),
    );
    queue = SyncQueueService(
      store,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: 'company-a', userId: 'user-a'),
    );
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:14627'));
    repo = VentasRepository(
      dio,
      queue,
      WarehouseRepository(dio),
      originCashSessionIdResolver: () async => 'session-a',
    );
  });
  tearDown(() async {
    dio.close(force: true);
    queue.dispose();
    await store.closeForTesting();
    await databaseFactory.setDatabasesPath(oldPath);
    final resolved = root.absolute.path;
    expect(resolved.startsWith(Directory.systemTemp.absolute.path), isTrue);
    await root.delete(recursive: true);
  });
  Future<dynamic> pay() => repo.addCreditPayment(
    saleId: 'sale-a',
    cashAmount: 500,
    transferAmount: 0,
  );
  Map<String, dynamic> response(RequestOptions req) => {
    'sale': {
      'id': 'sale-a',
      'paymentMethod': 'credit',
      'totalSold': 2500,
      'creditPaidAmount': 1500,
      'creditBalance': 1000,
    },
    'payment': {
      'id': 'payment-a',
      'saleId': 'sale-a',
      'operationId': req.data['operationId'],
      'cashSessionId': 'session-a',
      'companyId': 'company-a',
      'userId': 'user-a',
      'cashAmount': 500,
      'transferAmount': 0,
    },
  };
  ResponseBody json(Map<String, dynamic> data, int status) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  test(
    'journals before POST and keeps the same identity across SQLite restart and lost response',
    () async {
      var posts = 0;
      late String identity;
      dio.httpClientAdapter = _Adapter((req) async {
        posts++;
        final pending = await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        );
        expect(pending.single.idempotencyKey, req.data['operationId']);
        expect(pending.single.nextAttemptAt, isNotNull);
        identity = pending.single.idempotencyKey!;
        throw DioException(
          requestOptions: req,
          type: DioExceptionType.receiveTimeout,
        );
      });
      expect((await pay()).status, 'PENDING_SYNC');
      await store.closeForTesting();
      expect(
        (await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        )).single.idempotencyKey,
        identity,
      );
      repo = VentasRepository(
        dio,
        queue,
        WarehouseRepository(dio),
        originCashSessionIdResolver: () async => 'session-a',
      );
      await expectLater(pay(), throwsA(isA<ApiException>()));
      expect(posts, 1);
      dio.httpClientAdapter = _Adapter((req) async {
        posts++;
        expect(req.data['operationId'], identity);
        return json(response(req), 201);
      });
      repo.registerSyncHandlers();
      final pending = (await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
      )).single;
      await store.updatePendingAction(
        pending.copyWith(clearNextAttemptAt: true),
      );
      await queue.processPending();
      expect(posts, 2);
      expect(
        await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        ),
        isEmpty,
      );
    },
  );

  test(
    'confirmed response removes only its journal and returns the confirmed balance',
    () async {
      dio.httpClientAdapter = _Adapter((req) async => json(response(req), 201));
      final sale = await pay();
      expect(sale.creditBalance, 1000);
      expect(
        await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        ),
        isEmpty,
      );
    },
  );

  for (final field in [
    'saleId',
    'operationId',
    'cashAmount',
    'companyId',
    'id',
  ]) {
    test(
      'mismatched $field keeps the journal and blocks a second payment',
      () async {
        dio.httpClientAdapter = _Adapter((req) async {
          final body = response(req);
          (body['payment'] as Map)[field] = field == 'cashAmount'
              ? 600
              : field == 'id'
              ? ''
              : 'mismatch';
          return json(body, 201);
        });
        await expectLater(pay(), throwsA(isA<ApiException>()));
        final pending = await store.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        );
        expect(pending.single.status, 'conflict');
        await expectLater(pay(), throwsA(isA<ApiException>()));
      },
    );
  }

  test(
    '422 is retained as rejected and never replayed; 429 preserves Retry-After',
    () async {
      dio.httpClientAdapter = _Adapter(
        (req) async => json({'message': 'Importe inválido'}, 422),
      );
      await expectLater(pay(), throwsA(isA<ApiException>()));
      var pending = await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
      );
      expect(pending.single.status, 'review_resolved');
      expect(pending.single.permanent, isTrue);
      dio.httpClientAdapter = _Adapter(
        (req) async => ResponseBody.fromString(
          '{"message":"Espera"}',
          429,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'retry-after': ['600'],
          },
        ),
      );
      await expectLater(pay(), throwsA(isA<ApiException>()));
      pending = await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
      );
      final waiting = pending.singleWhere(
        (row) => row.status != 'review_resolved',
      );
      expect(waiting.permanent, isFalse);
      expect(
        waiting.nextAttemptAt!.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 9)),
        ),
        isTrue,
      );
    },
  );
}
