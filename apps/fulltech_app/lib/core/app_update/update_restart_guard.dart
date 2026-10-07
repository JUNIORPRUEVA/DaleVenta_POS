import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/sync_queue_service.dart';
import '../update/print_activity_tracker.dart';

final updateRestartGuardProvider = Provider<UpdateRestartGuard>((ref) {
  return AppUpdateRestartGuard(ref);
});

final updateCriticalOperationGateProvider =
    Provider<UpdateCriticalOperationGate>(
      (ref) => UpdateCriticalOperationGate(),
    );

class UpdateCriticalOperationGate {
  int _activeOperations = 0;

  bool get hasActiveCriticalOperation => _activeOperations > 0;

  UpdateCriticalOperationToken beginCriticalOperation() {
    _activeOperations += 1;
    return UpdateCriticalOperationToken._(this);
  }

  void _endCriticalOperation() {
    if (_activeOperations > 0) _activeOperations -= 1;
  }
}

class UpdateCriticalOperationToken {
  UpdateCriticalOperationToken._(this._gate);

  final UpdateCriticalOperationGate _gate;
  bool _ended = false;

  void end() {
    if (_ended) return;
    _ended = true;
    _gate._endCriticalOperation();
  }
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

class AppUpdateRestartGuard implements UpdateRestartGuard {
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
    return canSafelyRestartForUpdate();
  }
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
