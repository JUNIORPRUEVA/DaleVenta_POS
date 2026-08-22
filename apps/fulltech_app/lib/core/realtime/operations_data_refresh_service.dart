import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/cash/cash_management_screens.dart';
import '../../modules/cash/cash_providers.dart';
import '../../modules/ventas/application/ventas_controller.dart';
import '../../modules/ventas/sales_credit_screen.dart';
import '../auth/auth_provider.dart';
import 'operations_refresh_signals.dart';
import 'operations_realtime_service.dart';

final operationsDataRefreshProvider = Provider<OperationsDataRefreshService>((
  ref,
) {
  final service = OperationsDataRefreshService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class OperationsDataRefreshService {
  OperationsDataRefreshService(this._ref) {
    final realtime = _ref.read(operationsRealtimeServiceProvider);
    _salesSubscription = realtime.salesStream.listen((_) {
      refreshSalesAndCash();
    });
    _cashSubscription = realtime.cashStream.listen((_) {
      refreshCash();
    });
    _permissionsSubscription = realtime.permissionsStream.listen((message) {
      unawaited(refreshPermissions(message));
      if (message.type == 'permissions.reconnect') {
        // El socket se (re)conectó tras estar en background/caída de red: los
        // eventos realtime de caja (`cash.session.closed/opened`) pudieron
        // perderse mientras estuvo desconectado. Revalidamos el turno en
        // silencio para converger al estado real del backend (multi-dispositivo).
        refreshCash(silent: true);
      }
    });
    // Reacciona a login/logout para que la caja no arrastre estado de otra
    // sesión/empresa entre inicios de sesión. El subscription se gestiona solo
    // mientras viva este provider (ref.listen se limpia automáticamente).
    _ref.listen<AuthState>(authStateProvider, (
      previous,
      next,
    ) {
      if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        _resetCashState();
      } else if (previous?.isAuthenticated == false && next.isAuthenticated) {
        refreshCash();
      }
    });
  }

  final Ref _ref;
  StreamSubscription<SalesRealtimeMessage>? _salesSubscription;
  StreamSubscription<CashRealtimeMessage>? _cashSubscription;
  StreamSubscription<PermissionsRealtimeMessage>? _permissionsSubscription;

  void refreshSalesAndCash() {
    _ref.read(salesDataRefreshTickProvider.notifier).state++;
    _ref.invalidate(ventasControllerProvider);
    _ref.invalidate(salesCreditsProvider);
    refreshCash(silent: true);
  }

  void refreshCash({bool silent = false}) {
    _ref.read(cashDataRefreshTickProvider.notifier).state++;
    // IMPORTANTE: NO invalidar activeCashSessionControllerProvider aquí.
    // Invalidarlo destruye (dispose) el notifier mientras una operación
    // async (abrir/cerrar turno) puede estar en vuelo o mientras un diálogo
    // conserva una referencia, provocando:
    //   Bad state: Tried to use ActiveCashSessionController after 'dispose'.
    // En su lugar se refresca el MISMO controller en sitio (sin recrearlo).
    final controller = _ref
        .read(activeCashSessionControllerProvider.notifier);
    _ref.invalidate(cashGateStateProvider);
    _ref.invalidate(activeCashSessionProvider);
    _ref.invalidate(cashSummaryProvider);
    _ref.invalidate(cashMovementsProvider);
    _ref.invalidate(cashExpenseHistoryProvider);
    _ref.invalidate(cashMovementHistoryProvider);
    _ref.invalidate(cashTurnHistoryProvider);
    if (controller.mounted) {
      // `silent: true` para reconciliaciones de fondo (realtime, reconnect,
      // resume, polling): no queremos que cada evento provoque un flash de
      // loading en la UI (ver regla anti-flicker).
      unawaited(controller.refresh(silent: silent));
    }
  }

  void _resetCashState() {
    _ref.invalidate(activeCashSessionControllerProvider);
    _ref.invalidate(cashGateStateProvider);
    _ref.invalidate(activeCashSessionProvider);
    _ref.invalidate(cashSummaryProvider);
    _ref.invalidate(cashMovementsProvider);
    _ref.invalidate(cashExpenseHistoryProvider);
    _ref.invalidate(cashMovementHistoryProvider);
    _ref.invalidate(cashTurnHistoryProvider);
  }

  Future<void> refreshPermissions(PermissionsRealtimeMessage message) async {
    final auth = _ref.read(authStateProvider);
    final user = auth.user;
    if (!auth.isAuthenticated || user == null) return;
    if (message.companyId != user.companyId || message.userId != user.id) {
      return;
    }

    await _ref
        .read(authStateProvider.notifier)
        .refreshCurrentUser(silent: true);
  }

  void dispose() {
    unawaited(_salesSubscription?.cancel());
    unawaited(_cashSubscription?.cancel());
    unawaited(_permissionsSubscription?.cancel());
  }
}
