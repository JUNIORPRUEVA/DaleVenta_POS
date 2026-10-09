import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/trace_log.dart';
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

/// `true` cuando el estado actual del turno provino de la caché local (fallo
/// de red transitorio) o de un error de revalidación: NO está confirmado contra
/// el backend. La UI debe mostrarlo como "estado no sincronizado", nunca como
/// un turno abierto/cerrado garantizado.
final cashStateUnverifiedProvider = StateProvider<bool>((ref) => false);

/// `true` cuando el backend rechazó el estado de caja porque existe un turno
/// abierto legacy/ambiguo que necesita revisión (409
/// `CASH_SESSION_REQUIRES_REVIEW`). Es una decisión del servidor, NO un fallo de
/// red: la UI debe decirlo así y bloquear "Abrir caja".
final cashStateRequiresReviewProvider = StateProvider<bool>((ref) => false);
final cashStateReviewMessageProvider = StateProvider<String?>((ref) => null);

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
  int _refreshGeneration = 0;

  @override
  void dispose() {
    _refreshGeneration++;
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

  bool _canApplyRefresh(int generation) {
    return mounted && generation == _refreshGeneration;
  }

  void _markCashStateUnverified(bool value) {
    if (!mounted) return;
    ref.read(cashStateUnverifiedProvider.notifier).state = value;
  }

  void _markCashStateRequiresReview(bool value, String? message) {
    if (!mounted) return;
    ref.read(cashStateRequiresReviewProvider.notifier).state = value;
    ref.read(cashStateReviewMessageProvider.notifier).state = value
        ? message
        : null;
  }

  void _invalidateCashReadsAfterRefresh() {
    if (!mounted) return;
    ref.invalidate(cashGateStateProvider);
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
  }

  /// Revalida el turno contra el backend (fuente de verdad).
  ///
  /// - `silent: false` (acciones explícitas): muestra loading mientras consulta.
  /// - `silent: true` (reconciliación de fondo: resume, reconexión realtime,
  ///   polling, navegación): conserva el snapshot visual actual para no
  ///   provocar parpadeo; al terminar queda el estado real del backend.
  ///
  /// Regla #39: un error de red/API nunca se traduce a "turno cerrado", y un
  /// snapshot de caché se marca como "no sincronizado" ([cashStateUnverifiedProvider]).
  Future<void> refresh({bool silent = false}) async {
    if (!mounted) return;
    final generation = ++_refreshGeneration;
    final previousState = state;
    debugPrint('[CASH_LIFECYCLE] REFRESH START id=${identityHashCode(this)}');
    TraceLog.log('cash', 'cash.refresh silent=$silent');
    if (!silent) _setState(const AsyncLoading());

    AsyncValue<ActiveCashSession?> nextState;
    try {
      final gate = await ref.read(cashRepositoryProvider).state();
      if (!_canApplyRefresh(generation)) return;
      debugPrint(
        '[CashController] currentShift=${gate.activeSession?.shiftId}',
      );
      // Estado verificado contra el backend (o snapshot local marcado como
      // no verificado si vino de caché por fallo de red).
      _markCashStateUnverified(gate.fromCache);
      if (!_canApplyRefresh(generation)) return;
      _markCashStateRequiresReview(gate.requiresReview, gate.reviewMessage);
      if (!_canApplyRefresh(generation)) return;
      _invalidateCashReadsAfterRefresh();
      debugPrint('[CashController] refresh complete');
      nextState = AsyncValue.data(gate.activeSession);
    } catch (error, stack) {
      if (!_canApplyRefresh(generation)) return;
      // Un fallo de red/API NO debe convertir un turno abierto conocido en
      // "cerrado" ni viceversa: se conserva el último snapshot y se marca como
      // no sincronizado. Solo si nunca hubo dato se expone el error.
      _markCashStateUnverified(true);
      if (!_canApplyRefresh(generation)) return;
      if (previousState.hasValue) {
        nextState = previousState;
      } else {
        nextState = AsyncValue.error(error, stack);
      }
    }
    if (!_canApplyRefresh(generation)) return;
    _setState(nextState);
    debugPrint('[CASH_LIFECYCLE] REFRESH END id=${identityHashCode(this)}');
  }

  Future<void> open(double openingAmount, {String? note}) async {
    if (!mounted) return;
    // Guarda anti doble-apertura: evita ejecutar dos aperturas simultáneas.
    if (_opening) return;
    _opening = true;
    try {
      debugPrint('[CASH_LIFECYCLE] OPEN START id=${identityHashCode(this)}');
      TraceLog.log('cash', 'cash.open.start');
      _setState(const AsyncLoading());
      final nextState = await AsyncValue.guard(() async {
        final session = await ref
            .read(cashRepositoryProvider)
            .openSession(openingAmount: openingAmount, note: note);
        if (!mounted) return session;
        _invalidateCashReadsAfterRefresh();
        // La apertura se confirmó contra el backend: el estado ya no es un
        // snapshot no verificado.
        _markCashStateUnverified(false);
        TraceLog.log('cash', 'cash.open.done shiftId=${session.shiftId}');
        return session;
      });
      if (!mounted) return;
      _setState(nextState);
      debugPrint('[CASH_LIFECYCLE] OPEN END id=${identityHashCode(this)}');
    } finally {
      _opening = false;
    }
  }

  Future<PrintTicketResult?> close(double closingAmount, {String? note}) async {
    if (!mounted) return null;
    // Guarda anti doble-cierre: evita ejecutar dos cierres simultáneos.
    if (_closing) return null;
    _closing = true;
    try {
      debugPrint('[CASH_LIFECYCLE] CLOSE START id=${identityHashCode(this)}');
      TraceLog.log('cash', 'cash.close.start');
      final repo = ref.read(cashRepositoryProvider);
      final printer = ref.read(cashCloseTicketPrinterProvider);
      final stateBeforeClose = await repo.state();
      if (!mounted) return null;
      final summaryBeforeClose = await repo.summary();
      if (!mounted) return null;
      final movementsBeforeClose = await repo.movements();
      if (!mounted) return null;
      // Identidad del turno que estaba abierto cuando el usuario inició el
      // cierre. Se fija AQUÍ y se envía al backend, de modo que un replay
      // offline nunca cierre un turno posterior.
      final sessionId = stateBeforeClose.activeSession?.shiftId.trim() ?? '';
      if (sessionId.isEmpty) {
        // No hay un turno abierto identificable: no se cierra NADA (jamás un
        // turno posterior) y la UI converge a CERRADO, igual que cuando el
        // turno ya fue cerrado por otro dispositivo.
        TraceLog.log('cash', 'cash.close.no_open_session');
        if (mounted) await refresh(silent: true);
        return null;
      }
      final snapshot = CashCloseTicketSnapshot(
        state: stateBeforeClose,
        summary: summaryBeforeClose,
        movements: movementsBeforeClose,
        closingAmount: closingAmount,
        note: note,
        capturedAt: DateTime.now(),
      );

      await repo.closeSession(
        closingAmount: closingAmount,
        sessionId: sessionId,
        note: note,
      );
      if (!mounted) return null;
      // El cierre se confirmó contra el backend: estado verificado.
      _markCashStateUnverified(false);
      debugPrint(
        '[CASH_LIFECYCLE] CLOSE API SUCCESS id=${identityHashCode(this)}',
      );
      TraceLog.log('cash', 'cash.close.done');
      if (!mounted) return null;
      return await printer.printCloseTicket(snapshot);
    } on CashSessionAlreadyClosedException {
      // El turno ya estaba cerrado (lo cerró este u otro dispositivo). En vez
      // de quedarse mostrando el snapshot viejo "abierto", revalidamos contra
      // el backend para que la UI converja inmediatamente a CERRADO.
      debugPrint(
        '[CASH_LIFECYCLE] CLOSE ALREADY CLOSED id=${identityHashCode(this)}',
      );
      TraceLog.log('cash', 'cash.conflict already_closed');
      if (!mounted) return null;
      await refresh(silent: true);
      if (!mounted) return null;
      return null;
    } on CashClosePendingSyncException {
      // El cierre quedó guardado localmente, pero aún no está confirmado por el
      // backend. Mantener el turno en estado no verificado evita abrir otro
      // turno antes de que la cola sincronice el cierre exacto.
      debugPrint(
        '[CASH_LIFECYCLE] CLOSE PENDING SYNC id=${identityHashCode(this)}',
      );
      TraceLog.log('cash', 'cash.close.pending_sync');
      _markCashStateUnverified(true);
      if (!mounted) return null;
      await refresh(silent: true);
      if (!mounted) return null;
      return null;
    } finally {
      _closing = false;
    }
  }

  Future<PrintTicketResult> printCurrent() async {
    if (!mounted) return _disposedPrintResult;
    final repo = ref.read(cashRepositoryProvider);
    final printer = ref.read(cashCloseTicketPrinterProvider);
    final state = await repo.state();
    if (!mounted) return _disposedPrintResult;
    final summary = await repo.summary();
    if (!mounted) return _disposedPrintResult;
    final movements = await repo.movements();
    if (!mounted) return _disposedPrintResult;
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
    // El notifier pudo haberse recreado (dispose) mientras una operación
    // async/diálogo estaba en vuelo. Evitar tocar un controller muerto.
    if (!mounted) return;
    final repo = ref.read(cashRepositoryProvider);
    await repo.addMovement(
      type: type,
      amount: amount,
      reason: reason,
      sessionId: state.valueOrNull?.shiftId,
      movementType: movementType,
      affectsProfit: affectsProfit,
    );
    if (!mounted) return;
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
  }
}

const _disposedPrintResult = PrintTicketResult(
  success: false,
  message: 'El turno cambió mientras se preparaba la impresión.',
);

final activeCashSessionControllerProvider =
    StateNotifierProvider<
      ActiveCashSessionController,
      AsyncValue<ActiveCashSession?>
    >((ref) => ActiveCashSessionController(ref));
