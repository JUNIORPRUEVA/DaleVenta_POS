import 'app_update_installer_contract.dart';
import 'app_update_models.dart';

AppUpdateInstaller createAppUpdateInstaller() =>
    const UnsupportedAppUpdateInstaller();

class UnsupportedAppUpdateInstaller implements AppUpdateInstaller {
  const UnsupportedAppUpdateInstaller();

  @override
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  }) {
    throw const AppUpdateInstallException(
      'La instalación automática solo está disponible en Windows.',
    );
  }
}
