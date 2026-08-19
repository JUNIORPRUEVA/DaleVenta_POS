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
    refreshCash();
  }

  void refreshCash() {
    _ref.read(cashDataRefreshTickProvider.notifier).state++;
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
