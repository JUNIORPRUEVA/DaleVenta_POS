import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final cashSummaryProvider = FutureProvider<CashSummaryModel>((ref) {
  return ref.watch(cashRepositoryProvider).summary();
});

final cashMovementsProvider = FutureProvider<List<CashMovementModel>>((ref) {
  return ref.watch(cashRepositoryProvider).movements();
});

class ActiveCashSessionController
    extends StateNotifier<AsyncValue<ActiveCashSession?>> {
  ActiveCashSessionController(this.ref) : super(const AsyncLoading()) {
    refresh();
  }

  final Ref ref;

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gate = await ref.read(cashRepositoryProvider).state();
      ref.invalidate(cashGateStateProvider);
      return gate.activeSession;
    });
  }

  Future<void> open(double openingAmount, {String? note}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .read(cashRepositoryProvider)
          .openSession(openingAmount: openingAmount, note: note);
      ref.invalidate(cashGateStateProvider);
      ref.invalidate(cashSummaryProvider);
      return session;
    });
  }

  Future<void> close(double closingAmount, {String? note}) async {
    await ref
        .read(cashRepositoryProvider)
        .closeSession(closingAmount: closingAmount, note: note);
    ref.invalidate(cashGateStateProvider);
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
    state = const AsyncData(null);
  }

  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    await ref
        .read(cashRepositoryProvider)
        .addMovement(
          type: type,
          amount: amount,
          reason: reason,
          movementType: movementType,
          affectsProfit: affectsProfit,
        );
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
  }
}

final activeCashSessionControllerProvider =
    StateNotifierProvider<
      ActiveCashSessionController,
      AsyncValue<ActiveCashSession?>
    >((ref) => ActiveCashSessionController(ref));
