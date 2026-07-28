import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/app_update/app_update_controller.dart';
import 'package:daleventa_pos/core/app_update/app_update_installer_contract.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';

void main() {
  group('AppUpdateController', () {
    test('forces Android users to update when a newer build exists', () async {
      final repository = FakeAppUpdateRepository(
        installedRelease: const InstalledReleaseInfo(
          platform: ReleasePlatform.android,
          currentVersion: '1.0.0',
          currentBuild: 1,
        ),
        updateInfo: const AppUpdateInfo(
          update: true,
          required: false,
          latestVersion: '1.0.1',
          latestBuild: 2,
          downloadUrl: 'https://example.com/fulltech.apk',
        ),
      );
      final installer = FakeAppUpdateInstaller();
      final controller = AppUpdateController(repository, installer);

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.requiredUpdate);
      expect(controller.state.blocksUsage, isTrue);
      expect(installer.installCalls, 0);
    });

    test(
      'starts Windows automatic installation when a new release exists',
      () async {
        final repository = FakeAppUpdateRepository(
          installedRelease: const InstalledReleaseInfo(
            platform: ReleasePlatform.windows,
            currentVersion: '1.0.0',
            currentBuild: 1,
          ),
          updateInfo: const AppUpdateInfo(
            update: true,
            required: false,
            latestVersion: '1.0.1',
            latestBuild: 2,
            downloadUrl: 'https://example.com/fulltech-setup.exe',
          ),
        );
        final installer = FakeAppUpdateInstaller(
          onInstall: ({required onProgress}) async {
            onProgress(0.4);
            onProgress(1);
          },
        );
        final controller = AppUpdateController(repository, installer);

        await controller.checkNow(force: true);

        expect(installer.installCalls, 1);
        expect(controller.state.phase, AppUpdatePhase.installingUpdate);
        expect(controller.state.blocksUsage, isTrue);
        expect(controller.state.downloadProgress, 1);
      },
    );

    test('keeps Windows blocked if automatic installation fails', () async {
      final repository = FakeAppUpdateRepository(
        installedRelease: const InstalledReleaseInfo(
          platform: ReleasePlatform.windows,
          currentVersion: '1.0.0',
          currentBuild: 1,
        ),
        updateInfo: const AppUpdateInfo(
          update: true,
          required: false,
          latestVersion: '1.0.1',
          latestBuild: 2,
          downloadUrl: 'https://example.com/fulltech-setup.exe',
        ),
      );
      final installer = FakeAppUpdateInstaller(
        onInstall: ({required onProgress}) async {
          throw const AppUpdateInstallException('fallo controlado');
        },
      );
      final controller = AppUpdateController(repository, installer);

      await controller.checkNow(force: true);

      expect(installer.installCalls, 1);
      expect(controller.state.phase, AppUpdatePhase.requiredUpdate);
      expect(controller.state.blocksUsage, isTrue);
      expect(controller.state.message, contains('fallo controlado'));
    });
  });
}

class FakeAppUpdateRepository extends AppUpdateRepository {
  FakeAppUpdateRepository({
    this.configured = true,
    this.installedRelease,
    this.updateInfo,
  });

  final bool configured;
  final InstalledReleaseInfo? installedRelease;
  final AppUpdateInfo? updateInfo;

  @override
  bool get isConfigured => configured;

  @override
  Future<InstalledReleaseInfo?> readInstalledRelease() async =>
      installedRelease;

  @override
  Future<AppUpdateInfo> checkForUpdate(
    InstalledReleaseInfo installedRelease,
  ) async {
    final response = updateInfo;
    if (response == null) {
      throw StateError('FakeAppUpdateRepository.updateInfo is required');
    }
    return response;
  }
}

typedef InstallCallback =
    Future<void> Function({required void Function(double progress) onProgress});

class FakeAppUpdateInstaller implements AppUpdateInstaller {
  FakeAppUpdateInstaller({this.onInstall});

  final InstallCallback? onInstall;
  int installCalls = 0;

  @override
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  }) async {
    installCalls += 1;
    final callback = onInstall;
    if (callback == null) {
      return;
    }
    await callback(onProgress: onProgress);
  }
}
