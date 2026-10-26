import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Blindaje multiusuario (cliente): turno vencido consultable/cerrable y
/// fecha real de la operación en los movimientos de caja.
///
/// Contrato del backend nuevo:
///  - `GET /cash/state` responde 200 con `activeSession` + `staleBusinessDate`
///    + `requiresClosure` + `canOperate: false` cuando el turno abierto es de un
///    día comercial anterior (antes era 409 y el usuario quedaba sin acción).
///  - `POST /cash/movements` acepta `occurredAt` (fecha real de la operación)
///    para no depender del instante de sincronización.
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

Map<String, dynamic> _staleStatePayload() => {
  'businessDate': '2026-10-26',
  'canOperate': false,
  'staleBusinessDate': true,
  'requiresClosure': true,
  'requiresReview': false,
  'activeSession': {
    'shiftId': 'e27d77e1-2957-45e4-bad8-2aea2559c5cf',
    'status': 'OPEN',
    'openedAt': '2026-10-19T23:26:04.382Z',
    'businessDate': '2026-10-19',
    'userName': 'Antonio Lauture',
    'initialAmount': 0,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  const scope = OfflineSyncScope(
    companyId: 'company-antonio',
    userId: 'user-antonio',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    databaseCounter += 1;
    store = OfflineStore.forTesting('cash_stale_shift_$databaseCounter.db');
    await store.clearAll();
  });

  tearDown(() async {
    await store.closeForTesting();
  });

  test(
    'turno vencido: se expone como cerrable (activeSession) y NO operativo',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.path == '/cash/state') {
            return _jsonResponse(_staleStatePayload(), 200);
          }
          return _jsonResponse(const {}, 200);
        });
      final queue = SyncQueueService(store, scopeResolver: () async => scope);
      final repository = CashRepository(dio, queue);

      final gate = await repository.state();

      expect(gate.staleBusinessDate, isTrue);
      expect(gate.requiresClosure, isTrue);
      expect(gate.canOperate, isFalse);
      expect(
        gate.activeSession?.shiftId,
        'e27d77e1-2957-45e4-bad8-2aea2559c5cf',
        reason: 'sin la sesión la UI no podría ofrecer "Cerrar turno"',
      );
      expect(gate.requiresReview, isFalse);
    },
  );

  test('un turno del día no se marca como vencido', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.path == '/cash/state') {
          return _jsonResponse(const {
            'businessDate': '2026-10-26',
            'canOperate': true,
            'staleBusinessDate': false,
            'requiresClosure': false,
            'activeSession': {
              'shiftId': 'shift-hoy',
              'status': 'OPEN',
              'openedAt': '2026-10-26T13:08:26.249Z',
              'businessDate': '2026-10-26',
            },
          }, 200);
        }
        return _jsonResponse(const {}, 200);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    final repository = CashRepository(dio, queue);

    final gate = await repository.state();

    expect(gate.staleBusinessDate, isFalse);
    expect(gate.canOperate, isTrue);
  });

  test('el movimiento de caja envía occurredAt (fecha real de la operación)',
      () async {
    Map<String, dynamic>? captured;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.path == '/cash/movements') {
          captured = Map<String, dynamic>.from(options.data as Map);
          return _jsonResponse(const {'id': 'movement-1'}, 201);
        }
        return _jsonResponse(const {}, 200);
      });
    final queue = SyncQueueService(store, scopeResolver: () async => scope);
    final repository = CashRepository(dio, queue);

    await repository.addMovement(
      type: 'IN',
      amount: 25,
      reason: 'fondo',
      sessionId: 'e27d77e1-2957-45e4-bad8-2aea2559c5cf',
    );

    expect(captured, isNotNull);
    expect(captured!['sessionId'], 'e27d77e1-2957-45e4-bad8-2aea2559c5cf');
    expect(
      captured!['occurredAt'],
      isA<String>(),
      reason: 'el backend valida la ventana del turno con la fecha de operación',
    );
    expect(DateTime.parse(captured!['occurredAt'] as String).isUtc, isTrue);
  });
}
