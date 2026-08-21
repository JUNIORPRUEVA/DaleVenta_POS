import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printing/unified_ticket_printer.dart';
import 'cash_close_ticket_printer.dart';
import 'cash_models.dart';
import 'cash_repository.dart';

final cashGateStateProvider = FutureProvider<CashGateState>((ref) {
  return ref.watch(cashRepositoryProvider).state();
});

final activeCashSessionProvider = FutureProvider<ActiveCashSession?>((
  ref,
) async {
  final state = await ref.watch(cashGateStateProvider.future);
  return state.activeSession;
});

final cashSummaryProvider = FutureProvider<CashSummaryModel?>((ref) async {
  final active = await ref.watch(activeCashSessionProvider.future);
  if (active == null) return null;
  return ref.watch(cashRepositoryProvider).summary();
});

final cashMovementsProvider = FutureProvider<List<CashMovementModel>>((
  ref,
) async {
  final active = await ref.watch(activeCashSessionProvider.future);
  if (active == null) return const [];
  return ref.watch(cashRepositoryProvider).movements();
});

class ActiveCashSessionController
    extends StateNotifier<AsyncValue<ActiveCashSession?>> {
  ActiveCashSessionController(this.ref) : super(const AsyncLoading()) {
    debugPrint(
      '[CASH_LIFECYCLE] controller CREATE id=${identityHashCode(this)}',
    );
    refresh();
  }

  final Ref ref;

  bool _opening = false;
  bool _closing = false;

  @override
  void dispose() {
    debugPrint(
      '[CASH_LIFECYCLE] controller DISPOSE id=${identityHashCode(this)}',
    );
    super.dispose();
  }

  /// Asigna el estado solo si el notifier sigue montado.
  ///
  /// Evita estructuralmente el error:
  ///   Bad state: Tried to use ActiveCashSessionController after dispose.
  /// El setter de `state` de StateNotifier lanza esa excepción (en debug)
  /// cuando se toca un notifier ya destruido, así que aquí se chequea
  /// `mounted` antes de cada asignación.
  void _setState(AsyncValue<ActiveCashSession?> value) {
    if (!mounted) return;
    state = value;
  }

  Future<void> refresh() async {
    debugPrint(
      '[CASH_LIFECYCLE] REFRESH START id=${identityHashCode(this)}',
    );
    _setState(const AsyncLoading());
    final nextState = await AsyncValue.guard(() async {
      final gate = await ref.read(cashRepositoryProvider).state();
      debugPrint(
        '[CashController] currentShift=${gate.activeSession?.shiftId}',
      );
      if (!mounted) return gate.activeSession;
      ref.invalidate(cashGateStateProvider);
      ref.invalidate(cashSummaryProvider);
      ref.invalidate(cashMovementsProvider);
      debugPrint('[CashController] refresh complete');
      return gate.activeSession;
    });
    _setState(nextState);
    debugPrint(
      '[CASH_LIFECYCLE] REFRESH END id=${identityHashCode(this)}',
    );
  }

  Future<void> open(double openingAmount, {String? note}) async {
    // Guarda anti doble-apertura: evita ejecutar dos aperturas simultáneas.
    if (_opening) return;
    _opening = true;
    try {
      debugPrint(
        '[CASH_LIFECYCLE] OPEN START id=${identityHashCode(this)}',
      );
      _setState(const AsyncLoading());
      final nextState = await AsyncValue.guard(() async {
        final session = await ref
            .read(cashRepositoryProvider)
            .openSession(openingAmount: openingAmount, note: note);
        if (!mounted) return session;
        ref.invalidate(cashGateStateProvider);
        ref.invalidate(cashSummaryProvider);
        return session;
      });
      _setState(nextState);
      debugPrint(
        '[CASH_LIFECYCLE] OPEN END id=${identityHashCode(this)}',
      );
    } finally {
      _opening = false;
    }
  }

  Future<PrintTicketResult?> close(double closingAmount, {String? note}) async {
    // Guarda anti doble-cierre: evita ejecutar dos cierres simultáneos.
    if (_closing) return null;
    _closing = true;
    try {
      debugPrint(
        '[CASH_LIFECYCLE] CLOSE START id=${identityHashCode(this)}',
      );
      final repo = ref.read(cashRepositoryProvider);
      final printer = ref.read(cashCloseTicketPrinterProvider);
      final stateBeforeClose = await repo.state();
      final summaryBeforeClose = await repo.summary();
      final movementsBeforeClose = await repo.movements();
      final snapshot = CashCloseTicketSnapshot(
        state: stateBeforeClose,
        summary: summaryBeforeClose,
        movements: movementsBeforeClose,
        closingAmount: closingAmount,
        note: note,
        capturedAt: DateTime.now(),
      );

      await repo.closeSession(closingAmount: closingAmount, note: note);
      debugPrint(
        '[CASH_LIFECYCLE] CLOSE API SUCCESS id=${identityHashCode(this)}',
      );
      if (!mounted) return null;
      return printer.printCloseTicket(snapshot);
    } finally {
      _closing = false;
    }
  }

  Future<PrintTicketResult> printCurrent() async {
    final repo = ref.read(cashRepositoryProvider);
    final printer = ref.read(cashCloseTicketPrinterProvider);
    final state = await repo.state();
    final summary = await repo.summary();
    final movements = await repo.movements();
    final snapshot = CashCloseTicketSnapshot(
      state: state,
      summary: summary,
      movements: movements,
      closingAmount: summary.expectedCash,
      note: 'Impresión previa del turno activo',
      capturedAt: DateTime.now(),
    );
    return printer.printCloseTicket(snapshot, automatic: false);
  }

  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    final repo = ref.read(cashRepositoryProvider);
    await repo.addMovement(
      type: type,
      amount: amount,
      reason: reason,
      movementType: movementType,
      affectsProfit: affectsProfit,
    );
    if (!mounted) return;
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
  }
}

final activeCashSessionControllerProvider =
    StateNotifierProvider<
      ActiveCashSessionController,
      AsyncValue<ActiveCashSession?>
    >((ref) => ActiveCashSessionController(ref));
