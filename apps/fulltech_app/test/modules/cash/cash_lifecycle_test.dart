import 'dart:async';
import 'dart:io';

import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio fake que NO toca la red. Controlable para simular operaciones
/// async en vuelo (Completers).
class _FakeCashRepository implements CashRepository {
  Future<ActiveCashSession> Function()? openSessionOverride;
  Future<CashGateState> Function()? stateOverride;
  Future<CashSummaryModel> Function()? summaryOverride;
  Future<List<CashMovementModel>> Function()? movementsOverride;
  Future<void> Function()? closeSessionOverride;

  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() {
    final override = stateOverride;
    if (override != null) return override();
    return Future.value(
      const CashGateState(businessDate: '2026-08-20', canOperate: false),
    );
  }

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) {
    final override = openSessionOverride;
    if (override != null) return override();
    return Future.value(_session);
  }

  @override
  Future<void> closeSession({
    required double closingAmount,
    required String sessionId,
    String? note,
  }) {
    final override = closeSessionOverride;
    if (override != null) return override();
    return Future.value();
  }

  @override
  Future<CashSummaryModel> summary() {
    final override = summaryOverride;
    if (override != null) return override();
    return Future.value(_summary);
  }

  @override
  Future<List<CashMovementModel>> movements() {
    final override = movementsOverride;
    if (override != null) return override();
    return Future.value(const []);
  }

  @override
  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {}

  @override
  Future<List<CashSessionHistoryModel>> closedSessions() {
    throw UnimplementedError('closedSessions');
  }

  @override
  Future<CashSessionDetailModel> sessionDetail(String id) {
    throw UnimplementedError('sessionDetail');
  }

  @override
  Future<ActiveCashSession?> cachedActiveSession() async => null;

  @override
  Future<List<CashMovementModel>> movementHistory({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int take = 160,
  }) async => const [];
}

class _FakeCashCloseTicketPrinter implements CashCloseTicketPrinter {
  @override
  Future<PrintTicketResult> printCloseTicket(
    CashCloseTicketSnapshot snapshot, {
    bool automatic = true,
  }) async {
    return const PrintTicketResult(success: true, message: 'Impreso');
  }

  @override
  Future<PrintTicketResult> printHistoryTicket(CashSessionHistoryModel row) {
    throw UnimplementedError('printHistoryTicket');
  }

  @override
  List<String> buildLines(CashCloseTicketSnapshot snapshot) => const [];

  @override
  List<String> buildHistoryLines(CashSessionHistoryModel row) => const [];
}

/// Impresora que falla SIEMPRE al imprimir el cierre. Sirve para verificar que
/// un fallo de impresión posterior al cierre NO dispara un segundo cierre.
class _ThrowingCashCloseTicketPrinter implements CashCloseTicketPrinter {
  @override
  Future<PrintTicketResult> printCloseTicket(
    CashCloseTicketSnapshot snapshot, {
    bool automatic = true,
  }) async {
    throw Exception('impresora sin papel');
  }

  @override
  Future<PrintTicketResult> printHistoryTicket(CashSessionHistoryModel row) {
    throw UnimplementedError('printHistoryTicket');
  }

  @override
  List<String> buildLines(CashCloseTicketSnapshot snapshot) => const [];

  @override
  List<String> buildHistoryLines(CashSessionHistoryModel row) => const [];
}

final _session = ActiveCashSession(
  userId: 'user-1',
  shiftId: 'shift-1',
  openedAt: DateTime.utc(2026, 8, 20, 10),
  status: 'OPEN',
  userName: 'Cajero',
  businessDate: '2026-08-20',
);

const _summary = CashSummaryModel(
  openingAmount: 0,
  totalSales: 0,
  totalExpenses: 0,
  totalWithdrawals: 0,
  cashInManual: 0,
  cashOutManual: 0,
  creditAbonos: 0,
  creditSalesTotal: 0,
  creditInitialCash: 0,
  creditInitialTransfer: 0,
  creditBalanceTotal: 0,
  creditPaymentCash: 0,
  creditPaymentTransfer: 0,
  salesCashTotal: 0,
  salesTransferTotal: 0,
  refundsCash: 0,
  expectedCash: 100,
  totalTickets: 0,
  totalRefunds: 0,
  categorySummary: [],
);

