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
    refresh();
  }

  final Ref ref;

  Future<void> refresh() async {
    debugPrint('[CashController] refresh start');
    state = const AsyncLoading();
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
    if (!mounted) return;
    state = nextState;
  }

  Future<void> open(double openingAmount, {String? note}) async {
    state = const AsyncLoading();
    final nextState = await AsyncValue.guard(() async {
      final session = await ref
          .read(cashRepositoryProvider)
          .openSession(openingAmount: openingAmount, note: note);
      if (!mounted) return session;
      ref.invalidate(cashGateStateProvider);
      ref.invalidate(cashSummaryProvider);
      return session;
    });
    if (!mounted) return;
    state = nextState;
  }

  Future<PrintTicketResult?> close(double closingAmount, {String? note}) async {
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
    if (!mounted) return null;
    return printer.printCloseTicket(snapshot);
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
