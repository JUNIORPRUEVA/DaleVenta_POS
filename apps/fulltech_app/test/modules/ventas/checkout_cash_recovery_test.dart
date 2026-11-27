import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/pos_sale_identity.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = OfflineStore.instance;
  late Directory root;
  late String previous;
  late SyncQueueService queue;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    previous = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('checkout-cash-recovery-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(
      UserModel.fromJson({
        'id': 'user-a',
        'companyId': 'company-a',
        'email': 'fixture@example.test',
        'role': 'ADMIN',
      }),
    );
    queue = SyncQueueService(store, scopeResolver: () async {
      final user = await TokenStorage().getUserSnapshot();
      return OfflineSyncScope(companyId: user?.companyId, userId: user?.id);
    });
  });
  tearDown(() async {
    queue.dispose();
    await store.closeForTesting();
    await databaseFactory.setDatabasesPath(previous);
    await root.delete(recursive: true);
  });

  Future<SaleModel?> charge(VentasRepository repo) => repo.createSale(
    clientTicketId: 'ticket-held-for-days',
    paymentMethod: 'cash',
    paymentCashAmount: 100,
    cashReceived: 100,
    expectedTotalSold: 100,
    items: const [
      SaleDraftItem(
        productId: 'product-a',
        name: 'Fixture',
        imageUrl: null,
        isExternal: false,
        qty: 1,
        priceSoldUnit: 100,
        costUnitSnapshot: 40,
      ),
    ],
  );

  ResponseBody sale(RequestOptions request) => _json({
    'id': 'sale-confirmed',
    'userId': 'user-a',
    'clientRequestId': request.data['clientRequestId'],
    'totalSold': 100,
    'totalCost': 40,
    'totalProfit': 60,
    'commissionAmount': 0,
    'paymentMethod': 'cash',
    'items': [],
  }, 201);

  for (final gate in [
    {'canOperate': false, 'staleBusinessDate': true, 'requiresClosure': true},
    {'canOperate': false},
    {'canOperate': true, 'pendingClose': true},
    {
      'canOperate': true,
      'requiresReview': true,
      'reviewMessage': 'Revisión pendiente.',
    },
  ]) {
    test(
      'fresh cash verdict blocks before POST or durable attempt: $gate',
      () async {
        var posts = 0;
        final dio = Dio()
          ..httpClientAdapter = _Adapter((request) async {
            if (request.method == 'POST') posts++;
            return _json({
              'businessDate': '2026-11-27',
              ...gate,
              'activeSession': {
                'shiftId': 'old-shift',
                'userId': 'user-a',
                'status': 'OPEN',
                'openedAt': '2026-11-20T12:00:00Z',
                'businessDate': '2026-11-20',
              },
            });
          });
        final repo = VentasRepository(
          dio,
          queue,
          WarehouseRepository(dio),
          durableSaleAttemptsForTesting: true,
        );
        final expected = gate['pendingClose'] == true ? 'cierre de caja'
            : gate['requiresReview'] == true ? 'Revisión pendiente.'
            : gate['staleBusinessDate'] == true ? 'turno anterior' : 'no está habilitado';
        await expectLater(charge(repo), throwsA(isA<ApiException>()
          .having((error) => error.message, 'cash verdict', contains(expected))));
        expect(posts, 0);
        expect(await store.listPendingActions(limit: null), isEmpty);
        dio.close(force: true);
      },
    );
  }

  test(
    'a turn valid when payment opened is rechecked before the final confirmation',
    () async {
      var valid = true;
      var posts = 0;
      var checks = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          if (request.path == '/cash/state') {
            checks++;
            return _json({
              'businessDate': '2026-11-27',
              'canOperate': valid,
              'staleBusinessDate': !valid,
              'requiresClosure': !valid,
              'activeSession': {
                'shiftId': 'shift-a',
                'userId': 'user-a',
                'status': 'OPEN',
                'openedAt': '2026-11-27T12:00:00Z',
                'businessDate': '2026-11-27',
              },
            });
          }
          if (request.path != '/sales') return _json([]);
          posts++;
          return sale(request);
        });
      final cash = CashRepository(dio, queue);
      final repo = VentasRepository(
        dio,
        queue,
        WarehouseRepository(dio),
        cashRepository: cash,
        durableSaleAttemptsForTesting: true,
      );
      expect((await cash.state()).checkoutBlockReason(), isNull);
      valid = false;
      await expectLater(charge(repo), throwsA(isA<ApiException>()));
      expect(checks, 2);
      expect(posts, 0);
      expect(await store.listPendingActions(limit: null), isEmpty);
      valid = true;
      expect((await charge(repo))?.id, 'sale-confirmed');
      expect(posts, 1);
      dio.close(force: true);
    },
  );

  for (final code in [
    'CASH_SESSION_STALE',
    'ORIGIN_SESSION_CLOSED',
    'ORIGIN_SESSION_NOT_FOUND',
    'CASH_OPERATION_BEFORE_SHIFT',
    'CASH_OPERATION_AFTER_CLOSE',
  ]) {
    test(
      'typed pre-transaction rejection releases attempt; same ticket can retry: $code',
      () async {
        var posts = 0;
        final dio = Dio()
          ..httpClientAdapter = _Adapter((request) async {
            if (request.path != '/sales') return _json([]);
            posts++;
            return posts == 1
                ? _json({
                    'code': code,
                    'errorCode': code,
                    'message': 'Revisa el turno.',
                  }, 409)
                : sale(request);
          });
        final repo = VentasRepository(
          dio,
          queue,
          WarehouseRepository(dio),
          originCashSessionIdResolver: () async => 'shift-a',
          durableSaleAttemptsForTesting: true,
        );
        await expectLater(charge(repo), throwsA(isA<ApiException>()));
        expect(await store.listPendingActions(limit: null), isEmpty);
        expect((await charge(repo))?.id, 'sale-confirmed');
        expect(posts, 2);
        dio.close(force: true);
      },
    );
  }

  for (final outcome in [
    'timeout',
    'generic-conflict',
    'unmatched-code',
    'server-error',
  ]) {
    test(
      'uncertain result still blocks the original ticket: $outcome',
      () async {
        var posts = 0;
        final dio = Dio()
          ..httpClientAdapter = _Adapter((request) async {
            if (request.path != '/sales') return _json([]);
            posts++;
            if (outcome == 'timeout') {
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.receiveTimeout,
              );
            }
            return _json(
              outcome == 'unmatched-code'
                  ? {
                      'code': 'CASH_SESSION_STALE',
                      'errorCode': 'IDEMPOTENCY_CONFLICT',
                    }
                  : {'message': 'No confirmado'},
              outcome == 'server-error' ? 503 : 409,
            );
          });
        final repo = VentasRepository(
          dio,
          queue,
          WarehouseRepository(dio),
          originCashSessionIdResolver: () async => 'shift-a',
          durableSaleAttemptsForTesting: true,
        );
        await expectLater(charge(repo), throwsA(anything));
        await store.closeForTesting();
        await expectLater(charge(repo), throwsA(anything));
        expect(posts, 1);
        expect(
          (await store.listUnresolvedSaleAttempts(
            companyId: 'company-a',
            userId: 'user-a',
          )),
          hasLength(1),
        );
        dio.close(force: true);
      },
    );
  }

  test(
    'withdrawal through recovery permits same ticket, survives restart and preserves both original attempts',
    () async {
      var posts = 0;
      var withdrawn = false;
      late PendingSyncAction original;
      final sentKeys = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          if (request.path.startsWith('/recovery/reviews')) {
            final decision = request.path.endsWith('/decision');
            if (decision) withdrawn = true;
            final identity = RecoveryReviewRepository.requestFor(original);
            return _json({
              ...identity,
              'id': 'review-$posts',
              'companyId': 'company-a',
              'sourceUserId': 'user-a',
              'sourceActionId': original.id,
              'version': 1,
              'status': withdrawn ? 'RESOLVED_NOT_PERFORMED' : 'OPEN',
              'financiallyConfirmed': false,
            });
          }
          if (request.path != '/sales') return _json([]);
          posts++;
          sentKeys.add(request.data['clientRequestId'] as String);
          if (posts < 3) {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            );
          }
          return sale(request);
        });
      final repo = VentasRepository(
        dio,
        queue,
        WarehouseRepository(dio),
        originCashSessionIdResolver: () async => 'shift-a',
        durableSaleAttemptsForTesting: true,
      );
      final recovery = RecoveryReviewRepository(dio, store);
      for (var index = 0; index < 2; index++) {
        if (index == 0) {
          await expectLater(charge(repo), throwsA(anything));
        } else {
          await Future.wait([
            expectLater(charge(repo), throwsA(anything)),
            expectLater(charge(repo), throwsA(anything)),
          ]);
        }
        expect(
          posts,
          index + 1,
          reason:
              'Double confirmation must reserve only one financial operation.',
        );
        original = (await store.listUnresolvedSaleAttempts(
          companyId: 'company-a',
          userId: 'user-a',
        )).single;
        withdrawn = false;
        await recovery.resolveNotPerformed(original, 'No se realizó el cobro.');
        await store.closeForTesting();
      }
      expect((await charge(repo))?.id, 'sale-confirmed');
      expect(sentKeys.toSet(), hasLength(3));
      // The successful revision is stable too: any repeated submission uses
      // the same backend idempotency key, never a fourth financial operation.
      expect((await charge(repo))?.id, 'sale-confirmed');
      expect(sentKeys.last, sentKeys[2]);
      final archived = await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
        limit: null,
      );
      expect(archived, hasLength(2));
      expect(
        archived.every(
          (a) =>
              a.status == 'review_resolved' &&
              a.payload['recoveryReviewStatus'] == 'RESOLVED_NOT_PERFORMED',
        ),
        isTrue,
      );
      expect(
        archived.map((a) => a.idempotencyKey).toSet(),
        sentKeys.take(2).toSet(),
      );
      expect(
        await store.listUnresolvedSaleAttempts(
          companyId: 'company-a',
          userId: 'user-a',
        ),
        isEmpty,
      );
      dio.close(force: true);
    },
  );

  for (final decision in [
    'RESOLVED_REGISTERED',
    'OPEN',
    'missing-proof',
    'money-received',
  ]) {
    test(
      'resolved/uncertain money is never treated as a withdrawn charge: $decision',
      () async {
        var posts = 0;
        final dio = Dio()
          ..httpClientAdapter = _Adapter((request) async {
            if (request.path != '/sales') return _json([]);
            posts++;
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            );
          });
        final repo = VentasRepository(
          dio,
          queue,
          WarehouseRepository(dio),
          originCashSessionIdResolver: () async => 'shift-a',
          durableSaleAttemptsForTesting: true,
        );
        await expectLater(charge(repo), throwsA(anything));
        final original = (await store.listPendingActions(limit: null)).single;
        await store.updatePendingAction(
          original.copyWith(
            status: 'review_resolved',
            permanent: true,
            payload: {
              ...original.payload,
              'recoveryReviewStatus': decision == 'missing-proof'
                  ? 'RESOLVED_NOT_PERFORMED'
                  : decision,
              if (decision != 'missing-proof') 'recoveryReviewId': 'review-a',
            },
          ),
        );
        await store.closeForTesting();
        await expectLater(charge(repo), throwsA(anything));
        expect(posts, 1);
        expect(
          (await store.listPendingActions(limit: null)).single.idempotencyKey,
          original.idempotencyKey,
        );
        dio.close(force: true);
      },
    );
  }

  test(
    'an unconfirmed withdrawal never advances the ticket or loses its pending evidence',
    () async {
      var posts = 0;
      late PendingSyncAction original;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          if (request.path.startsWith('/recovery/reviews')) {
            return _json({
              ...RecoveryReviewRepository.requestFor(original),
              'id': 'review-open',
              'companyId': 'company-a',
              'sourceUserId': 'user-a',
              'sourceActionId': original.id,
              'version': 1,
              'status': 'OPEN',
              'financiallyConfirmed': false,
            });
          }
          if (request.path != '/sales') return _json([]);
          posts++;
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        });
      final repo = VentasRepository(
        dio,
        queue,
        WarehouseRepository(dio),
        originCashSessionIdResolver: () async => 'shift-a',
        durableSaleAttemptsForTesting: true,
      );
      await expectLater(charge(repo), throwsA(anything));
      original = (await store.listPendingActions(limit: null)).single;
      await expectLater(
        RecoveryReviewRepository(
          dio,
          store,
        ).resolveNotPerformed(original, 'Revisar retiro.'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(charge(repo), throwsA(anything));
      expect(posts, 1);
      expect(
        (await store.listUnresolvedSaleAttempts(
          companyId: 'company-a',
          userId: 'user-a',
        )).single.id,
        original.id,
      );
      dio.close(force: true);
    },
  );

  test(
    'a withdrawn ticket in another company or user cannot advance this identity',
    () async {
      final key = posSaleRequestId(
        companyId: 'company-a',
        userId: 'user-a',
        deviceId: 'device-a',
        ticketId: 'ticket-a',
      )!;
      final now = DateTime.now().toUtc();
      await store.putPendingAction(
        PendingSyncAction(
          id: 'sales.attempt:$key',
          type: 'sales.attempt',
          scope: 'sales',
          companyId: 'company-b',
          userId: 'user-b',
          idempotencyKey: key,
          payload: {
            'posTicketId': 'ticket-a',
            'deviceFingerprint': 'device-a',
            'recoveryReviewStatus': 'RESOLVED_NOT_PERFORMED',
            'recoveryReviewId': 'foreign-review',
          },
          status: 'review_resolved',
          attempts: 0,
          createdAt: now,
          updatedAt: now,
        ),
        requireDatabase: true,
      );
      expect(
        await store.saleAttemptRevisionForTicket(
          companyId: 'company-a',
          userId: 'user-a',
          deviceId: 'device-a',
          ticketId: 'ticket-a',
        ),
        0,
      );
    },
  );

  test(
    'revision zero keeps legacy identity; revisions remain scoped to tenant/user/device/ticket',
    () {
      String id({
        String company = 'a',
        String user = 'u',
        String device = 'd',
        String ticket = 't',
        int revision = 0,
      }) => posSaleRequestId(
        companyId: company,
        userId: user,
        deviceId: device,
        ticketId: ticket,
        attemptRevision: revision,
      )!;
      expect(
        id(),
        // Golden value from the original SHA-256 of ["a","u","d","t"].
        'pos_b4940b770b875bda21c4e8781bdb9b100b80986838253f3f05518b480e5aa307',
      );
      expect({
        id(),
        id(revision: 1),
        id(company: 'b', revision: 1),
        id(user: 'v', revision: 1),
        id(device: 'e', revision: 1),
        id(ticket: 'x', revision: 1),
      }, hasLength(6));
    },
  );

  test(
    'cached shift is usable today but cannot carry into a later business day',
    () {
      final session = ActiveCashSession(
        userId: 'u',
        shiftId: 's',
        status: 'OPEN',
        userName: 'U',
        openedAt: _opened,
        businessDate: '2026-11-27',
      );
      final gate = CashGateState(
        businessDate: '2026-11-27',
        canOperate: true,
        fromCache: true,
        activeSession: session,
      );
      expect(
        gate.checkoutBlockReason(now: DateTime.utc(2026, 11, 28, 3, 59)),
        isNull,
      );
      expect(
        gate.checkoutBlockReason(now: DateTime.utc(2026, 11, 28, 4)),
        contains('turno anterior'),
      );
    },
  );
}

final _opened = DateTime.utc(2026, 11, 27, 12);

ResponseBody _json(Object value, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}
