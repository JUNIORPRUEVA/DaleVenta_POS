import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const company = 'journal-company',
      user = 'journal-user',
      shift = '11111111-1111-4111-8111-111111111111';
  late Directory root;
  late String previous;
  late SyncQueueService queue;
  late CashRepository repository;
  late Dio dio;
  late String mode;
  late int status;
  late int posts;
  late PendingSyncAction sent;
  final store = OfflineStore.instance;
  Future<List<PendingSyncAction>> actions() =>
      store.listPendingActions(companyId: company, userId: user, limit: null);
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    previous = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-cash-journal-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final identity = TokenStorage();
    await identity.saveUserSnapshot(
      UserModel.fromJson({
        'id': user,
        'companyId': company,
        'email': 'fixture@example.test',
        'nombreCompleto': 'Fixture',
      }),
    );
    queue = SyncQueueService(
      store,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: company, userId: user),
    );
    mode = 'exact';
    status = 201;
    posts = 0;
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        posts++;
        final before = await actions();
        expect(
          before.length,
          1,
          reason: 'The durable record must exist before any financial POST.',
        );
        sent = before.single;
        expect(sent.status, 'requires_action');
        expect(sent.permanent, isTrue);
        final body = request.data as Map;
        Map<String, dynamic> reply;
        if (request.path == '/cash/sessions/open') {
          expect(sent.payload['clientSessionId'], body['clientSessionId']);
          reply = {
            'userId': user,
            'shiftId': body['clientSessionId'],
            'openingAmount': body['openingAmount'],
            'status': 'OPEN',
            'openedAt': DateTime.now().toUtc().toIso8601String(),
            'businessDate': '2026-11-20',
          };
          if (mode == 'amount') reply['openingAmount'] = 99;
          if (mode == 'identity') reply['shiftId'] = 'another-shift';
          if (mode == 'missing') reply.remove('shiftId');
        } else if (request.path == '/cash/sessions/close') {
          final session = <String, dynamic>{
            'id': body['sessionId'],
            'status': 'CLOSED',
            'closingAmount': body['closingAmount'],
          };
          reply = {'session': session};
          if (mode == 'amount') session['closingAmount'] = 99;
          if (mode == 'identity') session['id'] = 'another-shift';
          if (mode == 'missing') session.remove('id');
        } else {
          expect(request.path, '/cash/movements');
          expect(sent.payload['occurredAt'], body['occurredAt']);
          expect(sent.payload['operationId'], body['operationId']);
          reply = {
            'id': 'registered-movement',
            'operationId': body['operationId'],
            'sessionId': body['sessionId'],
            'type': body['type'],
            'amount': body['amount'],
          };
          if (mode == 'amount') reply['amount'] = 99;
          if (mode == 'identity') reply['operationId'] = 'another-operation';
          if (mode == 'missing') reply.remove('id');
        }
        return ResponseBody.fromString(
          jsonEncode(reply),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            if (status == 429) 'retry-after': ['60'],
          },
        );
      });
    repository = CashRepository(
      dio,
      queue,
      offlineStore: store,
      tokenStorage: identity,
    );
  });
  tearDown(() async {
    queue.dispose();
    dio.close(force: true);
    await store.closeForTesting();
    await databaseFactory.setDatabasesPath(previous);
    expect(
      root.absolute.path.startsWith(
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
      ),
      isTrue,
    );
    await root.delete(recursive: true);
  });
  Future<void> perform(String kind) async {
    if (kind == 'open') {
      await repository.openSession(openingAmount: 7);
    } else if (kind == 'close') {
      await repository.closeSession(sessionId: shift, closingAmount: 7);
    } else {
      await repository.addMovement(
        sessionId: shift,
        type: 'IN',
        amount: 7,
        reason: 'Synthetic journal',
      );
    }
  }

  for (final kind in ['open', 'movement', 'close']) {
    test(
      '$kind is persisted before POST and consumed only after exact confirmation',
      () async {
        await perform(kind);
        expect(posts, 1);
        expect(await actions(), isEmpty);
      },
    );
    for (final mismatch in ['amount', 'identity', 'missing']) {
      test(
        '$kind preserves an uncertain $mismatch confirmation through store reopen',
        () async {
          mode = mismatch;
          await expectLater(perform(kind), throwsException);
          await store.closeForTesting();
          final saved = (await actions()).single;
          expect(saved.id, sent.id);
          expect(saved.status, 'requires_action');
          expect(saved.permanent, isTrue);
          expect(saved.payload, sent.payload);
          repository.registerSyncHandlers();
          await queue.processPending();
          expect(posts, 1);
        },
      );
    }
  }
  for (final code in [401, 403, 409, 422, 429]) {
    test(
      'foreground HTTP $code retains the same identity and queue classification',
      () async {
        status = code;
        await expectLater(perform('movement'), throwsException);
        final saved = (await actions()).single;
        expect(saved.id, sent.id);
        expect(saved.payload, sent.payload);
        expect(saved.status, switch (code) {
          401 => 'auth_blocked',
          409 => 'conflict',
          429 => 'error',
          _ => 'failed',
        });
        if (code == 429) {
          expect(
            saved.nextAttemptAt!.isAfter(
              DateTime.now().toUtc().add(const Duration(seconds: 55)),
            ),
            isTrue,
          );
        } else {
          expect(saved.permanent, isTrue);
        }
        repository.registerSyncHandlers();
        await queue.processPending();
        expect(posts, 1);
      },
    );
  }
  for (final kind in ['open', 'movement', 'close']) {
    for (final amount in [null, 'NaN', 'Infinity', -1]) {
      test(
        '$kind never replays an absent or invalid original amount: $amount',
        () async {
          repository.registerSyncHandlers();
          final now = DateTime.now().toUtc();
          final field = switch (kind) {
            'open' => 'openingAmount',
            'close' => 'closingAmount',
            _ => 'amount',
          };
          final original = PendingSyncAction(
            id: 'legacy-$kind',
            type: 'cash.$kind',
            scope: 'cash',
            companyId: company,
            userId: user,
            status: 'pending',
            attempts: 0,
            createdAt: now,
            updatedAt: now,
            payload: {
              'sessionId': shift,
              'clientSessionId': shift,
              'openedAt': now.toIso8601String(),
              'occurredAt': now.toIso8601String(),
              'offlineOpenPermit': 'synthetic-evidence',
              'deviceFingerprint': 'fixture-device',
              'operationId': 'legacy-movement',
              'type': 'IN',
              if (amount != null) field: amount,
            },
          );
          await store.putPendingAction(original, requireDatabase: true);
          await queue.processPending();
          expect(posts, 0);
          await store.closeForTesting();
          final retained = (await actions()).single;
          expect(retained.id, original.id);
          expect(retained.payload, original.payload);
          expect(retained.permanent, isTrue);
          expect(retained.isAutomaticallyRetryable, isFalse);
        },
      );
    }
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions request) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);
  @override
  void close({bool force = false}) {}
}
