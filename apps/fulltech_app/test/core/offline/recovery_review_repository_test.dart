import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  late PendingSyncAction action;
  late Dio dio;
  late RecoveryReviewRepository repository;
  late Map<String, dynamic> reply;
  late List<String> paths;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(
      UserModel.fromJson({
        'id': 'user-a',
        'companyId': 'company-a',
        'email': 'fixture@example.test',
        'nombreCompleto': 'Fixture',
      }),
    );
    store = OfflineStore.forTesting(
      'review_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final now = DateTime.now().toUtc();
    action = PendingSyncAction(
      id: 'blocked-a',
      type: 'cash.movement',
      scope: 'cash',
      companyId: 'company-a',
      userId: 'user-a',
      idempotencyKey: 'operation-a',
      payload: {
        'operationId': 'operation-a',
        'sessionId': 'shift-a',
        'amount': 7,
        'type': 'IN',
        'offlineOpenPermit': 'must-not-be-transmitted',
        'accessToken': 'must-not-be-transmitted',
      },
      status: 'requires_action',
      permanent: true,
      attempts: 1,
      createdAt: now,
      updatedAt: now,
    );
    await store.putPendingAction(action, requireDatabase: true);
    reply = {
      'id': 'review-a',
      'companyId': 'company-a',
      'sourceUserId': 'user-a',
      'sourceActionId': 'blocked-a',
      'actionType': 'cash.movement',
      'operationId': 'operation-a',
      'originalSessionId': 'shift-a',
      'expectedAmount': 7,
      'status': 'OPEN',
      'version': 1,
      'financiallyConfirmed': false,
      'needsIntervention': true,
    };
    paths = [];
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        paths.add(request.path);
        return reply;
      });
    repository = RecoveryReviewRepository(dio, store);
  });
  tearDown(() async {
    dio.close(force: true);
    await store.closeForTesting();
  });
  Future<PendingSyncAction> persisted() async =>
      (await store.listPendingActions(
        companyId: 'company-a',
        userId: 'user-a',
        limit: null,
      )).singleWhere((row) => row.id == action.id);

  test('one check prepares an idempotent case and verifies without replaying money', () async {
    await TokenStorage().saveUserSnapshot(UserModel.fromJson({
      'id': 'user-a', 'companyId': 'company-a', 'email': 'fixture@example.test', 'role': 'ADMIN',
    }));
    await repository.check(action);
    expect(paths, ['/recovery/reviews', '/recovery/reviews/review-a/verify']);
    final saved = await store.listPendingActions(limit: null);
    expect(saved.single.status, 'requires_action');
    expect(saved.single.payload['amount'], action.payload['amount']);
    expect(saved.single.createdAt.millisecondsSinceEpoch, action.createdAt.millisecondsSinceEpoch);
  });

  test('cashier cannot prepare or check an operation through the admin action', () async {
    await TokenStorage().saveUserSnapshot(UserModel.fromJson({
      'id': 'user-a', 'companyId': 'company-a', 'email': 'fixture@example.test', 'role': 'CAJERO',
    }));
    await expectLater(repository.check(action), throwsA(isA<Exception>()));
    expect(paths, isEmpty);
    expect((await store.listPendingActions(limit: null)).single.payload, action.payload);
  });

  test(
    'submission preserves original evidence and excludes authorization secrets',
    () async {
      final summary =
          RecoveryReviewRepository.requestFor(action)['payloadSummary'] as Map;
      expect(summary.containsKey('accessToken'), isFalse);
      expect(summary.containsKey('offlineOpenPermit'), isFalse);
      await repository.submit(action);
      final saved = await persisted();
      expect(saved.status, 'requires_action');
      expect(saved.payload['accessToken'], action.payload['accessToken']);
      expect(saved.payload['recoveryReviewId'], 'review-a');
      expect(paths, ['/recovery/reviews']);
    },
  );
  for (final mismatch in [
    {'expectedAmount': 8},
    {'operationId': 'other'},
    {'sourceUserId': 'other'},
    {'companyId': 'foreign'},
    {'originalSessionId': 'another-shift'},
  ]) {
    test('mismatched review is never attached: $mismatch', () async {
      reply.addAll(mismatch);
      await expectLater(repository.submit(action), throwsException);
      expect(
        (await persisted()).payload.containsKey('recoveryReviewId'),
        isFalse,
      );
    });
  }
  test('confirmation requires an entity identifier', () async {
    reply.addAll({
      'status': 'RESOLVED_REGISTERED',
      'financiallyConfirmed': true,
      'registeredEntityId': '',
    });
    await repository.submit(action);
    expect((await persisted()).status, 'requires_action');
  });
  test(
    'exact registered result retains row and leaves active counters',
    () async {
      reply.addAll({
        'status': 'RESOLVED_REGISTERED',
        'financiallyConfirmed': true,
        'registeredEntityId': 'movement-a',
      });
      await repository.submit(action);
      expect((await persisted()).status, 'review_resolved');
      expect(
        await store.reviewedFinancialOperationIds(
          companyId: 'company-a',
          userId: 'user-a',
          type: 'cash.movement',
        ),
        {'operation-a'},
      );
      expect(
        await store.reviewedFinancialOperationIds(
          companyId: 'company-b',
          userId: 'user-a',
          type: 'cash.movement',
        ),
        isEmpty,
      );
      final stats = await store.pendingActionStats(
        companyId: 'company-a',
        userId: 'user-a',
      );
      expect(stats.values.fold<int>(0, (sum, count) => sum + count), 0);
      expect(
        paths.every((path) => path.startsWith('/recovery/reviews')),
        isTrue,
      );
    },
  );
  test(
    'human not-performed resolution never claims financial confirmation',
    () async {
      reply.addAll({
        'status': 'RESOLVED_NOT_PERFORMED',
        'financiallyConfirmed': false,
      });
      await repository.submit(action);
      final saved = await persisted();
      expect(saved.status, 'review_resolved');
      expect(saved.payload['recoveryReviewStatus'], 'RESOLVED_NOT_PERFORMED');
      expect(paths, ['/recovery/reviews']);
    },
  );
  for (final type in ['cash.open', 'cash.close']) {
    for (final matching in [true, false]) {
      test(
        '$type confirmation must return the original session: matching=$matching',
        () async {
          action = PendingSyncAction(
            id: 'blocked-$type',
            type: type,
            scope: 'cash',
            companyId: action.companyId,
            userId: action.userId,
            status: 'requires_action',
            permanent: true,
            attempts: 1,
            createdAt: action.createdAt,
            updatedAt: action.updatedAt,
            payload: type == 'cash.open'
                ? {'clientSessionId': 'shift-a', 'openingAmount': 7}
                : {'sessionId': 'shift-a', 'closingAmount': 7},
          );
          await store.putPendingAction(action, requireDatabase: true);
          reply.addAll({
            'sourceActionId': action.id,
            'actionType': type,
            'operationId': 'shift-a',
            'status': 'RESOLVED_REGISTERED',
            'financiallyConfirmed': true,
            'registeredEntityId': matching ? 'shift-a' : 'foreign-shift',
          });
          if (matching) {
            await repository.submit(action);
            expect((await persisted()).status, 'review_resolved');
          } else {
            await expectLater(repository.submit(action), throwsException);
            expect((await persisted()).status, 'requires_action');
            expect(
              (await persisted()).payload.containsKey('recoveryReviewId'),
              isFalse,
            );
          }
        },
      );
    }
  }
  test('changed owner cannot send an old incident', () async {
    await TokenStorage().saveUserSnapshot(
      UserModel.fromJson({
        'id': 'user-b',
        'companyId': 'company-b',
        'email': 'fixture-b@example.test',
        'nombreCompleto': 'Fixture',
      }),
    );
    await expectLater(repository.submit(action), throwsException);
    expect(paths, isEmpty);
  });
  test('withdrawal requires a confirmed company decision before local completion', () async {
    await TokenStorage().saveUserSnapshot(UserModel.fromJson({
      'id': 'user-a', 'companyId': 'company-a', 'email': 'fixture@example.test', 'role': 'ADMIN',
    }));
    await expectLater(repository.resolveNotPerformed(action, 'Synthetic audited withdrawal'), throwsException);
    expect((await persisted()).status, 'requires_action');
    dio.httpClientAdapter = _Adapter((request) {
      if (request.path.endsWith('/decision')) {
        reply['status'] = 'RESOLVED_NOT_PERFORMED';
      }
      return reply;
    });
    await repository.resolveNotPerformed(action, 'Synthetic audited withdrawal');
    expect((await persisted()).status, 'review_resolved');
    expect((await persisted()).payload['amount'], 7);
  });
  test('uncertain sale publishes canonical identity and receives admin resolution', () async {
    action = action.copyWith(payload: {'expectedTotalSold': 7, 'paymentMethod': 'cash'});
    action = PendingSyncAction.fromMap({...action.toMap(), 'id': 'blocked-sale', 'type': 'sales.attempt'});
    await store.putPendingAction(action, requireDatabase: true);
    reply.addAll({'sourceActionId': action.id, 'actionType': 'sales.create',
      'originalSessionId': null, 'status': 'RESOLVED_NOT_PERFORMED'});
    final body = RecoveryReviewRepository.requestFor(action);
    expect(body['actionType'], 'sales.create');
    expect((body['payloadSummary'] as Map)['clientRequestId'], 'operation-a');
    reply.addAll({'actionType': 'sales.create', 'originalSessionId': null,
      'status': 'RESOLVED_NOT_PERFORMED', 'financiallyConfirmed': false});
    await repository.submit(action);
    expect((await persisted()).status, 'review_resolved');
    expect((await persisted()).payload['expectedTotalSold'], 7);
  });
  test('delayed response cannot resurrect an archived incident', () async {
    await store.updatePendingAction(action.copyWith(status: 'review_resolved'));
    await repository.submit(action);
    expect((await persisted()).status, 'review_resolved');
  });
  test('compare and update does not overwrite newer local evidence or deleted rows', () async {
    final original = await persisted();
    final newer = original.copyWith(payload: {...original.payload, 'newEvidence': true});
    await store.updatePendingAction(newer);
    expect(await store.updatePendingActionIfUnchanged(original,
      original.copyWith(status: 'review_resolved')), isFalse);
    expect((await persisted()).payload['newEvidence'], true);
    await store.removePendingAction(action.id);
    expect(await store.updatePendingActionIfUnchanged(newer,
      newer.copyWith(status: 'review_resolved')), isFalse);
    expect(await store.listPendingActions(limit: null), isEmpty);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions request) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}
