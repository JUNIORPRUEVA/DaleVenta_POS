import 'package:flutter_riverpod/flutter_riverpod.dart';

final updateRestartGuardProvider = Provider<UpdateRestartGuard>((ref) {
  return const PermissiveUpdateRestartGuard();
});

abstract class UpdateRestartGuard {
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate();
}

class UpdateRestartReadiness {
  final bool safe;
  final String? reason;

  const UpdateRestartReadiness.safe() : safe = true, reason = null;

  const UpdateRestartReadiness.blocked(this.reason) : safe = false;
}

class PermissiveUpdateRestartGuard implements UpdateRestartGuard {
  const PermissiveUpdateRestartGuard();

  @override
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate() async {
    return const UpdateRestartReadiness.safe();
  }
}
