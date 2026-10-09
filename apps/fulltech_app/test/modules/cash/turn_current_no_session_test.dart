import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:daleventa_pos/modules/cash/cash_turn_menu_button.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// BUG B — Regresión UAT Cafetería La Bomba ("Turno → Ver turno actual").
///
/// Estado real después de la reparación del turno legacy:
/// `GET /cash/state` → 200 con `userOpenShift = null`, `activeSession = null`,
/// `canOperate = false` (NO hay turno abierto).
///
/// Con ese estado, pulsar "Turno actual" llamaba a `GET /cash/summary` (que
/// exige turno abierto y responde 404) SIN comprobar `active == null` y SIN
/// try/catch: la excepción quedaba sin capturar, entraba al sistema global de
/// errores ("No pudimos completar la operación") y ese banner generaba además
/// el segundo error de RawTooltip (BUG A).
///
/// Reglas verificadas aquí:
/// - sin turno abierto NO se ofrecen "Turno actual" / "Hacer corte de turno";
/// - el estado no confirmado (offline) y "requiere revisión" tampoco;
/// - "Ver turno actual" nunca produce un error global (AppErrorOverlay);
/// - un turno abierto confirmado sigue funcionando (sin regresión).
const _companyId = 'f3651f62-be10-41aa-bde7-663cf990eae8';
const _userId = 'adc4bf90-41b3-4e20-99eb-f37d398200f5';
const _legacyShiftId = 'd2a540b0-a137-4665-81de-a1d2c545f8d6';
const _legacyCashboxId = '9b8464ec-90e5-4b84-acf8-671db8c4a8b9';

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

/// Forma REAL de `GET /cash/state` con un turno abierto (payload cacheado en
/// producción durante el incidente).
Map<String, dynamic> _stateWithOpenShift() => {
  'businessDate': '2026-09-16',
  'cashboxToday': null,
  'userOpenShift': {
    'id': _legacyShiftId,
    'companyId': _companyId,
    'openedByUserId': _userId,
    'userName': 'Edward vasquez',
    'openedAt': '2026-09-17T02:31:17.443Z',
    'initialAmount': '0',
    'status': 'OPEN',
    'closedAt': null,
    'cashboxDailyId': _legacyCashboxId,
    'businessDate': '2026-09-16',
    'requiresClosure': false,
  },
  'activeSession': {
    'userId': _userId,
    'cashId': _legacyCashboxId,
    'shiftId': _legacyShiftId,
    'openedAt': '2026-09-17T02:31:17.443Z',
    'status': 'OPEN',
    'userName': 'Edward vasquez',
    'businessDate': '2026-09-16',
    'terminalId': null,
    'terminalName': null,
    'terminalCode': null,
  },
  'canOperate': true,
};

