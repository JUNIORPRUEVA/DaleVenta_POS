import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/trace_log.dart';
import 'app_update_installer.dart';
import 'app_update_installer_contract.dart';
import 'app_update_models.dart';
import 'app_update_persistence.dart';
import 'app_update_repository.dart';
import 'update_downloader.dart';
import 'update_restart_guard.dart';
import 'update_signature_verifier.dart';
import 'update_verifier.dart';

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(
        ref.read(appUpdateRepositoryProvider),
        ref.read(updatePersistenceProvider),
        ref.read(updateRestartGuardProvider),
        ref.read(updateDownloaderProvider),
        ref.read(updateVerifierProvider),
        ref.read(updateSignatureVerifierProvider),
        ref.read(appUpdateInstallerProvider),
      );
    });

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._repository,
    this._persistence,
    this._restartGuard,
    this._downloader,
    this._verifier,
    this._signatureVerifier,
    this._installer,
  ) : super(AppUpdateState.initial());

  final AppUpdateRepository _repository;
  final UpdatePersistence _persistence;
  final UpdateRestartGuard _restartGuard;
  final UpdateDownloader _downloader;
  final UpdateVerifier _verifier;
  final UpdateSignatureVerifier _signatureVerifier;
  final AppUpdateInstaller _installer;
  Future<void>? _checkFuture;
  Future<void>? _downloadFuture;
  Future<void>? _loadFuture;
  bool _loaded = false;
  DateTime? _lastCheckedAt;
  static const Duration _minimumRecheckInterval = Duration(minutes: 1);
  static const Duration _initialCheckDelay = Duration(seconds: 3);

  Future<void> scheduleInitialCheck() async {
    await _ensureLoaded();
    unawaited(
      Future<void>.delayed(_initialCheckDelay, () {
        unawaited(checkNow());
      }),
    );
  }

  Future<void> checkNow({bool force = false}) async {
    await _ensureLoaded();

    if (!force && _checkFuture != null) {
      return _checkFuture!;
    }

    if (!force && _lastCheckedAt != null) {
      final elapsed = DateTime.now().difference(_lastCheckedAt!);
      if (elapsed < _minimumRecheckInterval) return;
    }

    late final Future<void> future;
    future = _runCheck().whenComplete(() {
      if (identical(_checkFuture, future)) _checkFuture = null;
    });
    _checkFuture = future;
    return future;
  }

  Future<void> dismissCurrentBuild() async {
    await _ensureLoaded();
    final build = state.manifest?.buildNumber;
    if (build == null) return;
    final persisted = state.persisted.copyWith(dismissedBuild: build);
    await _setState(state.copyWith(persisted: persisted));
  }

  Future<void> requestInstallPreparedUpdate() async {
    await _ensureLoaded();
    if (state.phase != AppUpdatePhase.readyToInstall) return;

    final readiness = await _restartGuard.canSafelyRestartForUpdate();
    final nextPhase = readiness.safe
        ? AppUpdatePhase.installRequested
        : AppUpdatePhase.waitingSafeState;
    var persisted = state.persisted.copyWith(
      phase: nextPhase,
      lastErrorCode: readiness.safe ? null : readiness.reason,
      clearLastError: readiness.safe,
    );
    await _setState(
      state.copyWith(
        phase: nextPhase,
        persisted: persisted,
        message: readiness.reason,
        clearMessage: readiness.safe,
      ),
    );

    if (!readiness.safe) return;

    try {
      await _installer.launchPreparedWindowsUpdate(persisted: state.persisted);
      persisted = state.persisted.copyWith(
        phase: AppUpdatePhase.updaterStarted,
        lastUpdateResult: 'UPDATER_STARTED',
        clearLastError: true,
      );
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.updaterStarted,
          persisted: persisted,
        ),
      );
    } catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'secure updater launch failed',
        error: error,
        stackTrace: stackTrace,
      );
      persisted = state.persisted.copyWith(
        phase: AppUpdatePhase.installFailed,
        lastUpdateResult: 'UPDATER_LAUNCH_FAILED',
        lastErrorCode: 'UPDATER_LAUNCH_FAILED',
      );
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.installFailed,
          persisted: persisted,
        ),
      );
    }
  }

  Future<void> retryBlockedUpdate() => requestInstallPreparedUpdate();

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final existing = _loadFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _persistence
        .load()
        .then((persisted) {
          state = state.copyWith(phase: persisted.phase, persisted: persisted);
          if (persisted.lastErrorCode == 'RECOVERED_TRANSIENT_STATE') {
            final targetBuild = persisted.targetBuild;
            if (targetBuild != null) {
              unawaited(_downloader.discardBuild(targetBuild));
            }
            _loaded = true;
            return _persistence.save(persisted);
          }
          _loaded = true;
        })
        .whenComplete(() {
          if (identical(_loadFuture, future)) _loadFuture = null;
        });
    _loadFuture = future;
    return future;
  }

  Future<void> _runCheck() async {
    if (!_repository.isConfigured) {
      await _persistStable(
        phase: AppUpdatePhase.idle,
        result: 'CONFIG_DISABLED',
        clearTarget: true,
      );
      return;
    }

    final installedRelease = await _repository.readInstalledRelease();
    if (installedRelease == null) {
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.unsupported,
          installedRelease: null,
          clearManifest: true,
          clearMessage: true,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.unsupported,
            lastUpdateCheckAt: DateTime.now(),
            lastUpdateResult: 'UNSUPPORTED_PLATFORM',
            clearTarget: true,
          ),
        ),
      );
      return;
    }

    if (await _reconcileInstallerResult(installedRelease)) {
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      installedRelease: installedRelease,
      clearMessage: true,
    );

    try {
      final manifest = await _repository.checkForUpdate(installedRelease);
      _lastCheckedAt = DateTime.now();

      if (!manifest.isNewerThan(installedRelease.currentBuild)) {
        final staleBuild = state.persisted.targetBuild;
        if (staleBuild != null) {
          await _downloader.discardBuild(staleBuild);
        }
        await _setState(
          state.copyWith(
            phase: AppUpdatePhase.idle,
            installedRelease: installedRelease,
            manifest: manifest,
            checkedAt: _lastCheckedAt,
            clearMessage: true,
            persisted: state.persisted.copyWith(
              phase: AppUpdatePhase.idle,
              lastUpdateCheckAt: _lastCheckedAt,
              lastUpdateResult: 'UP_TO_DATE',
              clearTarget: true,
              clearLastError: true,
            ),
          ),
        );
        return;
      }

      final previousBuild = state.persisted.targetBuild;
      if (previousBuild != null && previousBuild != manifest.buildNumber) {
        await _downloader.discardBuild(previousBuild);
      }

      final dismissed = manifest.isDismissedBy(state.persisted.dismissedBuild);
      const phase = AppUpdatePhase.available;
      await _setState(
        state.copyWith(
          phase: phase,
          installedRelease: installedRelease,
          manifest: manifest,
          checkedAt: _lastCheckedAt,
          clearMessage: true,
          persisted: state.persisted.copyWith(
            phase: phase,
            targetBuild: manifest.buildNumber,
            targetVersion: manifest.version,
            fileSizeExpected: manifest.fileSize,
            sha256Expected: manifest.sha256?.toLowerCase(),
            bytesDownloaded: 0,
            clearArtifact: true,
            lastUpdateCheckAt: _lastCheckedAt,
            lastUpdateResult: dismissed ? 'AVAILABLE_DISMISSED' : 'AVAILABLE',
            clearLastError: true,
          ),
        ),
      );
      unawaited(_startBackgroundDownload(manifest));
    } catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'silent check failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.idle,
          installedRelease: installedRelease,
          clearManifest: true,
          message: null,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.idle,
            lastUpdateCheckAt: DateTime.now(),
            lastUpdateResult: 'CHECK_ERROR',
            lastErrorCode: 'CHECK_ERROR',
          ),
        ),
      );
    }
  }

  Future<bool> _reconcileInstallerResult(
    InstalledReleaseInfo installedRelease,
  ) async {
    final targetBuild = state.persisted.targetBuild;
    if (targetBuild == null) return false;
    final result = await _downloader.readInstallerResult(targetBuild);
    if (result == null || result.targetBuild != targetBuild) {
      if (installedRelease.currentBuild >= targetBuild) {
        await _setState(
          state.copyWith(
            phase: AppUpdatePhase.installedConfirmed,
            installedRelease: installedRelease,
            clearManifest: true,
            clearMessage: true,
            persisted: state.persisted.copyWith(
              phase: AppUpdatePhase.installedConfirmed,
              lastUpdateResult: 'INSTALLED_CONFIRMED',
              clearTarget: true,
              clearLastError: true,
            ),
          ),
        );
        return true;
      }
      return false;
    }

    if (result.result == 'SUCCESS' &&
        installedRelease.currentBuild >= targetBuild) {
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.installedConfirmed,
          installedRelease: installedRelease,
          clearManifest: true,
          clearMessage: true,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.installedConfirmed,
            lastUpdateResult: 'INSTALLED_CONFIRMED',
            clearTarget: true,
            clearLastError: true,
          ),
        ),
      );
      return true;
    }

    if (result.result == 'UAC_CANCELLED') {
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          installedRelease: installedRelease,
          clearMessage: true,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.readyToInstall,
            lastUpdateResult: 'UAC_CANCELLED',
            lastErrorCode: 'UAC_CANCELLED',
          ),
        ),
      );
      return true;
    }

    if (state.persisted.phase == AppUpdatePhase.updaterStarted ||
        result.result == 'INSTALLER_FAILED' ||
        result.result == 'UPDATER_ERROR') {
      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.installFailed,
          installedRelease: installedRelease,
          clearMessage: true,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.installFailed,
            lastUpdateResult: result.result,
            lastErrorCode: result.result,
          ),
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _persistStable({
    required AppUpdatePhase phase,
    required String result,
    bool clearTarget = false,
  }) {
    final now = DateTime.now();
    return _setState(
      state.copyWith(
        phase: phase,
        clearManifest: clearTarget,
        clearMessage: true,
        persisted: state.persisted.copyWith(
          phase: phase,
          lastUpdateCheckAt: now,
          lastUpdateResult: result,
          clearTarget: clearTarget,
          clearLastError: true,
        ),
      ),
    );
  }

  Future<void> _startBackgroundDownload(UpdateManifest manifest) async {
    final existing = _downloadFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _downloadAndVerify(manifest).whenComplete(() {
      if (identical(_downloadFuture, future)) _downloadFuture = null;
    });
    _downloadFuture = future;
    return future;
  }

  Future<void> _downloadAndVerify(UpdateManifest manifest) async {
    final targetBuild = manifest.buildNumber;
    if (targetBuild == null) return;

    await _setState(
      state.copyWith(
        phase: AppUpdatePhase.downloading,
        manifest: manifest,
        clearMessage: true,
        clearProgress: true,
        persisted: state.persisted.copyWith(
          phase: AppUpdatePhase.downloading,
          targetBuild: targetBuild,
          targetVersion: manifest.version,
          fileSizeExpected: manifest.fileSize,
          sha256Expected: manifest.sha256?.toLowerCase(),
          attempts: state.persisted.attempts + 1,
          clearArtifact: true,
          clearLastError: true,
        ),
      ),
    );

    try {
      final download = await _downloader.download(
        manifest,
        onProgress: (progress) {
          final next = state.copyWith(
            phase: AppUpdatePhase.downloading,
            manifest: manifest,
            progress: progress,
            persisted: state.persisted.copyWith(
              phase: AppUpdatePhase.downloading,
              bytesDownloaded: progress.bytesDownloaded,
              fileSizeExpected: progress.totalBytes,
              sha256Expected: manifest.sha256?.toLowerCase(),
            ),
          );
          state = next;
          unawaited(_persistence.save(next.persisted));
        },
      );

      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.verifyingSha,
          manifest: manifest,
          progress: UpdateDownloadProgress(
            bytesDownloaded: download.bytesDownloaded,
            totalBytes: download.fileSizeExpected,
          ),
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.verifyingSha,
            bytesDownloaded: download.bytesDownloaded,
            fileSizeExpected: download.fileSizeExpected,
            sha256Expected: manifest.sha256?.toLowerCase(),
          ),
        ),
      );

      await _verifier.verifySha256(
        filePath: download.partPath,
        expectedSha256: manifest.sha256 ?? '',
      );

      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.verifyingSignature,
          manifest: manifest,
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.verifyingSignature,
          ),
        ),
      );

      await _signatureVerifier.verifyPackage(
        filePath: download.partPath,
        updateRootPath: download.updateRootPath,
        expectedSha256: manifest.sha256 ?? '',
      );
      await _downloader.promoteToReady(download);

      await _setState(
        state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          manifest: manifest,
          progress: UpdateDownloadProgress(
            bytesDownloaded: download.bytesDownloaded,
            totalBytes: download.fileSizeExpected,
          ),
          persisted: state.persisted.copyWith(
            phase: AppUpdatePhase.readyToInstall,
            artifactRelativePath: download.artifactRelativePath,
            bytesDownloaded: download.bytesDownloaded,
            fileSizeExpected: download.fileSizeExpected,
            sha256Expected: manifest.sha256?.toLowerCase(),
            lastUpdateResult: 'READY_TO_INSTALL',
            clearLastError: true,
          ),
        ),
      );
    } on UpdateDownloadException catch (error, stackTrace) {
      await _failDownload(manifest, targetBuild, error.code, error, stackTrace);
    } on UpdateVerificationException catch (error, stackTrace) {
      await _downloader.discardBuild(targetBuild);
      await _failDownload(manifest, targetBuild, error.code, error, stackTrace);
    } on UpdateSignatureVerificationException catch (error, stackTrace) {
      await _downloader.discardBuild(targetBuild);
      await _failDownload(manifest, targetBuild, error.code, error, stackTrace);
    } catch (error, stackTrace) {
      await _downloader.discardBuild(targetBuild);
      await _failDownload(
        manifest,
        targetBuild,
        'DOWNLOAD_FAILED',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _failDownload(
    UpdateManifest manifest,
    int targetBuild,
    String code,
    Object error,
    StackTrace stackTrace,
  ) async {
    TraceLog.log(
      'AppUpdate',
      'background download failed',
      error: error,
      stackTrace: stackTrace,
    );
    await _setState(
      state.copyWith(
        phase: AppUpdatePhase.installFailed,
        manifest: manifest,
        message: null,
        clearProgress: true,
        persisted: state.persisted.copyWith(
          phase: AppUpdatePhase.installFailed,
          targetBuild: targetBuild,
          targetVersion: manifest.version,
          fileSizeExpected: manifest.fileSize,
          sha256Expected: manifest.sha256?.toLowerCase(),
          clearArtifact: true,
          lastUpdateResult: 'DOWNLOAD_FAILED',
          lastErrorCode: code,
        ),
      ),
    );
  }

  Future<void> _setState(AppUpdateState next) async {
    state = next;
    await _persistence.save(next.persisted);
  }
}

typedef UpdateStateController = AppUpdateController;
