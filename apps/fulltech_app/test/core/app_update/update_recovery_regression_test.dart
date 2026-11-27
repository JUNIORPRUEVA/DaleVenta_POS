import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daleventa_pos/core/app_update/app_update_controller.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store_io.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store.dart'
    as state_store;
import 'package:daleventa_pos/core/app_update/update_downloader.dart';
import 'package:daleventa_pos/core/app_update/update_trust_policy.dart';
import 'package:daleventa_pos/core/app_update/update_restart_guard.dart';
import 'app_update_controller_test.dart' as fixtures;

const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
UpdateManifest manifest() => UpdateManifest.fromJson({
  'updateAvailable': true,
  'version': '1.0.7',
  'buildNumber': 138,
  'fileName': 'audit.exe',
  'fileSize': 123456789,
  'sha256': hash,
  'downloadUrl': 'https://downloads.example.com/setup.exe',
  'signed': false,
  'publishedAt': '2026-11-27T00:00:00Z',
});
PersistedUpdateState prepared() => PersistedUpdateState.initial().copyWith(
  phase: AppUpdatePhase.readyToInstall,
  targetBuild: 138,
  targetVersion: '1.0.7',
  artifactRelativePath: '138/audit.exe.ready',
  fileSizeExpected: 123456789,
  sha256Expected: hash,
  signatureStatus: 'NotSigned',
  signatureAcceptedBy: 'ProductionUnsignedPolicy',
);
AppUpdateController controller(
  PersistedUpdateState initial,
  fixtures.FakeUpdateDownloader downloader, {
  Object? error,
  fixtures.FakeAppUpdateInstaller? installer,
  UpdatePersistence? persistence,
  UpdateRestartGuard? guard,
  fixtures.FakeAppUpdateRepository? repository,
}) {
  final app = AppUpdateController(
    repository ??
        fixtures.FakeAppUpdateRepository(
          installedRelease: const InstalledReleaseInfo(
            platform: ReleasePlatform.windows,
            currentVersion: '1.0.6',
            currentBuild: 137,
          ),
          manifest: manifest(),
          error: error,
        ),
    persistence ?? fixtures.FakeUpdatePersistence(initial: initial),
    guard ?? const fixtures.FakeRestartGuard(true),
    downloader,
    const fixtures.FakeUpdateVerifier(),
    fixtures.FakeUpdateSignatureVerifier(),
    installer ?? fixtures.FakeAppUpdateInstaller(),
    const UpdateTrustPolicy(
      allowUnsignedProduction: true,
      allowedHosts: {'downloads.example.com'},
    ),
  );
  addTearDown(app.dispose);
  return app;
}

