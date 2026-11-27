import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/sync_queue_service.dart';
import '../update/print_activity_tracker.dart';
import 'update_critical_operation_gate.dart';
export 'update_critical_operation_gate.dart';

final updateRestartGuardProvider = Provider<UpdateRestartGuard>((ref) {
  return AppUpdateRestartGuard(ref);
});

final updateCriticalOperationGateProvider =
    Provider<UpdateCriticalOperationGate>(
      (ref) => UpdateCriticalOperationGate.instance,
    );

abstract interface class UpdateRestartLeaseGuard {
  void releaseRestart();
}

abstract class UpdateRestartGuard {
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate();

  Future<UpdateRestartReadiness> prepareForRestart() async {
    return canSafelyRestartForUpdate();
  }
}

class UpdateRestartReadiness {
  final bool safe;
  final String? reason;

  const UpdateRestartReadiness.safe() : safe = true, reason = null;

  const UpdateRestartReadiness.blocked(this.reason) : safe = false;
}

class AppUpdateRestartGuard
    implements UpdateRestartGuard, UpdateRestartLeaseGuard {
  const AppUpdateRestartGuard(this._ref);

  final Ref _ref;

  @override
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate() async {
    final gate = _ref.read(updateCriticalOperationGateProvider);
    if (gate.hasActiveCriticalOperation) {
      return const UpdateRestartReadiness.blocked('CRITICAL_OPERATION');
    }
    if (PrintActivityTracker.instance.hasPendingPrintJobs) {
      return const UpdateRestartReadiness.blocked('PRINT_IN_PROGRESS');
    }
    final syncState = _ref.read(syncQueueServiceProvider);
    if (syncState.isProcessing) {
      return const UpdateRestartReadiness.blocked('SYNC_COMMIT_IN_PROGRESS');
    }
    return const UpdateRestartReadiness.safe();
  }

  @override
  Future<UpdateRestartReadiness> prepareForRestart() async {
    final printIdle = await PrintActivityTracker.instance.waitUntilIdle(
      const Duration(seconds: 8),
    );
    if (!printIdle) {
      return const UpdateRestartReadiness.blocked('PRINT_IN_PROGRESS');
    }
    final readiness = await canSafelyRestartForUpdate();
    if (!readiness.safe) return readiness;
    return _ref.read(updateCriticalOperationGateProvider).reserveRestart()
        ? const UpdateRestartReadiness.safe()
        : const UpdateRestartReadiness.blocked('CRITICAL_OPERATION');
  }

  @override
  void releaseRestart() =>
      _ref.read(updateCriticalOperationGateProvider).releaseRestart();
}

class PermissiveUpdateRestartGuard implements UpdateRestartGuard {
  const PermissiveUpdateRestartGuard();

  @override
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate() async {
    return const UpdateRestartReadiness.safe();
  }

  @override
  Future<UpdateRestartReadiness> prepareForRestart() async {
    return const UpdateRestartReadiness.safe();
  }
}
