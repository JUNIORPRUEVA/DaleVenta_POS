import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/trace_log.dart';
import 'app_update_models.dart';
import 'app_update_persistence.dart';
import 'app_update_repository.dart';
import 'update_restart_guard.dart';

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(
        ref.read(appUpdateRepositoryProvider),
        ref.read(updatePersistenceProvider),
        ref.read(updateRestartGuardProvider),
      );
    });

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._repository, this._persistence, this._restartGuard)
    : super(AppUpdateState.initial());

  final AppUpdateRepository _repository;
  final UpdatePersistence _persistence;
  final UpdateRestartGuard _restartGuard;
  Future<void>? _checkFuture;
  Future<void>? _loadFuture;
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
    final persisted = state.persisted.copyWith(
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
  }

  Future<void> retryBlockedUpdate() => requestInstallPreparedUpdate();

  Future<void> _ensureLoaded() {
    final existing = _loadFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _persistence
        .load()
        .then((persisted) {
          state = state.copyWith(phase: persisted.phase, persisted: persisted);
          if (persisted.lastErrorCode == 'RECOVERED_TRANSIENT_STATE') {
            return _persistence.save(persisted);
          }
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

    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      installedRelease: installedRelease,
      clearMessage: true,
    );

    try {
      final manifest = await _repository.checkForUpdate(installedRelease);
      _lastCheckedAt = DateTime.now();

      if (!manifest.isNewerThan(installedRelease.currentBuild)) {
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
            lastUpdateCheckAt: _lastCheckedAt,
            lastUpdateResult: dismissed ? 'AVAILABLE_DISMISSED' : 'AVAILABLE',
            clearLastError: true,
          ),
        ),
      );
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

  Future<void> _setState(AppUpdateState next) async {
    state = next;
    await _persistence.save(next.persisted);
  }
}

typedef UpdateStateController = AppUpdateController;