Future<void> settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'actual installed target confirms offline despite old failure metadata',
    () async {
      final repo = fixtures.FakeAppUpdateRepository(
        installedRelease: const InstalledReleaseInfo(
          platform: ReleasePlatform.windows,
          currentVersion: '1.0.7',
          currentBuild: 138,
        ),
        error: const SocketException('offline'),
      );
      final app = controller(
        prepared().copyWith(
          phase: AppUpdatePhase.installFailed,
          lastUpdateResult: 'UPDATER_RESULT_MISSING',
        ),
        fixtures.FakeUpdateDownloader(
          installerResult: const UpdateInstallerResult(
            targetBuild: 138,
            result: 'UAC_CANCELLED',
            exitCode: 1223,
          ),
        ),
        repository: repo,
      );
      await app.checkNow(force: true);
      expect(app.state.phase, AppUpdatePhase.installedConfirmed);
      expect(repo.checkCalls, 0);
    },
  );
  test(
    'handled UAC cancellation does not prevent later release checks',
    () async {
      final repo = fixtures.FakeAppUpdateRepository(
        installedRelease: const InstalledReleaseInfo(
          platform: ReleasePlatform.windows,
          currentVersion: '1.0.6',
          currentBuild: 137,
        ),
        manifest: manifest(),
      );
      final app = controller(
        prepared().copyWith(lastUpdateResult: 'UAC_CANCELLED'),
        fixtures.FakeUpdateDownloader(
          installerResult: const UpdateInstallerResult(
            targetBuild: 138,
            result: 'UAC_CANCELLED',
            exitCode: 1223,
          ),
        ),
        repository: repo,
      );
      await app.checkNow(force: true);
      expect(repo.checkCalls, 1);
      expect(app.state.phase, AppUpdatePhase.readyToInstall);
    },
  );
  test(
    'streaming progress does not enqueue one disk write per chunk',
    () async {
      final persistence = fixtures.FakeUpdatePersistence();
      final app = controller(
        PersistedUpdateState.initial(),
        ManyChunksDownloader(),
        persistence: persistence,
      );
      await app.checkNow(force: true);
      await settle();
      expect(app.state.phase, AppUpdatePhase.readyToInstall);
      expect(persistence.saved.length, lessThan(12));
    },
  );
  test(
    'actual restart guard releases reservation when launching fails',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final app = controller(
        prepared(),
        fixtures.FakeUpdateDownloader(),
        installer: fixtures.FakeAppUpdateInstaller(failLaunch: true),
        guard: container.read(updateRestartGuardProvider),
      );
      await app.checkNow(force: true);
      await app.requestInstallPreparedUpdate();
      expect(app.state.phase, AppUpdatePhase.installFailed);
      expect(UpdateCriticalOperationGate.instance.restartReserved, isFalse);
      await UpdateCriticalOperationGate.instance.run(() async {});
    },
  );
  test(
    'prepared package survives failed check and restart without redownload',
    () async {
      final downloader = fixtures.FakeUpdateDownloader();
      final offline = controller(
        prepared(),
        downloader,
        error: const SocketException('isolated offline'),
      );
      await offline.checkNow(force: true);
      expect(offline.state.phase, AppUpdatePhase.readyToInstall);
      expect(offline.state.persisted.phase, AppUpdatePhase.readyToInstall);
      final restarted = controller(offline.state.persisted, downloader);
      await restarted.checkNow(force: true);
      await settle();
      expect(restarted.state.phase, AppUpdatePhase.readyToInstall);
      expect(downloader.downloads, 0);
    },
  );
  test('simultaneous install requests perform one handoff', () async {
    final installer = fixtures.FakeAppUpdateInstaller();
    final app = controller(
      prepared(),
      fixtures.FakeUpdateDownloader(),
      installer: installer,
    );
    await app.checkNow(force: true);
    await Future.wait([
      app.requestInstallPreparedUpdate(),
      app.requestInstallPreparedUpdate(),
    ]);
    expect(installer.launches, 1);
  });
  for (final phase in [
    AppUpdatePhase.waitingSafeState,
    AppUpdatePhase.installRequested,
  ]) {
    test(
      'restart during $phase preserves package and does not install automatically',
      () async {
        final downloader = fixtures.FakeUpdateDownloader();
        final installer = fixtures.FakeAppUpdateInstaller();
        final app = controller(
          prepared().copyWith(phase: phase),
          downloader,
          installer: installer,
        );
        await app.checkNow(force: true);
        await settle();
        expect(app.state.phase, AppUpdatePhase.readyToInstall);
        expect(downloader.downloads, 0);
        expect(downloader.discardedBuilds, isEmpty);
        expect(installer.launches, 0);
      },
    );
  }
  test(
    'failed installer can retry cached package offline after restart',
    () async {
      final downloader = fixtures.FakeUpdateDownloader(
        installerResult: const UpdateInstallerResult(
          targetBuild: 138,
          result: 'INSTALLER_FAILED',
          exitCode: 1,
        ),
      );
      final installer = fixtures.FakeAppUpdateInstaller();
      final app = controller(
        prepared().copyWith(phase: AppUpdatePhase.updaterStarted),
        downloader,
        installer: installer,
        error: const SocketException('offline'),
      );
      await app.checkNow(force: true);
      expect(app.state.phase, AppUpdatePhase.installFailed);
      expect(app.state.manifest, isNull);
      await app.requestInstallPreparedUpdate();
      expect(installer.launches, 1);
      expect(downloader.downloads, 0);
    },
  );
  test(
    'missing prepared package is downloaded again instead of trusting metadata',
    () async {
      final downloader = MissingPreparedDownloader();
      final app = controller(prepared(), downloader);
      await app.checkNow(force: true);
      await settle();
      expect(downloader.downloads, 1);
    },
  );
  test(
    'durable write failure never advertises READY or launches installer',
    () async {
      final persistence = UpdatePersistence(FailingStore());
      final installer = fixtures.FakeAppUpdateInstaller();
      final app = controller(
        prepared(),
        fixtures.FakeUpdateDownloader(),
        installer: installer,
        persistence: persistence,
      );
      await app.checkNow(force: true);
      await settle();
      expect(app.state.phase, AppUpdatePhase.installFailed);
      expect(app.state.persisted.lastErrorCode, 'STATE_WRITE_FAILED');
      await app.requestInstallPreparedUpdate();
      expect(installer.launches, 0);
    },
  );
  test(
    'file store isolates corrupt old builds and recovers interrupted replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fullpos-updater-state-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = UpdateStateFileStore(rootDirectory: root);
      await store.writeJson(prepared().toJson());
      final corrupt = File('${root.path}/1/update_state.json');
      await corrupt.parent.create(recursive: true);
      await corrupt.writeAsString('{');
      expect((await store.readJson())?['targetBuild'], 138);
      final current = File('${root.path}/138/update_state.json');
      final next = prepared().copyWith(
        dismissedBuild: 138,
        updatedAt: DateTime.now().add(const Duration(seconds: 1)),
      );
      await File(
        '${current.path}.tmp',
      ).writeAsString(jsonEncode(next.toJson()), flush: true);
      await current.rename('${current.path}.bak');
      expect((await store.readJson())?['dismissedBuild'], 138);
      await File('${current.path}.tmp').writeAsString('{broken');
      expect((await store.readJson())?['targetBuild'], 138);
      expect((await store.readJson())?['dismissedBuild'], isNull);
    },
  );
  test(
    'critical gate covers nested and detached work and releases on errors',
    () async {
      final gate = UpdateCriticalOperationGate();
      final finish = Completer<void>();
      Future<void>? detached;
      await gate.run(() async {
        detached = gate.run(() => finish.future);
      });
      expect(gate.reserveRestart(), isFalse);
      finish.complete();
      await detached;
      await expectLater(
        gate.run(() async {
          throw StateError('test');
        }),
        throwsStateError,
      );
      expect(gate.hasActiveCriticalOperation, isFalse);
      expect(gate.reserveRestart(), isTrue);
      await expectLater(gate.run(() async {}), throwsException);
      gate.releaseRestart();
      await gate.run(() async {});
    },
  );
}

class MissingPreparedDownloader extends fixtures.FakeUpdateDownloader {
  @override
  Future<String> resolvePreparedArtifact(PersistedUpdateState state) async =>
      throw const UpdateDownloadException('PREPARED_FILE_INVALID');
}

class ManyChunksDownloader extends fixtures.FakeUpdateDownloader {
  @override
  Future<UpdateDownloadResult> download(
    UpdateManifest manifest, {
    void Function(UpdateDownloadProgress progress)? onProgress,
  }) async {
    for (var i = 1; i <= 1000; i++) {
      onProgress?.call(
        UpdateDownloadProgress(
          bytesDownloaded: manifest.fileSize! * i ~/ 1000,
          totalBytes: manifest.fileSize!,
        ),
      );
    }
    return super.download(manifest);
  }
}

class FailingStore extends state_store.UpdateStateFileStore {
  @override
  Future<Map<String, dynamic>?> readJson() async => prepared().toJson();
  @override
  Future<void> writeJson(Map<String, dynamic> json) async =>
      throw const FileSystemException('disk unavailable');
}
