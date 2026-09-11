import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_installer.dart';
import 'app_update_installer_contract.dart';
import 'app_update_models.dart';
import 'app_update_repository.dart';

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(
        ref.read(appUpdateRepositoryProvider),
        ref.read(appUpdateInstallerProvider),
      );
    });

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._repository, this._installer)
    : super(AppUpdateState.initial());

  final AppUpdateRepository _repository;
  final AppUpdateInstaller _installer;
  Future<void>? _checkFuture;
  DateTime? _lastCheckedAt;
  static const Duration _minimumRecheckInterval = Duration(minutes: 1);

  Future<void> retryBlockedUpdate() {
    final installedRelease = state.installedRelease;
    final updateInfo = state.updateInfo;

    if (installedRelease?.platform == ReleasePlatform.windows &&
        updateInfo?.update == true) {
      return _startWindowsAutoUpdate(installedRelease!, updateInfo!);
    }

    return checkNow(force: true);
  }

  Future<void> checkNow({bool force = false}) {
    if (!force && state.blocksUsage) {
      return Future.value();
    }

    if (!force && _checkFuture != null) {
      return _checkFuture!;
    }

    if (!force && _lastCheckedAt != null) {
      final elapsed = DateTime.now().difference(_lastCheckedAt!);
      if (elapsed < _minimumRecheckInterval) {
        return Future.value();
      }
    }

    late final Future<void> future;
    future = _runCheck().whenComplete(() {
      if (identical(_checkFuture, future)) {
        _checkFuture = null;
      }
    });
    _checkFuture = future;
    return future;
  }

  Future<void> _runCheck() async {
    if (!_repository.isConfigured) {
      state = state.copyWith(
        phase: AppUpdatePhase.disabled,
        message: 'Releases no configurado.',
        clearUpdateInfo: true,
        clearDownloadProgress: true,
      );
      return;
    }

    final installedRelease = await _repository.readInstalledRelease();
    if (installedRelease == null) {
      state = state.copyWith(
        phase: AppUpdatePhase.unsupported,
        message: 'La plataforma actual no usa releases administrados.',
        clearUpdateInfo: true,
        clearDownloadProgress: true,
      );
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      installedRelease: installedRelease,
      clearMessage: true,
      clearDownloadProgress: true,
    );

    try {
      final updateInfo = await _repository.checkForUpdate(installedRelease);
      _lastCheckedAt = DateTime.now();

      if (installedRelease.platform == ReleasePlatform.windows &&
          updateInfo.update) {
        state = state.copyWith(
          installedRelease: installedRelease,
          updateInfo: updateInfo,
          checkedAt: _lastCheckedAt,
          clearMessage: true,
          clearDownloadProgress: true,
        );
        await _startWindowsAutoUpdate(installedRelease, updateInfo);
        return;
      }

      state = state.copyWith(
        phase: _resolvePhase(updateInfo, installedRelease),
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        checkedAt: _lastCheckedAt,
        clearMessage: true,
        clearDownloadProgress: true,
      );
    } on AppUpdateConfigurationException catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.disabled,
        installedRelease: installedRelease,
        message: error.message,
        clearUpdateInfo: true,
        clearDownloadProgress: true,
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        installedRelease: installedRelease,
        message: error.toString(),
        clearUpdateInfo: true,
        clearDownloadProgress: true,
      );
    }
  }

  Future<void> _startWindowsAutoUpdate(
    InstalledReleaseInfo installedRelease,
    AppUpdateInfo updateInfo,
  ) async {
    if (!updateInfo.hasDownloadUrl) {
      state = state.copyWith(
        phase: AppUpdatePhase.requiredUpdate,
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        message:
            'Hay una nueva versión de Windows, pero el release no tiene una URL de descarga válida.',
        clearDownloadProgress: true,
      );
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.downloadingUpdate,
      installedRelease: installedRelease,
      updateInfo: updateInfo,
      checkedAt: _lastCheckedAt,
      message: 'Descargando actualización de FullTech para Windows...',
      downloadProgress: 0,
    );

    try {
      await _installer.downloadAndLaunchWindowsInstaller(
        updateInfo,
        onProgress: (progress) {
          state = state.copyWith(
            phase: AppUpdatePhase.downloadingUpdate,
            installedRelease: installedRelease,
            updateInfo: updateInfo,
            checkedAt: _lastCheckedAt,
            message: 'Descargando actualización de FullTech para Windows...',
            downloadProgress: progress,
          );
        },
      );

      state = state.copyWith(
        phase: AppUpdatePhase.installingUpdate,
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        checkedAt: _lastCheckedAt,
        message:
            'Instalador iniciado. FullTech se cerrará para completar la actualización.',
        downloadProgress: 1,
      );
    } on AppUpdateInstallException catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.requiredUpdate,
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        checkedAt: _lastCheckedAt,
        message: error.message,
        clearDownloadProgress: true,
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.requiredUpdate,
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        checkedAt: _lastCheckedAt,
        message:
            'No se pudo completar la actualización automática de Windows.',
        clearDownloadProgress: true,
      );
    }
  }

  AppUpdatePhase _resolvePhase(
    AppUpdateInfo updateInfo,
    InstalledReleaseInfo installedRelease,
  ) {
    if (installedRelease.platform == ReleasePlatform.android &&
        updateInfo.update) {
      return AppUpdatePhase.requiredUpdate;
    }

    if (updateInfo.required) return AppUpdatePhase.requiredUpdate;
    if (updateInfo.update) return AppUpdatePhase.optionalUpdate;
    return AppUpdatePhase.upToDate;
  }
}
