import 'package:daleventa_pos/core/app_update/app_update_controller.dart';
import 'package:daleventa_pos/core/app_update/app_update_installer_contract.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';
import 'package:daleventa_pos/core/app_update/update_downloader.dart';
import 'package:daleventa_pos/core/app_update/update_restart_guard.dart';
import 'package:daleventa_pos/core/app_update/update_signature_verifier.dart';
import 'package:daleventa_pos/core/app_update/update_trust_policy.dart';
import 'package:daleventa_pos/core/app_update/update_verifier.dart';
import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/debug/error_notice_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El actualizador NUNCA puede interrumpir la venta.
///
/// Caso real (cliente Windows con build UAT): `WindowsProductPaths` lanza
/// `Build UAT sin almacenamiento aislado` al resolver la carpeta de estado. La
/// excepción escapaba por `checkNow()` hasta el manejador global y el POS
/// mostraba un aviso técnico. Estas pruebas fijan las dos fronteras: la
/// persistencia y la comprobación de actualizaciones.
const String _uatError =
    'Build UAT sin almacenamiento aislado: define DALEVENTAS_POS_ROOT con una '
    'carpeta exclusiva de pruebas antes de abrir la aplicación.';

const String _updaterTitle = 'No pudimos comprobar las actualizaciones.';
const String _updaterMessage = 'Puedes seguir utilizando FullPOS normalmente.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ErrorNoticeGate.instance.resetForTest();
    AppErrorReporter.instance.resetForTesting();
  });

  tearDown(() {
    ErrorNoticeGate.instance.resetForTest();
    AppErrorReporter.instance.resetForTesting();
  });

  group('UpdatePersistence — errores de almacenamiento', () {
    test('guardar jamás propaga, aunque el almacenamiento falle', () async {
      final persistence = UpdatePersistence(const _UnresolvableStore());

      await expectLater(
        persistence.save(PersistedUpdateState.initial()),
        completes,
      );
    });

    test('leer degrada a STATE_READ_FAILED en lugar de lanzar', () async {
      final persistence = UpdatePersistence(const _UnresolvableStore());

      final persisted = await persistence.load();

      expect(persisted.lastErrorCode, 'STATE_READ_FAILED');
    });

    test('varios guardados fallidos no acumulan errores', () async {
      final store = _CountingFailingStore();
      final persistence = UpdatePersistence(store);

      for (var i = 0; i < 3; i += 1) {
        await expectLater(
          persistence.save(PersistedUpdateState.initial()),
          completes,
        );
      }

      expect(store.attempts, 3);
    });
  });

  group('AppUpdateController — frontera del actualizador', () {
    test('un fallo al leer la instalación no lanza ni bloquea el POS', () async {
      final controller = _controller(repository: _ThrowingRepository());

      await expectLater(controller.checkNow(force: true), completes);

      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.blocksUsage, isFalse);
    });

    test('el aviso del actualizador usa texto de negocio, no técnico', () async {
      final controller = _controller(repository: _ThrowingRepository());

      await controller.checkNow(force: true);

      final notice = AppErrorReporter.instance.lastError.value;
      expect(notice, isNotNull);
      expect(notice!.title, _updaterTitle);
      expect(notice.userMessage, _updaterMessage);
      expect(notice.severity, AppErrorSeverity.warning);
      expect(notice.userMessage, isNot(contains('DALEVENTAS_POS_ROOT')));
      expect(notice.userMessage, isNot(contains('StateError')));
      // La causa real se conserva para diagnóstico técnico.
      expect(AppErrorReporter.instance.lastRecorded.value?.message, isNotNull);
    });

    test('una comprobación correcta no genera ningún aviso', () async {
      final controller = _controller(repository: _InstalledRepository());

      await controller.checkNow(force: true);

      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(AppErrorReporter.instance.lastError.value, isNull);
      expect(ErrorNoticeGate.instance.shouldShow('updater'), isTrue);
    });

    test('tras recuperarse, el siguiente fallo vuelve a informar sólo una vez',
        () async {
      final controller = _controller(repository: _ThrowingRepository());
      await controller.checkNow(force: true);
      expect(AppErrorReporter.instance.lastError.value, isNotNull);

      // El cliente cierra el aviso y sigue vendiendo.
      AppErrorReporter.instance.clear();
      await controller.checkNow(force: true);

      expect(
        AppErrorReporter.instance.lastError.value,
        isNull,
        reason: 'El mismo fallo no puede reaparecer el mismo día.',
      );
      expect(controller.state.phase, AppUpdatePhase.idle);
      expect(controller.state.blocksUsage, isFalse);
    });
  });
}

AppUpdateController _controller({required AppUpdateRepository repository}) {
  return AppUpdateController(
    repository,
    _InMemoryPersistence(),
    _AlwaysSafeRestartGuard(),
    UpdateDownloader(),
    const UpdateVerifier(),
    UpdateSignatureVerifier(),
    _NoopInstaller(),
    const UpdateTrustPolicy(
      allowUnsignedProduction: true,
      allowedHosts: {'downloads.example.com'},
    ),
  );
}

/// Almacenamiento que no puede resolver su carpeta: reproduce exactamente el
/// fallo de una build UAT instalada sin `DALEVENTAS_POS_ROOT`.
class _UnresolvableStore extends UpdateStateFileStore {
  const _UnresolvableStore();

  @override
  Future<Map<String, dynamic>?> readJson() async => throw StateError(_uatError);

  @override
  Future<void> writeJson(Map<String, dynamic> json) async =>
      throw StateError(_uatError);
}

class _CountingFailingStore extends UpdateStateFileStore {
  int attempts = 0;

  @override
  Future<Map<String, dynamic>?> readJson() async => null;

  @override
  Future<void> writeJson(Map<String, dynamic> json) async {
    attempts += 1;
    throw StateError(_uatError);
  }
}

class _InMemoryPersistence extends UpdatePersistence {
  _InMemoryPersistence() : super(const UpdateStateFileStore());

  @override
  Future<PersistedUpdateState> load() async =>
      PersistedUpdateState.initial().normalizeForStartup();

  @override
  Future<void> save(PersistedUpdateState state) async {}
}

class _ThrowingRepository extends AppUpdateRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<InstalledReleaseInfo?> readInstalledRelease() async {
    throw StateError(_uatError);
  }
}

class _InstalledRepository extends AppUpdateRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<InstalledReleaseInfo?> readInstalledRelease() async {
    return const InstalledReleaseInfo(
      platform: ReleasePlatform.windows,
      currentVersion: '1.0.7',
      currentBuild: 151,
    );
  }

  @override
  Future<UpdateManifest> checkForUpdate(
    InstalledReleaseInfo installedRelease,
  ) async {
    return UpdateManifest.noUpdate();
  }
}

class _AlwaysSafeRestartGuard extends UpdateRestartGuard {
  @override
  Future<UpdateRestartReadiness> canSafelyRestartForUpdate() async =>
      const UpdateRestartReadiness.safe();
}

class _NoopInstaller implements AppUpdateInstaller {
  @override
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  }) async {}

  @override
  Future<void> launchPreparedWindowsUpdate({
    required PersistedUpdateState persisted,
  }) async {}
}
