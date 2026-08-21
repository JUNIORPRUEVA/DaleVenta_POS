import 'dart:async';

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
  });
}