ProviderContainer _buildContainer(_FakeCashRepository repo) {
  return ProviderContainer(
    overrides: [
      cashRepositoryProvider.overrideWithValue(repo),
      cashCloseTicketPrinterProvider.overrideWithValue(
        _FakeCashCloseTicketPrinter(),
      ),
    ],
  );
}

void main() {
  group('ActiveCashSessionController lifecycle', () {
    test('abrir turno funciona y deja el turno abierto', () async {
      final repo = _FakeCashRepository();
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container
          .read(activeCashSessionControllerProvider.notifier);
      await controller.open(1000);

      final state = container.read(activeCashSessionControllerProvider);
      expect(state.valueOrNull?.isOpen, isTrue);
    });

    test('cerrar turno cierra y sigue estable', () async {
      final repo = _FakeCashRepository();
      // Para cerrar un turno debe existir un turno abierto identificable.
      repo.stateOverride = () async => CashGateState(
            businessDate: '2026-08-20',
            canOperate: true,
            activeSession: _session,
          );
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container
          .read(activeCashSessionControllerProvider.notifier);
      final result = await controller.close(1000);

      expect(result?.success, isTrue);
    });

    test(
      'usar un controller ya dispuesto NO lanza Bad state '
      '(referencia obsoleta después de invalidar)', () async {
        final repo = _FakeCashRepository();
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        // Referencia "vieja" capturada ANTES de que Riverpod lo disponga
        // (equivale a capturar el notifier antes de un showDialog).
        final stale = container.read(
          activeCashSessionControllerProvider.notifier,
        );

        // Riverpod invalida (destruye) el controller, como hacía el realtime.
        container.invalidate(activeCashSessionControllerProvider);
        expect(stale.mounted, isFalse);

        // Llamar operaciones sobre la referencia muerta debe ser seguro.
        await stale.open(1000);
        await stale.refresh();
        await stale.close(1000);

        // El controller fresco sigue funcionando.
        final fresh = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        expect(fresh.mounted, isTrue);
        await fresh.open(1000);
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);
      },
    );

    test(
      'operación open en vuelo sobrevive al dispose/rebuild sin tocar un '
      'notifier muerto', () async {
        final repo = _FakeCashRepository();
        final openCompleter = Completer<ActiveCashSession>();
        repo.openSessionOverride = () => openCompleter.future;
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );

        // Arranca open() pero aún no ha terminado la llamada al backend.
        final openFuture = controller.open(1000);

        // Mientras está en vuelo, se invalida el provider (dispose + rebuild).
        container.invalidate(activeCashSessionControllerProvider);

        // El backend termina la operación.
        openCompleter.complete(_session);

        // NO debe lanzar 'Bad state: Tried to use ... after dispose'.
        await openFuture;
      },
    );

    test(
      'refresh en vuelo que falla después de dispose no toca state/ref muerto',
      () async {
        final repo = _FakeCashRepository();
        final stateCompleter = Completer<CashGateState>();
        repo.stateOverride = () => stateCompleter.future;
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        final refreshFuture = controller.refresh(silent: true);

        container.invalidate(activeCashSessionControllerProvider);
        expect(controller.mounted, isFalse);

        stateCompleter.completeError(Exception('red caida tardia'));

        await refreshFuture;
      },
    );

    test('doble apertura simultánea solo ejecuta una', () async {
      final repo = _FakeCashRepository();
      var calls = 0;
      final openCompleter = Completer<ActiveCashSession>();
      repo.openSessionOverride = () {
        calls += 1;
        return openCompleter.future;
      };
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      final first = controller.open(1000);
      final second = controller.open(2000);

      openCompleter.complete(_session);
      await Future.wait([first, second]);

      expect(calls, 1);
    });

    test('doble cierre simultáneo solo ejecuta uno', () async {
      final repo = _FakeCashRepository();
      repo.stateOverride = () async => CashGateState(
            businessDate: '2026-08-20',
            canOperate: true,
            activeSession: _session,
          );
      var calls = 0;
      final closeCompleter = Completer<void>();
      repo.closeSessionOverride = () {
        calls += 1;
        return closeCompleter.future;
      };
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      final first = controller.close(1000);
      final second = controller.close(2000);

      closeCompleter.complete();
      await Future.wait([first, second]);

      expect(calls, 1);
    });

    test('fallo en open() libera la guarda y permite reintentar', () async {
      final repo = _FakeCashRepository();
      var calls = 0;
      repo.openSessionOverride = () {
        calls += 1;
        if (calls == 1) throw Exception('red caida');
        return Future.value(_session);
      };
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      // Primer intento falla: la guarda debe liberarse (finally).
      await controller.open(1000);
      // Reintento debe funcionar.
      await controller.open(1000);

      expect(calls, 2);
      expect(
        container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen,
        isTrue,
      );
    });

    test('fallo en close() libera la guarda y permite reintentar', () async {
      final repo = _FakeCashRepository();
      repo.stateOverride = () async => CashGateState(
            businessDate: '2026-08-20',
            canOperate: true,
            activeSession: _session,
          );
      var calls = 0;
      repo.closeSessionOverride = () {
        calls += 1;
        if (calls == 1) throw Exception('red caida');
        return Future.value();
      };
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      // Primer cierre falla y propaga el error; la guarda se libera (finally).
      await expectLater(
        controller.close(1000),
        throwsA(isA<Exception>()),
      );
      // Reintento debe funcionar.
      final result = await controller.close(1000);

      expect(calls, 2);
      expect(result?.success, isTrue);
    });

    test('un fallo de impresión tras cerrar NO dispara un segundo cierre', () async {
      final repo = _FakeCashRepository();
      repo.stateOverride = () async => CashGateState(
            businessDate: '2026-08-20',
            canOperate: true,
            activeSession: _session,
          );
      var closeCalls = 0;
      repo.closeSessionOverride = () {
        closeCalls += 1;
        return Future.value();
      };
      final container = ProviderContainer(
        overrides: [
          cashRepositoryProvider.overrideWithValue(repo),
          cashCloseTicketPrinterProvider.overrideWithValue(
            _ThrowingCashCloseTicketPrinter(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      // El cierre ya se aplicó en backend; la impresión falla después.
      await expectLater(controller.close(1000), throwsA(isA<Exception>()));
      // El backend sólo se llamó UNA vez: imprimir no vuelve a cerrar.
      expect(closeCalls, 1);
    });

    test('tras invalidar, la instancia vieja y la nueva no comparten estado',
        () async {
          final repo = _FakeCashRepository();
          final container = _buildContainer(repo);
          addTearDown(container.dispose);

          final stale = container.read(
            activeCashSessionControllerProvider.notifier,
          );
          container.invalidate(activeCashSessionControllerProvider);
          final fresh = container.read(
            activeCashSessionControllerProvider.notifier,
          );

          // Son instancias distintas: el estado de la vieja jamás puede
          // escribirse sobre la nueva (equivale a Empresa A vs Empresa B).
          expect(identical(stale, fresh), isFalse);
          expect(stale.mounted, isFalse);
          expect(fresh.mounted, isTrue);

          // open() sobre la instancia vieja es seguro (no lanza) y NO puede
          // escribir sobre la nueva: cada una mantiene su propio estado.
          await stale.open(1000);

          // La instancia nueva conserva su propio estado (null según el fake).
          await pumpEventQueue();
          final freshState = container.read(
            activeCashSessionControllerProvider,
          );
          expect(freshState.valueOrNull, isNull);
        });

    test(
      'multi-dispositivo: dispositivo B refresca y ve el turno abierto por A',
      () async {
        final repo = _FakeCashRepository();
        // Dispositivo B arranca con caja cerrada (baseline del fake).
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        // Dispositivo A abre el turno → backend ahora responde ABIERTO.
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: true,
              activeSession: _session,
            );
        await controller.refresh();

        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.shiftId, 'shift-1');
        expect(container.read(cashStateUnverifiedProvider), isFalse);
      },
    );

    test(
      'multi-dispositivo: A cierra → B hace refresh silencioso y ve CERRADO',
      () async {
        final repo = _FakeCashRepository();
        // B arranca con turno abierto.
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: true,
              activeSession: _session,
            );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);

        // A cierra el turno → backend responde CERRADO (activo null).
        repo.stateOverride = () async => const CashGateState(
              businessDate: '2026-08-20',
              canOperate: false,
            );
        await controller.refresh(silent: true);

        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull, isNull);
        expect(container.read(cashStateUnverifiedProvider), isFalse);
      },
    );

    test(
      'error de red al revalidar NO convierte un turno abierto en "cerrado"',
      () async {
        final repo = _FakeCashRepository();
        // B tiene el turno abierto confirmado.
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: true,
              activeSession: _session,
            );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);

        // Ahora hay fallo de red al revalidar: se conserva el snapshot y se
        // marca "estado no sincronizado" (regla #39: error != cerrado).
        repo.stateOverride = () async => throw Exception('red caida');
        await controller.refresh(silent: true);

        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);
        expect(container.read(cashStateUnverifiedProvider), isTrue);
      },
    );

    test(
      'estado de caché (fallo de red) se muestra como "no sincronizado", '
      'nunca como confirmado', () async {
        final repo = _FakeCashRepository();
        // El repo cae a caché: devuelve turno abierto pero marcado fromCache.
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: true,
              activeSession: _session,
              fromCache: true,
            );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();

        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);
        expect(container.read(cashStateUnverifiedProvider), isTrue);
      },
    );

    test(
      'cerrar un turno ya cerrado por otro dispositivo converge a CERRADO',
      () async {
        final repo = _FakeCashRepository();
        var closed = false;
        // B cree que está abierto (snapshot viejo).
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: !closed,
              activeSession: closed ? null : _session,
            );
        repo.closeSessionOverride = () {
          // A ya lo cerró: el backend responde "ya cerrado".
          closed = true;
          throw const CashSessionAlreadyClosedException(
            'El turno ya estaba cerrado.',
          );
        };
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);

        // B intenta cerrar: no debe quedarse mostrando el estado viejo.
        final result = await controller.close(1000);
        expect(result, isNull);
        expect(closed, isTrue);
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull, isNull);
      },
    );

    test(
      'abrir un turno ya abierto por otro dispositivo NO crea uno nuevo: '
      'el backend devuelve el existente y la UI converge', () async {
        final repo = _FakeCashRepository();
        // B cree que está cerrado; A ya abrió el turno.
        repo.openSessionOverride = () async => _session;
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.open(1000);

        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.shiftId, 'shift-1');
        expect(container.read(cashStateUnverifiedProvider), isFalse);
      },
    );

    test(
      'cambio de empresa/logout: nueva instancia revalida y no hereda el '
      'snapshot anterior', () async {
        final repo = _FakeCashRepository();
        // Empresa A: turno abierto.
        repo.stateOverride = () async => CashGateState(
              businessDate: '2026-08-20',
              canOperate: true,
              activeSession: _session,
            );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        // Sesión Empresa A con turno abierto.
        final first = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await first.refresh();
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull?.isOpen, isTrue);

        // Empresa B (equivale a logout+login): se invalida y se revalida.
        container.invalidate(activeCashSessionControllerProvider);
        repo.stateOverride = () async => const CashGateState(
              businessDate: '2026-08-20',
              canOperate: false,
            );
        final second = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await second.refresh();

        expect(identical(first, second), isFalse);
        expect(container.read(activeCashSessionControllerProvider)
            .valueOrNull, isNull);
      },
    );
  });

  // Regresión del bug REAL de login (UAT Windows):
  //   StateError: Bad state: Tried to use ActiveCashSessionController after
  //   'dispose' was called. Consider checking `mounted`.
  //
  // Disparador real: `OperationsDataRefreshService._resetCashState()` invalida
  // `activeCashSessionControllerProvider` cuando `authStateProvider` pasa de
  // autenticado → no autenticado (login/logout/re-bootstrap). Si en ese momento
  // había un `refresh()` en vuelo y el camino de error volvía a leer `state`
  // después de escribir `cashStateUnverifiedProvider`, el notifier ya estaba
  // dispuesto y la lectura lanzaba StateError.
  group('cash controller login dispose race (regression)', () {
    test(
      'login: dispose por cambio de auth durante el refresh inicial no vuelve '
      'a leer ni escribir state (no StateError)',
      () async {
        final repo = _FakeCashRepository();
        final gateCompleter = Completer<CashGateState>();
        repo.stateOverride = () => gateCompleter.future;
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        // El constructor del controller ya disparó refresh(); sigue en vuelo.
        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );

        // Equivale a OperationsDataRefreshService._resetCashState() cuando auth
        // pasa de autenticado → no autenticado durante el bootstrap de login.
        container.invalidate(activeCashSessionControllerProvider);
        expect(controller.mounted, isFalse);

        // El backend responde tarde y con error (red caída durante el login).
        // Este es el camino que en el código antiguo hacía
        // `... .state = true; final previous = state;` sobre un notifier muerto.
        gateCompleter.completeError(Exception('red caida durante login'));

        // NO debe lanzar 'Bad state: Tried to use ActiveCashSessionController
        // after dispose was called.'
        await pumpEventQueue();

        expect(controller.mounted, isFalse);
        // La instancia muerta tampoco debe haber escrito el flag de estado no
        // sincronizado (lo compartiría con la sesión/empresa siguiente).
        expect(container.read(cashStateUnverifiedProvider), isFalse);
      },
    );

    test('login: open en vuelo + dispose no escribe el flag desde la instancia '
        'muerta', () async {
      final repo = _FakeCashRepository();
      final openCompleter = Completer<ActiveCashSession>();
      repo.openSessionOverride = () => openCompleter.future;
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        activeCashSessionControllerProvider.notifier,
      );
      final openFuture = controller.open(1000);

      // Dispose mientras la apertura está en el backend.
      container.invalidate(activeCashSessionControllerProvider);
      openCompleter.complete(_session);

      await openFuture;
      expect(container.read(cashStateUnverifiedProvider), isFalse);
    });

    test(
      'invariante estructural: refresh() captura el snapshot antes de mutar y '
      'no re-lee state después',
      () {
        final source = File(
          'lib/modules/cash/cash_providers.dart',
        ).readAsStringSync();
        final start = source.indexOf(
          'Future<void> refresh({bool silent = false})',
        );
        expect(start, greaterThanOrEqualTo(0));
        final end = source.indexOf('Future<void> open(', start);
        expect(end, greaterThan(start));
        final body = source.substring(start, end);

        // Marcador agnóstico a la implementación: tanto el helper
        // `_markCashStateUnverified(...)` como una escritura directa
        // `ref.read(cashStateUnverifiedProvider.notifier).state = ...` cuentan
        // como mutación de otro provider dentro de refresh().
        final mutationIndexes = <int>[
          body.indexOf('_markCashStateUnverified('),
          body.indexOf('cashStateUnverifiedProvider'),
        ].where((index) => index >= 0).toList();
        final snapshot = body.indexOf('= state;');
        final mountedGuard = body.indexOf('if (!mounted) return;');
        final firstMutation = mutationIndexes.isEmpty
            ? -1
            : mutationIndexes.reduce((a, b) => a < b ? a : b);

        expect(
          snapshot,
          greaterThanOrEqualTo(0),
          reason: 'refresh() debe capturar un snapshot local de state',
        );
        expect(
          mountedGuard,
          lessThan(snapshot),
          reason: 'mounted debe comprobarse antes de leer state',
        );
        expect(
          snapshot,
          lessThan(firstMutation),
          reason:
              'el snapshot debe capturarse ANTES de escribir en '
              'cashStateUnverifiedProvider: mutar otro provider puede '
              'invalidar/dispose este controller (login/logout) y leer state '
              'después lanza "Tried to use ... after dispose".',
        );
        expect(
          body.indexOf('= state;', snapshot + 1),
          -1,
          reason: 'refresh() no debe volver a leer state tras mutar',
        );
      },
    );
  });

  // Regresión UAT Cafetería La Bomba (caja): el backend respondió 409
  // CASH_SESSION_REQUIRES_REVIEW (turno legacy/ambiguo) porque SÍ contestó, así
  // que la UI no debe decir "Sin conexión" ni marcar el estado como no
  // sincronizado por red.
  group('cash controller: estado que requiere revisión', () {
    test(
      'un gate requiresReview se expone como revisión y NO como "no '
      'sincronizado"',
      () async {
        final repo = _FakeCashRepository();
        repo.stateOverride = () async => const CashGateState(
          businessDate: '2026-10-03',
          canOperate: false,
          requiresReview: true,
          reviewMessage:
              'Este turno abierto necesita revisión antes de operar. '
              'Contacta a un administrador.',
        );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();

        expect(container.read(cashStateRequiresReviewProvider), isTrue);
        expect(
          container.read(cashStateReviewMessageProvider),
          contains('revisión'),
        );
        expect(
          container.read(cashStateUnverifiedProvider),
          isFalse,
          reason: 'fue una decisión del servidor, no un fallo de red',
        );
        expect(
          container.read(activeCashSessionControllerProvider).valueOrNull,
          isNull,
        );
      },
    );
  });
}
