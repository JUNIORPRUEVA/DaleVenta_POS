import 'dart:typed_data';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/api/api_error_mapper.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation_providers.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_recovery_engine.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_recovery_providers.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class CaptureAdapter implements HttpClientAdapter {
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"id":"movement-id","operationId":"original-operation","sessionId":"original-shift","type":"IN","amount":10}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class PendingStore implements OfflineStore {
  int counts = 0;
  @override
  Future<int> countUnresolvedSaleAttempts({
    required String companyId,
    required String userId,
  }) async {
    counts++;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PendingSyncAction action(
  String id, {
  String type = 'sales.attempt',
  String status = 'requires_action',
  bool permanent = false,
  DateTime? createdAt,
  Map<String, dynamic>? payload,
}) {
  final at = createdAt ?? DateTime.utc(2026, 11, 20);
  return PendingSyncAction(
    id: id,
    type: type,
    scope: 'sales',
    companyId: 'audit-company',
    userId: 'audit-user',
    idempotencyKey: id,
    payload: payload ?? {'expectedTotalSold': 100},
    status: status,
    permanent: permanent,
    attempts: 0,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Regression: provider startup checks attempts in the active company and user',
    () async {
      await TokenStorage().saveUserSnapshot(
        UserModel(
          id: 'audit-user',
          companyId: 'audit-company',
          email: 'fixture@local.test',
          nombreCompleto: 'Fixture',
          telefono: '',
        ),
      );
      final store = PendingStore();
      var lookups = 0;
      final reconciler = SaleAttemptReconciler(
        lookup: (_, __) async {
          lookups++;
          return null;
        },
        listAttempts: ({companyId, userId}) async => [action('request-1')],
        recordEvidence:
            ({
              required action,
              required clientRequestId,
              required result,
              required decision,
              actorUserId,
              actorRole,
              note,
            }) async {},
        resolveAttempt:
            ({
              required action,
              required clientRequestId,
              required result,
              required decision,
              actorUserId,
              actorRole,
              note,
            }) async => true,
      );
      final container = ProviderContainer(
        overrides: [
          offlineStoreProvider.overrideWithValue(store),
          saleAttemptReconcilerProvider.overrideWithValue(reconciler),
          recoveryEngineStoreProvider.overrideWithValue(
            InMemoryRecoveryEngineStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(recoveryEngineProvider)
          .runOnce(trigger: RecoveryTrigger.startup);
      expect(result, RecoveryRunOutcome.partiallyUnreachable);
      expect(store.counts, 2);
      expect(lookups, 1);
    },
  );

  test('Regression: mismatched confirmation preserves the incident', () async {
    var resolved = false;
    final reconciler = SaleAttemptReconciler(
      lookup: (_, __) async => {
        'status': 'CONFIRMED',
        'clientRequestId': 'other-request',
        'matchesExpected': false,
        'sale': {'id': 'sale-x', 'totalSold': 999},
      },
      listAttempts: ({companyId, userId}) async => [],
      recordEvidence:
          ({
            required action,
            required clientRequestId,
            required result,
            required decision,
            actorUserId,
            actorRole,
            note,
          }) async {},
      resolveAttempt:
          ({
            required action,
            required clientRequestId,
            required result,
            required decision,
            actorUserId,
            actorRole,
            note,
          }) async {
            resolved = true;
            return true;
          },
    );
    await reconciler.verify(action('expected-request'));
    expect(resolved, isFalse);
  });

  test(
    'Regression: forty blocked actions do not starve newer eligible work',
    () async {
      final store = OfflineStore.forTesting('audit_starvation_20261120.db');
      await store.clearAll();
      addTearDown(store.closeForTesting);
      final service = SyncQueueService(
        store,
        scopeResolver: () async => const OfflineSyncScope(
          companyId: 'audit-company',
          userId: 'audit-user',
        ),
      );
      addTearDown(service.dispose);
      var processed = 0;
      service.registerHandler('audit.operation', (_) async {
        processed++;
      });
      for (var i = 0; i < 40; i++) {
        await store.putPendingAction(
          action(
            'blocked-$i',
            type: 'audit.operation',
            status: 'failed',
            permanent: true,
          ),
        );
      }
      await store.putPendingAction(
        action(
          'eligible',
          type: 'audit.operation',
          status: 'pending',
          createdAt: DateTime.utc(2026, 11, 21),
        ),
      );
      await service.processPending();
      expect(processed, 1);
      final all = await store.listPendingActions(
        limit: 100,
        companyId: 'audit-company',
        userId: 'audit-user',
      );
      expect(all.any((a) => a.id == 'eligible'), isFalse);
      expect(all.length, 40);
    },
  );

  test('Regression: cash replay preserves original occurredAt', () async {
    final store = OfflineStore.forTesting('audit_cash_replay_20261120.db');
    await store.clearAll();
    addTearDown(store.closeForTesting);
    final service = SyncQueueService(
      store,
      scopeResolver: () async => const OfflineSyncScope(
        companyId: 'audit-company',
        userId: 'audit-user',
      ),
    );
    addTearDown(service.dispose);
    final adapter = CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
      ..httpClientAdapter = adapter;
    addTearDown(() => dio.close());
    CashRepository(dio, service, offlineStore: store).registerSyncHandlers();
    await store.putPendingAction(
      action(
        'movement-audit',
        type: 'cash.movement',
        status: 'pending',
        payload: {
          'sessionId': 'original-shift',
          'operationId': 'original-operation',
          'type': 'IN',
          'amount': 10,
          'reason': 'fixture',
          'occurredAt': '2026-11-18T12:00:00Z',
        },
      ),
    );
    await service.processPending();
    expect(adapter.request, isNotNull);
    expect(
      (adapter.request!.data as Map)['occurredAt'],
      '2026-11-18T12:00:00Z',
    );
  });

  test('Regression: mapped 422 is permanent and retained', () async {
    final store = OfflineStore.forTesting('audit_422_20261120.db');
    await store.clearAll();
    addTearDown(store.closeForTesting);
    final service = SyncQueueService(
      store,
      scopeResolver: () async => const OfflineSyncScope(
        companyId: 'audit-company',
        userId: 'audit-user',
      ),
    );
    addTearDown(service.dispose);
    final options = RequestOptions(path: '/audit');
    final mapped = ApiErrorMapper.fromDio(
      DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 422,
          data: {'message': 'fixture validation'},
        ),
        type: DioExceptionType.badResponse,
      ),
      fallbackMessage: 'fixture',
    );
    service.registerHandler('audit.422', (_) async {
      throw mapped;
    });
    await store.putPendingAction(
      action('mapped-422', type: 'audit.422', status: 'pending'),
    );
    await service.processPending();
    final remaining = await store.listPendingActions(
      companyId: 'audit-company',
      userId: 'audit-user',
    );
    expect(remaining.single.status, 'failed');
    expect(remaining.single.permanent, isTrue);
    expect(remaining.single.nextAttemptAt, isNull);
  });
}
