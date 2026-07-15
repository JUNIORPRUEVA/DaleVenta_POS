import 'app_update_models.dart';

abstract class AppUpdateInstaller {
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  });
}

class AppUpdateInstallException implements Exception {
  final String message;

  const AppUpdateInstallException(this.message);

  @override
  String toString() => message;
}
