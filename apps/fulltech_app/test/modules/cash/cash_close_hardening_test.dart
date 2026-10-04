import 'dart:convert';

import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Blindaje del cierre de turno en el cliente:
///  - El cierre encolado SIEMPRE lleva la identidad del turno (`sessionId`).
///  - Un item de cola sin identidad se descarta (obsolete) y NUNCA toca el
///    backend (no puede cerrar "el turno abierto actual").
///  - Un replay que cierra un turno distinto NO borra la caché del turno
///    actual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  const scope = OfflineSyncScope(
    companyId: 'company-cash',
    userId: 'user-cash',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    databaseCounter += 1;
    store = OfflineStore.forTesting('cash_close_hardening_$databaseCounter.db');
    await store.clearAll();
    await OfflineStore.instance.clearCacheEntries();
  });

  tearDown(() async {
    await store.closeForTesting();
    await OfflineStore.instance.clearCacheEntries();
  });

  CashRepository buildRepository(
    Dio dio, {
    required SyncQueueService queue,
    bool registerHandlers = true,
  }) {
    final repository = CashRepository(dio, queue);
    if (registerHandlers) repository.registerSyncHandlers();
    return repository;
  }

  test('un cierre sin red se encola CON sessionId y con id determinista por turno',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.path == '/cash/sessions/close') {
          return _jsonResponse({'message': 'servicio no disponible'}, 503);
        }
        return _jsonResponse(const {}, 200);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    final repository = buildRepository(dio, queue: queue);

    await repository.closeSession(
      closingAmount: 33735.60,
      sessionId: '11111111-1111-4111-8111-111111111111',
      note: 'corte',
    );

    var actions = await store.listPendingActions(
      companyId: scope.companyId,
      userId: scope.userId,
    );
    expect(actions, hasLength(1));
    expect(actions.first.type, 'cash.close');
    expect(actions.first.id, 'cash.close:11111111-1111-4111-8111-111111111111');
    expect(
      actions.first.payload['sessionId'],
      '11111111-1111-4111-8111-111111111111',
    );
    expect(actions.first.payload['closingAmount'], 33735.60);
    expect(
      actions.first.idempotencyKey,
      'cash.close:11111111-1111-4111-8111-111111111111',
    );

    // Un segundo intento del MISMO turno no duplica el item de cola.
    await repository.closeSession(
      closingAmount: 33735.60,
      sessionId: '11111111-1111-4111-8111-111111111111',
      note: 'corte',
    );
    actions = await store.listPendingActions(
      companyId: scope.companyId,
      userId: scope.userId,
    );
    expect(actions, hasLength(1));
  });

  test('un item de cola sin sessionId se descarta (obsolete) y nunca llama al backend',
      () async {
    final requests = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        requests.add(options.path);
        return _jsonResponse(const {}, 200);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    buildRepository(dio, queue: queue);

    // Item legacy (creado por una versión antigua) SIN identidad de turno.
    await store.putPendingAction(
      PendingSyncAction(
        id: 'cash.close:legacy',
        type: 'cash.close',
        scope: 'cash',
        companyId: scope.companyId,
        userId: scope.userId,
        payload: const {'closingAmount': 33735.60},
        status: 'pending',
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await queue.processPending();

    expect(requests, isEmpty, reason: 'no debe llamar al backend');
    final actions = await store.listPendingActions(
      companyId: scope.companyId,
      userId: scope.userId,
    );
    expect(actions, hasLength(1));
    expect(actions.first.status, 'obsolete');
    expect(actions.first.permanent, isTrue);

    // No se vuelve a intentar en el siguiente ciclo.
    await queue.processPending();
    expect(requests, isEmpty);
  });

  test('un replay que cierra un turno ya cerrado NO borra la caché del turno actual',
      () async {
    final cache = LocalJsonCache();
    // El turno ACTUAL cacheado es B.
    await cache.writeMap('cash.active.session', {
      'activeSession': {
        'userId': 'user-cash',
        'shiftId': 'sid-B',
        'openedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'OPEN',
        'userName': 'Cajero',
        'businessDate': '2026-10-03',
      },
      'businessDate': '2026-10-03',
      'canOperate': true,
    });

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return _jsonResponse({'message': 'Este turno ya fue cerrado.'}, 409);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    buildRepository(dio, queue: queue);

    await store.putPendingAction(
      PendingSyncAction(
        id: 'cash.close:sid-A',
        type: 'cash.close',
        scope: 'cash',
        companyId: scope.companyId,
        userId: scope.userId,
        entityType: 'cash_session',
        entityId: 'sid-A',
        payload: const {
          'sessionId': 'sid-A',
          'closingAmount': 33735.60,
        },
        status: 'pending',
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await queue.processPending();

    final cached = await cache.readMap('cash.active.session');
    expect(
      cached?['activeSession']?['shiftId'],
      'sid-B',
      reason: 'la caché del turno actual (B) no debe perderse por un replay de A',
    );
    final actions = await store.listPendingActions(
      companyId: scope.companyId,
      userId: scope.userId,
    );
    expect(actions.first.permanent, isTrue);
  });

  test('el replay del turno correcto SÍ limpia la caché cuando coincide', () async {
    final cache = LocalJsonCache();
    await cache.writeMap('cash.active.session', {
      'activeSession': {
        'userId': 'user-cash',
        'shiftId': 'sid-A',
        'openedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'OPEN',
        'userName': 'Cajero',
        'businessDate': '2026-10-03',
      },
      'businessDate': '2026-10-03',
      'canOperate': true,
    });

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return _jsonResponse({
          'session': {'id': 'sid-A', 'status': 'CLOSED'},
          'difference': 0,
        }, 201);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    buildRepository(dio, queue: queue);

    await store.putPendingAction(
      PendingSyncAction(
        id: 'cash.close:sid-A',
        type: 'cash.close',
        scope: 'cash',
        companyId: scope.companyId,
        userId: scope.userId,
        entityType: 'cash_session',
        entityId: 'sid-A',
        payload: const {
          'sessionId': 'sid-A',
          'closingAmount': 3731.80,
        },
        status: 'pending',
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await queue.processPending();

    final cached = await cache.readMap('cash.active.session');
    expect(cached, isNull);
    final actions = await store.listPendingActions(
      companyId: scope.companyId,
      userId: scope.userId,
    );
    expect(actions, isEmpty);
  });
}

ResponseBody _jsonResponse(Object body, int status) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
