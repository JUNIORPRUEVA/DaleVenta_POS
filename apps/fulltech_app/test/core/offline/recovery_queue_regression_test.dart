import 'dart:convert';
import 'package:daleventa_pos/core/api/api_error_mapper.dart';
import 'package:daleventa_pos/core/api/retry_after.dart';
import 'package:daleventa_pos/core/auth/operation_scope.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  late SyncQueueService queue;
  var serial = 0;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = OfflineStore.forTesting(
      'recovery_queue_${DateTime.now().microsecondsSinceEpoch}_${serial++}.db',
    );
    queue = SyncQueueService(
      store,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: 'company-a', userId: 'user-a'),
    );
  });
  tearDown(() async {
    queue.dispose();
    await store.closeForTesting();
  });
  PendingSyncAction row(
    String id, {
    String type = 'operation',
    String status = 'pending',
    bool permanent = false,
    Map<String, dynamic> payload = const {},
  }) => PendingSyncAction(
    id: id,
    type: type,
    scope: 'test',
    companyId: 'company-a',
    userId: 'user-a',
    payload: payload,
    status: status,
    permanent: permanent,
    attempts: 0,
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: serial++)),
    updatedAt: DateTime.now().toUtc(),
  );
  for (final mapped in [false, true]) {
    for (final status in [401, 403, 409, 422, 429]) {
      test(
        'HTTP $status mapped=$mapped is retained with the correct retry policy',
        () async {
          var calls = 0;
          final options = RequestOptions(path: '/fixture');
          final error = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: status,
              headers: Headers.fromMap({
                'retry-after': ['120'],
              }),
            ),
          );
          queue.registerHandler('operation', (_) async {
            calls++;
            throw mapped
                ? ApiErrorMapper.fromDio(error, fallbackMessage: 'fixture')
                : error;
          });
          await store.putPendingAction(row('http-$status'));
          final before = DateTime.now().toUtc();
          await queue.processPending();
          final persisted = (await store.listPendingActions(
            limit: null,
          )).single;
          expect(
            persisted.status,
            {
              401: 'auth_blocked',
              403: 'failed',
              409: 'conflict',
              422: 'failed',
              429: 'error',
            }[status],
          );
          expect(persisted.permanent, status != 429);
          if (status == 429) {
            expect(
              persisted.nextAttemptAt!.difference(before).inSeconds,
              greaterThanOrEqualTo(120),
            );
          }
          await store.closeForTesting();
          await queue.processPending();
          expect(
            calls,
            1,
            reason:
                'restart and manual retry cannot bypass a permanent error or Retry-After',
          );
          expect((await store.listPendingActions()).single.id, persisted.id);
        },
      );
    }
  }
  test(
    'blocked shift dependencies retain close, allow independent work, and count separately',
    () async {
      final sent = <String>[];
      for (final type in ['cash.movement', 'cash.close', 'operation']) {
        queue.registerHandler(type, (_) async {
          sent.add(type);
        });
      }
      await store.putPendingAction(
        row(
          'open',
          type: 'cash.open',
          status: 'failed',
          permanent: true,
          payload: {'clientSessionId': 'shift-a'},
        ),
      );
      await store.putPendingAction(
        row(
          'movement',
          type: 'cash.movement',
          payload: {'sessionId': 'shift-a'},
        ),
      );
      await store.putPendingAction(
        row('close', type: 'cash.close', payload: {'sessionId': 'shift-a'}),
      );
      await store.putPendingAction(row('unrelated'));
      await store.putPendingAction(
        row('attention', status: 'requires_action', permanent: true),
      );
      await queue.processPending();
      expect(sent, ['operation']);
      expect(queue.state.pendingCount, 2);
      expect(queue.state.blockedCount, 1);
      expect(queue.state.conflictCount, 1);
      expect(queue.state.errorCount, 0);
      expect((await store.listPendingActions(limit: null)).length, 4);
    },
  );
  test(
    'authentication recovery never releases another tenant and never releases a 403',
    () async {
      await store.putPendingAction(
        row('401', status: 'auth_blocked', permanent: true),
      );
      await store.putPendingAction(
        row('403', status: 'failed', permanent: true),
      );
      expect(
        await queue.releaseAuthBlocked(
          type: '',
          companyId: 'company-b',
          userId: 'user-b',
        ),
        0,
      );
      expect(await queue.releaseAuthBlocked(type: ''), 1);
      expect(
        (await store.listPendingActions())
            .singleWhere((a) => a.id == '403')
            .status,
        'failed',
      );
    },
  );
  test(
    'request scope pins JWT company and user, including a reused request after refresh',
    () {
      String token(String company, String user) =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'companyId': company, 'sub': user})))}.signature';
      const scope = OperationScope('company-a', 'user-a');
      expect(scope.matchesToken(token('company-a', 'user-a')), isTrue);
      expect(scope.matchesToken(token('company-b', 'user-a')), isFalse);
      expect(scope.matchesToken(token('company-a', 'user-b')), isFalse);
      expect(scope.matchesToken('invalid'), isFalse);
    },
  );
  test(
    'Retry-After accepts HTTP date and seconds without a negative delay',
    () {
      expect(parseRetryAfter('120'), const Duration(seconds: 120));
      expect(
        parseRetryAfter(
          'Fri, 20 Nov 2026 12:02:00 GMT',
          now: DateTime.utc(2026, 11, 20, 12),
        ),
        const Duration(minutes: 2),
      );
      expect(parseRetryAfter('-1'), isNull);
    },
  );
  test('sync messages and counters restore only for their original owner', () async {
    var owner=const OfflineSyncScope(companyId:'company-a',userId:'user-a');
    final scoped=SyncQueueService(store,scopeResolver:()async=>owner);
    addTearDown(scoped.dispose);
    scoped.registerHandler('operation',(_)async=>throw ApiException('Detalle de empresa A',422));
    await store.putPendingAction(row('metadata'));
    await scoped.processPending();
    final message=scoped.state.lastError;
    expect(message,isNotNull); expect(scoped.state.blockedCount,1);
    owner=const OfflineSyncScope(companyId:'company-b',userId:'user-b');
    await scoped.refreshStats();
    expect(scoped.state.lastError,isNull); expect(scoped.state.blockedCount,0);
    owner=const OfflineSyncScope(companyId:'company-a',userId:'user-a');
    await scoped.refreshStats();
    expect(scoped.state.lastError,message); expect(scoped.state.blockedCount,1);
  });
  test(
    'a duplicate local id cannot overwrite another company or user',
    () async {
      final original = row('collision');
      await store.putPendingAction(original);
      await expectLater(
        store.putPendingAction(
          original.copyWith(companyId: 'company-b', userId: 'user-b'),
        ),
        throwsStateError,
      );
      final persisted = (await store.listPendingActions()).single;
      expect(persisted.companyId, 'company-a');
      expect(persisted.userId, 'user-a');
    },
  );
}
