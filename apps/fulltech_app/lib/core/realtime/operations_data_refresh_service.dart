import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/cash/cash_management_screens.dart';
import '../../modules/cash/cash_providers.dart';
import '../../modules/ventas/application/ventas_controller.dart';
import '../../modules/ventas/sales_credit_screen.dart';
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
  }

  final Ref _ref;
  StreamSubscription<SalesRealtimeMessage>? _salesSubscription;
  StreamSubscription<CashRealtimeMessage>? _cashSubscription;

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

  void dispose() {
    unawaited(_salesSubscription?.cancel());
    unawaited(_cashSubscription?.cancel());
  }
}
