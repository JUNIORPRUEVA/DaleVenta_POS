import 'dart:convert';
import 'dart:typed_data';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.body, this.status);
  final Object body;
  final int status;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? bodyStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(
      UserModel(
        id: 'cash-user',
        companyId: 'cash-company',
        email: 'fixture@example.test',
        nombreCompleto: 'Fixture',
        telefono: '',
      ),
    );
  });
  final cases = <String, Map<String, dynamic>>{
    'missing identity': {'body': <String, dynamic>{}, 'status': 201},
    'different shift': {
      'body': {
        'session': {'id': 'shift-b', 'status': 'CLOSED', 'closingAmount': 10},
      },
      'status': 201,
    },
    'different amount': {
      'body': {
        'session': {'id': 'shift-a', 'status': 'CLOSED', 'closingAmount': 99},
      },
      'status': 201,
    },
    'not closed': {
      'body': {
        'session': {'id': 'shift-a', 'status': 'OPEN', 'closingAmount': 10},
      },
      'status': 201,
    },
    'HTTP 404': {
      'body': {'message': 'Missing shift'},
      'status': 404,
    },
    'HTTP 409': {
      'body': {'message': 'Conflict'},
      'status': 409,
    },
  };
  for (final entry in cases.entries) {
    test(
      'uncertain close (${entry.key}) remains a durable incident without confirmation',
      () async {
        final store = OfflineStore.forTesting(
          'close_confirmation_${DateTime.now().microsecondsSinceEpoch}.db',
        );
        final queue = SyncQueueService(
          store,
          scopeResolver: () async => const OfflineSyncScope(
            companyId: 'cash-company',
            userId: 'cash-user',
          ),
        );
        final adapter = _ResponseAdapter(
          entry.value['body'] as Object,
          entry.value['status'] as int,
        );
        final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'))
          ..httpClientAdapter = adapter;
        final repo = CashRepository(dio, queue, offlineStore: store);
        addTearDown(() async {
          queue.dispose();
          dio.close();
          await store.closeForTesting();
        });
        await expectLater(
          repo.closeSession(sessionId: 'shift-a', closingAmount: 10),
          throwsA(isA<CashClosePendingSyncException>()),
        );
        await store.closeForTesting();
        final persisted = (await store.listPendingActions(
          companyId: 'cash-company',
          userId: 'cash-user',
        )).single;
        expect(persisted.status, 'requires_action');
        expect(persisted.payload['sessionId'], 'shift-a');
        expect(persisted.payload['closingAmount'], 10);
        expect(persisted.permanent, isTrue);
        await queue.processPending();
        expect(
          adapter.calls,
          1,
          reason: 'uncertain closes require review, not automatic replay',
        );
      },
    );
  }
}
