import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/app_update/app_update_controller.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';
import 'package:daleventa_pos/core/app_update/update_downloader.dart';
import 'package:daleventa_pos/core/app_update/update_restart_guard.dart';
import 'package:daleventa_pos/core/app_update/update_verifier.dart';

void main() {
  group('UpdateManifest', () {
    test('parses a valid manifest', () {
      final manifest = UpdateManifest.fromJson(_manifestJson(build: 131));

      expect(manifest.updateAvailable, isTrue);
      expect(manifest.buildNumber, 131);
      expect(manifest.sha256, _sha);
      expect(manifest.releaseNotes, ['Mejoras']);
    });

    test('rejects invalid manifest metadata', () {
      expect(
        () => UpdateManifest.fromJson(_manifestJson(sha256: 'bad')),
        throwsFormatException,
      );
    });
  });

  group('AppUpdateController', () {
    test('no update returns idle without installer side effects', () async {
      final controller = _controller(
        manifest: UpdateManifest.noUpdate(),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.blocksUsage, isFalse);
      expect(controller.installerLaunches, 0);
    });

    test('greater build downloads and becomes ready silently', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.readyToInstall);
      expect(controller.state.manifest?.buildNumber, 131);
      expect(controller.state.hasVisibleMainPrompt, isTrue);
      expect(controller.installerLaunches, 0);
    });

    test('same build never upgrades', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 130)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.idle);
    });

    test('lower build never downgrades', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 129)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.idle);
    });

    test('check errors are non-fatal and return to idle', () async {
      final controller = _controller(error: StateError('network down'));

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.persisted.lastUpdateResult, 'CHECK_ERROR');
      expect(controller.state.blocksUsage, isFalse);
    });

    test('persists update state metadata', () async {
      final persistence = FakeUpdatePersistence();
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        persistence: persistence,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(persistence.saved.last.targetBuild, 131);
      expect(persistence.saved.last.targetVersion, '1.0.7');
      expect(persistence.saved.last.phase, AppUpdatePhase.readyToInstall);
      expect(persistence.saved.last.artifactRelativePath, contains('131'));
      expect(persistence.saved.last.fileSizeExpected, 123456789);
      expect(persistence.saved.last.sha256Expected, _sha);
    });

    test('recovers transient startup state', () async {
      final persistence = FakeUpdatePersistence(
        initial: PersistedUpdateState.initial().copyWith(
          phase: AppUpdatePhase.downloading,
        ),
      );
      final controller = _controller(
        manifest: UpdateManifest.noUpdate(),
        persistence: persistence,
      );

      await controller.checkNow(force: true);

      expect(
        persistence.saved.first.lastErrorCode,
        'RECOVERED_TRANSIENT_STATE',
      );
    });

    test(
      'dismissed build suppresses main prompt only for that build',
      () async {
        final controller = _controller(
          manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
          installedBuild: 130,
        );

        await controller.checkNow(force: true);
        await _drainBackgroundUpdate();
        await controller.dismissCurrentBuild();

        expect(controller.state.persisted.dismissedBuild, 131);
        expect(controller.state.hasVisibleMainPrompt, isFalse);
      },
    );

    test('new build after dismissed is not suppressed', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 132)),
        installedBuild: 130,
        persistence: FakeUpdatePersistence(
          initial: PersistedUpdateState.initial().copyWith(dismissedBuild: 131),
        ),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.manifest?.isDismissedBy(131), isFalse);
    });

    test(
      'non-Windows platforms are unsupported and do not call check',
      () async {
        final repository = FakeAppUpdateRepository(installedRelease: null);
        final controller = _controller(repository: repository);

        await controller.checkNow(force: true);

        expect(controller.state.phase, AppUpdatePhase.unsupported);
        expect(repository.checkCalls, 0);
      },
    );

    test('request install waits when restart guard blocks', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        restartGuard: const FakeRestartGuard(false),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();
      await controller.requestInstallPreparedUpdate();

      expect(controller.state.phase, AppUpdatePhase.waitingSafeState);
      expect(controller.installerLaunches, 0);
    });

    test('does not report financial side effects', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.financialSideEffects, isEmpty);
    });

    test('file size mismatch never reaches ready', () async {
      final downloader = FakeUpdateDownloader(failureCode: 'SIZE_MISMATCH');
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: downloader,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'SIZE_MISMATCH');
      expect(controller.state.persisted.artifactRelativePath, isNull);
    });

    test('sha mismatch never reaches ready and discards build', () async {
      final downloader = FakeUpdateDownloader();
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: downloader,
        verifier: const FakeUpdateVerifier(failureCode: 'HASH_MISMATCH'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'HASH_MISMATCH');
      expect(downloader.discardedBuilds, contains(131));
      expect(downloader.promoted, isFalse);
    });

    test('.part is never ready before verification and rename', () async {
      final downloader = FakeUpdateDownloader();
      final verifier = DelayedFakeUpdateVerifier();
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: downloader,
        verifier: verifier,
      );

      await controller.checkNow(force: true);
      await verifier.waitUntilCalled();

      expect(controller.state.phase, AppUpdatePhase.verifying);
      expect(controller.state.persisted.artifactRelativePath, isNull);
      expect(downloader.promoted, isFalse);

      verifier.complete();
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.readyToInstall);
      expect(downloader.promoted, isTrue);
    });

    test('rename final happens before ready persistence', () async {
      final downloader = FakeUpdateDownloader();
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: downloader,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(downloader.promoted, isTrue);
      expect(
        controller.state.persisted.artifactRelativePath,
        endsWith('.ready'),
      );
    });

    test(
      'restart during download recovers and discards partial build',
      () async {
        final downloader = FakeUpdateDownloader();
        final controller = _controller(
          manifest: UpdateManifest.noUpdate(),
          persistence: FakeUpdatePersistence(
            initial: PersistedUpdateState.initial().copyWith(
              phase: AppUpdatePhase.downloading,
              targetBuild: 131,
            ),
          ),
          downloader: downloader,
        );

        await controller.checkNow(force: true);

        expect(downloader.discardedBuilds, contains(131));
        expect(controller.state.persisted.lastErrorCode, isNull);
        expect(controller.state.phase, AppUpdatePhase.idle);
      },
    );

    test('restart during verify recovers and discards partial build', () async {
      final downloader = FakeUpdateDownloader();
      final controller = _controller(
        manifest: UpdateManifest.noUpdate(),
        persistence: FakeUpdatePersistence(
          initial: PersistedUpdateState.initial().copyWith(
            phase: AppUpdatePhase.verifying,
            targetBuild: 131,
          ),
        ),
        downloader: downloader,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(downloader.discardedBuilds, contains(131));
      expect(controller.state.phase, AppUpdatePhase.idle);
    });

    test('timeout is non-fatal install failure', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(failureCode: 'DOWNLOAD_TIMEOUT'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.blocksUsage, isFalse);
      expect(controller.state.persisted.lastErrorCode, 'DOWNLOAD_TIMEOUT');
    });

    test('404 is non-fatal install failure', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(failureCode: 'HTTP_404'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'HTTP_404');
    });

    test('disk write failure is non-fatal install failure', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(failureCode: 'DISK_WRITE_FAILED'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'DISK_WRITE_FAILED');
    });

    test('invalid fileName is rejected before ready', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(
          _manifestJson(build: 131, fileName: r'..\evil.exe'),
        ),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(failureCode: 'INVALID_FILE_NAME'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'INVALID_FILE_NAME');
    });

    test('invalid HTTPS URL is rejected before ready', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(failureCode: 'INVALID_DOWNLOAD_URL'),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.phase, AppUpdatePhase.installFailed);
      expect(controller.state.persisted.lastErrorCode, 'INVALID_DOWNLOAD_URL');
    });

    test('new build replaces older target build', () async {
      final downloader = FakeUpdateDownloader();
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 132)),
        installedBuild: 130,
        persistence: FakeUpdatePersistence(
          initial: PersistedUpdateState.initial().copyWith(
            phase: AppUpdatePhase.installFailed,
            targetBuild: 131,
          ),
        ),
        downloader: downloader,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(downloader.discardedBuilds, contains(131));
      expect(controller.state.persisted.targetBuild, 132);
      expect(controller.state.phase, AppUpdatePhase.readyToInstall);
    });

    test('revoked release invalidates local ready state', () async {
      final downloader = FakeUpdateDownloader();
      final controller = _controller(
        manifest: UpdateManifest.noUpdate(),
        installedBuild: 130,
        persistence: FakeUpdatePersistence(
          initial: PersistedUpdateState.initial().copyWith(
            phase: AppUpdatePhase.readyToInstall,
            targetBuild: 131,
            artifactRelativePath: '131/setup.exe.ready',
          ),
        ),
        downloader: downloader,
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(downloader.discardedBuilds, contains(131));
      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.persisted.targetBuild, isNull);
    });

    test('progress is kept internally without overlay', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
        downloader: FakeUpdateDownloader(),
      );

      await controller.checkNow(force: true);
      await _drainBackgroundUpdate();

      expect(controller.state.downloadProgress, 1);
      expect(controller.state.blocksUsage, isFalse);
      expect(controller.installerLaunches, 0);
    });
  });
}

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<void> _drainBackgroundUpdate() async {
  for (var i = 0; i < 10; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _manifestJson({
  int build = 131,
  String sha256 = _sha,
  String? fileName,
}) {
  return {
    'updateAvailable': true,
    'version': '1.0.7',
    'buildNumber': build,
    'fileName': fileName ?? 'Fullpos-Setup-1.0.7+$build.exe',
    'fileSize': 123456789,
    'sha256': sha256,
    'downloadUrl': 'https://downloads.example.com/setup.exe',
    'mandatory': false,
    'minimumSupportedBuild': null,
    'releaseNotes': ['Mejoras'],
    'publishedAt': '2026-10-06T12:00:00.000Z',
  };
}

TestAppUpdateController _controller({
  UpdateManifest? manifest,
  int installedBuild = 130,
  Object? error,
  FakeUpdatePersistence? persistence,
  FakeAppUpdateRepository? repository,
  UpdateRestartGuard restartGuard = const FakeRestartGuard(true),
  FakeUpdateDownloader? downloader,
  UpdateVerifier verifier = const FakeUpdateVerifier(),
}) {
  final repo =
      repository ??
      FakeAppUpdateRepository(
        installedRelease: InstalledReleaseInfo(
          platform: ReleasePlatform.windows,
          currentVersion: '1.0.6',
          currentBuild: installedBuild,
        ),
        manifest: manifest,
        error: error,
      );
  return TestAppUpdateController(
    repo,
    persistence ?? FakeUpdatePersistence(),
    restartGuard,
    downloader ?? FakeUpdateDownloader(),
    verifier,
  );
}

class TestAppUpdateController extends AppUpdateController {
  TestAppUpdateController(
    super.repository,
    super.persistence,
    super.guard,
    super.downloader,
    super.verifier,
  );

  int installerLaunches = 0;
  final List<String> financialSideEffects = [];
}

class FakeAppUpdateRepository extends AppUpdateRepository {
  FakeAppUpdateRepository({this.installedRelease, this.manifest, this.error});

  final InstalledReleaseInfo? installedRelease;
  final UpdateManifest? manifest;
  final Object? error;
  int checkCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<InstalledReleaseInfo?> readInstalledRelease() async =>
      installedRelease;

  @override
  Future<UpdateManifest> checkForUpdate(
    InstalledReleaseInfo installedRelease,
  ) async {
    checkCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return manifest ?? UpdateManifest.noUpdate();
  }
}

class FakeUpdatePersistence extends UpdatePersistence {
  FakeUpdatePersistence({PersistedUpdateState? initial})
    : initial = initial ?? PersistedUpdateState.initial(),
      super(const UpdateStateFileStore());

  final PersistedUpdateState initial;
  final List<PersistedUpdateState> saved = [];

  @override
  Future<PersistedUpdateState> load() async => initial.normalizeForStartup();

  @override
  Future<void> save(PersistedUpdateState state) async {
    saved.add(state);
  }
}

class FakeRestartGuard implements UpdateRestartGuard {
  const FakeRestartGuard(this.safe);

  final bool safe;

  @override
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate() async {
    return safe
        ? const UpdateRestartReadiness.safe()
        : const UpdateRestartReadiness.blocked('CRITICAL_OPERATION');
  }
}

class FakeUpdateDownloader extends UpdateDownloader {
  FakeUpdateDownloader({this.failureCode});

  final String? failureCode;
  final List<int> discardedBuilds = [];
  bool promoted = false;

  @override
  Future<UpdateDownloadResult> download(
    UpdateManifest manifest, {
    void Function(UpdateDownloadProgress progress)? onProgress,
  }) async {
    final code = failureCode;
    if (code != null) throw UpdateDownloadException(code);
    onProgress?.call(
      UpdateDownloadProgress(
        bytesDownloaded: (manifest.fileSize ?? 0) ~/ 2,
        totalBytes: manifest.fileSize ?? 0,
      ),
    );
    onProgress?.call(
      UpdateDownloadProgress(
        bytesDownloaded: manifest.fileSize ?? 0,
        totalBytes: manifest.fileSize ?? 0,
      ),
    );
    return UpdateDownloadResult(
      partPath: r'C:\updates\file.exe.part',
      readyPath: r'C:\updates\file.exe.ready',
      artifactRelativePath:
          '${manifest.buildNumber}/${manifest.fileName}.ready',
      bytesDownloaded: manifest.fileSize ?? 0,
      fileSizeExpected: manifest.fileSize ?? 0,
    );
  }

  @override
  Future<void> promoteToReady(UpdateDownloadResult result) async {
    promoted = true;
  }

  @override
  Future<void> discardBuild(int buildNumber) async {
    discardedBuilds.add(buildNumber);
  }
}

class FakeUpdateVerifier extends UpdateVerifier {
  const FakeUpdateVerifier({this.failureCode});

  final String? failureCode;

  @override
  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
  }) async {
    final code = failureCode;
    if (code != null) throw UpdateVerificationException(code);
  }
}

class DelayedFakeUpdateVerifier extends UpdateVerifier {
  final Completer<void> _called = Completer<void>();
  final Completer<void> _complete = Completer<void>();

  Future<void> waitUntilCalled() => _called.future;

  void complete() => _complete.complete();

  @override
  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
  }) async {
    if (!_called.isCompleted) _called.complete();
    await _complete.future;
  }
}