/// Forma REAL de `GET /cash/state` tras la reparación: sin turno abierto.
Map<String, dynamic> _stateWithoutOpenShift() => {
  'businessDate': '2026-10-08',
  'cashboxToday': null,
  'userOpenShift': null,
  'activeSession': null,
  'canOperate': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  const scope = OfflineSyncScope(companyId: _companyId, userId: _userId);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppErrorReporter.instance.resetForTesting();
    databaseCounter += 1;
    store = OfflineStore.forTesting('turn_current_$databaseCounter.db');
    await store.clearAll();
    await OfflineStore.instance.clearCacheEntries();
  });

  tearDown(() async {
    AppErrorReporter.instance.resetForTesting();
    await store.closeForTesting();
    await OfflineStore.instance.clearCacheEntries();
  });

  CashRepository repositoryWith(
    Future<ResponseBody> Function(RequestOptions options) handler,
  ) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter(handler);
    return CashRepository(
      dio,
      SyncQueueService(store, scopeResolver: () async => scope),
    );
  }

  CashRepository noOpenShiftRepository() {
    return repositoryWith((options) async {
      if (options.path == '/cash/state') {
        return _jsonResponse(_stateWithoutOpenShift(), 200);
      }
      return _jsonResponse(const {}, 200);
    });
  }

  /// Deja correr el event loop REAL y luego pinta los frames pendientes.
  Future<void> settleAsync(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpTurnMenu(
    WidgetTester tester,
    CashRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cashRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: CashTurnMenuButton())),
        ),
      ),
    );
    // El controller revalida el estado en su constructor. La caché local usa
    // sqflite ffi (I/O real), que NO avanza con el reloj falso de los
    // testWidgets: hace falta `runAsync` para que el estado async se asiente.
    await settleAsync(tester);
  }

  Future<void> openTurnMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmountTree(WidgetTester tester) async {
    // El botón del turno tiene una animación `repeat()`: se desmonta para no
    // dejar tickers activos al terminar el test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // `sqflite` deja un timer interno de bloqueo (10 s) al cerrar una
    // transacción de la caché local; se avanza el reloj falso para que no
    // quede pendiente al final del test ("A Timer is still pending").
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('sin turno abierto "Turno actual" informa sin error y no se '
      'ofrece cerrar un turno inexistente', (tester) async {
    await pumpTurnMenu(tester, noOpenShiftRepository());
    await openTurnMenu(tester);

    expect(find.text('Abrir caja'), findsOneWidget);
    // El detalle del turno sigue accesible como información...
    expect(find.text('Turno actual'), findsOneWidget);
    // ...pero no se ofrece cerrar un turno que no existe.
    expect(find.text('Hacer corte de turno'), findsNothing);

    await tester.tap(find.text('Turno actual'));
    await tester.pump();
    // `_runAfterNavigatorSettles` espera a que el menú se cierre.
    await tester.pump(const Duration(milliseconds: 300));
    await settleAsync(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      AppErrorReporter.instance.lastError.value,
      isNull,
      reason: 'no hay turno abierto: es un estado de negocio, no un error del '
          'sistema global',
    );
    expect(find.text('No tienes un turno abierto actualmente.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountTree(tester);
  });

  testWidgets('estado no confirmado (offline) tampoco ofrece acciones sobre '
      'un turno inexistente', (tester) async {
    final repository = repositoryWith((options) async {
      if (options.path == '/cash/state') {
        return _jsonResponse(const {'message': 'servicio no disponible'}, 503);
      }
      return _jsonResponse(const {}, 200);
    });

    await pumpTurnMenu(tester, repository);
    await openTurnMenu(tester);

    expect(find.text('Estado no sincronizado'), findsOneWidget);
    expect(find.text('Turno actual'), findsOneWidget);
    expect(find.text('Hacer corte de turno'), findsNothing);
    expect(find.text('Abrir caja'), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    await unmountTree(tester);
  });

  testWidgets('CASH_SESSION_REQUIRES_REVIEW no ofrece detalle operativo normal', (
    tester,
  ) async {
    final repository = repositoryWith((options) async {
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

    await pumpTurnMenu(tester, repository);
    await openTurnMenu(tester);

    expect(find.text('Requiere revisión de caja'), findsOneWidget);
    expect(find.text('Turno actual'), findsNothing);
    expect(find.text('Hacer corte de turno'), findsNothing);
    expect(find.text('Abrir caja'), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    await unmountTree(tester);
  });

  testWidgets('con turno abierto confirmado el menú sigue ofreciendo el detalle '
      'y el corte (sin regresión)', (tester) async {
    final repository = repositoryWith((options) async {
      if (options.path == '/cash/state') {
        return _jsonResponse(_stateWithOpenShift(), 200);
      }
      return _jsonResponse(const {}, 200);
    });

    await pumpTurnMenu(tester, repository);
    await openTurnMenu(tester);

    expect(find.text('Turno actual'), findsOneWidget);
    expect(find.text('Hacer corte de turno'), findsOneWidget);
    expect(find.text('Abrir caja'), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    await unmountTree(tester);
  });

  testWidgets('carrera: el turno ya se cerró en otro dispositivo -> aviso '
      'informativo, sin error global', (tester) async {
    var stateCalls = 0;
    final repository = repositoryWith((options) async {
      if (options.path == '/cash/state') {
        stateCalls += 1;
        // Primera lectura: el turno sigue abierto. Después: ya no existe.
        return _jsonResponse(
          stateCalls == 1 ? _stateWithOpenShift() : _stateWithoutOpenShift(),
          200,
        );
      }
      if (options.path == '/cash/summary') {
        return _jsonResponse(const {
          'message': 'No encontramos un turno abierto para operar.',
        }, 404);
      }
      return _jsonResponse(const {}, 200);
    });

    await pumpTurnMenu(tester, repository);
    await openTurnMenu(tester);
    expect(find.text('Turno actual'), findsOneWidget);

    await tester.tap(find.text('Turno actual'));
    await tester.pump();
    // `_runAfterNavigatorSettles` espera a que el menú se cierre.
    await tester.pump(const Duration(milliseconds: 300));
    // GET /cash/summary -> 404 + refresh del estado (I/O real).
    await settleAsync(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      AppErrorReporter.instance.lastError.value,
      isNull,
      reason: 'ver el turno sin turno abierto es un estado de negocio, no un '
          'error del sistema global',
    );
    expect(find.text('No tienes un turno abierto actualmente.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmountTree(tester);
  });

  test('isCashNoOpenSessionError distingue "sin turno" de un fallo real', () {
    expect(isCashNoOpenSessionError(ApiException('sin turno', 404)), isTrue);
    expect(
      isCashNoOpenSessionError(
        ApiException.detailed(
          message: 'servicio no disponible',
          code: 503,
          type: ApiErrorType.server,
          displayCode: 'SERVER_ERROR',
        ),
      ),
      isFalse,
    );
    expect(isCashNoOpenSessionError(StateError('otro')), isFalse);
  });

  test('summary() propaga el 404 como estado "sin turno abierto"', () async {
    final repository = repositoryWith((options) async {
      if (options.path == '/cash/summary') {
        return _jsonResponse(const {
          'message': 'No encontramos un turno abierto para operar.',
        }, 404);
      }
      return _jsonResponse(const {}, 200);
    });

    Object? captured;
    try {
      await repository.summary();
    } catch (error) {
      captured = error;
    }

    expect(captured, isA<ApiException>());
    expect(isCashNoOpenSessionError(captured), isTrue);
    expect(
      (captured as ApiException).message,
      contains('No encontramos un turno abierto'),
    );
  });
}
