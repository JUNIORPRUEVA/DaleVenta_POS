import '../debug/trace_log.dart';
import 'app_update_models.dart';

class AppUpdateTelemetry {
  const AppUpdateTelemetry();

  void event(
    String name, {
    InstalledReleaseInfo? installedRelease,
    PersistedUpdateState? persisted,
    int? targetBuild,
    String? result,
  }) {
    final buildNumber = installedRelease?.currentBuild;
    final state = persisted?.phase.code;
    final resolvedTargetBuild = targetBuild ?? persisted?.targetBuild;
    final checkedAt = persisted?.lastUpdateCheckAt?.toIso8601String();
    final resolvedResult = result ?? persisted?.lastUpdateResult;
    TraceLog.log(
      'AppUpdate',
      '$name buildNumber=$buildNumber updateState=$state targetBuild=$resolvedTargetBuild lastUpdateCheckAt=$checkedAt lastUpdateResult=$resolvedResult',
    );
  }
}
