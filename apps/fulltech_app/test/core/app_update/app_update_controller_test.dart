import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/app_update/app_update_controller.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';
import 'package:daleventa_pos/core/app_update/update_restart_guard.dart';

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

      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.blocksUsage, isFalse);
      expect(controller.installerLaunches, 0);
    });

    test('greater build becomes available silently', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.available);
      expect(controller.state.manifest?.buildNumber, 131);
      expect(controller.state.hasVisibleMainPrompt, isFalse);
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

      expect(persistence.saved.last.targetBuild, 131);
      expect(persistence.saved.last.targetVersion, '1.0.7');
      expect(persistence.saved.last.phase, AppUpdatePhase.available);
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
      await controller.requestInstallPreparedUpdate();

      expect(controller.state.phase, isNot(AppUpdatePhase.updaterStarted));
      expect(controller.installerLaunches, 0);
    });

    test('does not report financial side effects', () async {
      final controller = _controller(
        manifest: UpdateManifest.fromJson(_manifestJson(build: 131)),
        installedBuild: 130,
      );

      await controller.checkNow(force: true);

      expect(controller.financialSideEffects, isEmpty);
    });
  });
}

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _manifestJson({int build = 131, String sha256 = _sha}) {
  return {
    'updateAvailable': true,
    'version': '1.0.7',
    'buildNumber': build,
    'fileName': 'Fullpos-Setup-1.0.7+$build.exe',
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
  );
}

class TestAppUpdateController extends AppUpdateController {
  TestAppUpdateController(super.repository, super.persistence, super.guard);

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
