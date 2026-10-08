import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regresión UAT Cafetería La Bomba (caja):
///
/// `GET /cash/state` responde **409 CASH_SESSION_REQUIRES_REVIEW** porque el
/// backend detectó un turno abierto legacy/ambiguo (protección deliberada en
/// `cash.service.ts::rejectAmbiguousLegacyOpenSession`).
///
/// Eso NO es un fallo de red: el cliente debe reportarlo como "requiere
/// revisión de caja" (y bloquear "Abrir caja"), nunca como "Sin conexión" ni
/// cayendo a caché como si fuera un problema de conectividad.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> data, int status) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  const scope = OfflineSyncScope(
    companyId: 'company-la-bomba',
    userId: 'user-la-bomba',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    databaseCounter += 1;
    store = OfflineStore.forTesting('cash_requires_review_$databaseCounter.db');
    await store.clearAll();
    await OfflineStore.instance.clearCacheEntries();
  });

  tearDown(() async {
    await store.closeForTesting();
    await OfflineStore.instance.clearCacheEntries();
  });

  test(
    '409 CASH_SESSION_REQUIRES_REVIEW se reporta como revisión de caja, '
    'no como "sin conexión"/caché',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.path == '/cash/state') {
            return _jsonResponse(const {
              'code': 'CASH_SESSION_REQUIRES_REVIEW',
              'errorCode': 'CASH_SESSION_REQUIRES_REVIEW',
              'message':
                  'Este turno abierto necesita revisión antes de operar. '
                  'Contacta a un administrador.',
            }, 409);
          }
          return _jsonResponse(const {}, 200);
        });
      final queue = SyncQueueService(store, scopeResolver: () async => scope);
      final repository = CashRepository(dio, queue);

      // No debe lanzar: el servidor SÍ respondió.
      final gate = await repository.state();

      expect(gate.requiresReview, isTrue);
      expect(
        gate.fromCache,
        isFalse,
        reason: 'fue una decisión del servidor, no un fallo de red',
      );
      expect(gate.activeSession, isNull);
      expect(gate.canOperate, isFalse);
      expect(gate.reviewMessage, contains('revisión'));
      expect(repository.lastStateFromCache, isFalse);
    },
  );

  test(
    'un 503 real de /cash/state sigue usando el snapshot local como no '
    'verificado (comportamiento preservado)',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.path == '/cash/state') {
            return _jsonResponse(const {'message': 'servicio no disponible'}, 503);
          }
          return _jsonResponse(const {}, 200);
        });
      final queue = SyncQueueService(store, scopeResolver: () async => scope);
      final repository = CashRepository(dio, queue);
      await LocalJsonCache().writeMap('cash.active.session', const {
        'activeSession': {
          'userId': 'user-la-bomba',
          'shiftId': '11111111-1111-4111-8111-111111111111',
          'openedAt': '2026-10-03T12:00:00.000Z',
          'status': 'OPEN',
          'userName': 'Cajero',
          'businessDate': '2026-10-03',
        },
        'businessDate': '2026-10-03',
        'canOperate': true,
      });

      final gate = await repository.state();

      expect(gate.fromCache, isTrue);
      expect(gate.requiresReview, isFalse);
      expect(repository.lastStateFromCache, isTrue);
    },
  );
}
