import 'dart:io';

import 'package:daleventa_pos/core/app_update/app_update_installer_contract.dart';
import 'package:daleventa_pos/core/app_update/app_update_installer_io.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

// El instalador de actualizaciones es API Win32: `app_update_installer_io.dart`
// rechaza cualquier otro sistema con UNSUPPORTED_PLATFORM. Estas pruebas
// necesitan Windows y se omiten (con motivo explícito) en Linux; el job
// `windows-updater` de CI las ejecuta de verdad en windows-latest.
final bool _notWindows = !Platform.isWindows;
const String _windowsOnlyReason = 'Requiere Windows: instalación Win32';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: '''
DISABLE_APP_UPDATES=false
ALLOW_UNSIGNED_UPDATES_FOR_UAT=false
ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false
EXPECTED_UPDATE_PUBLISHER=
''');
    PackageInfo.setMockInitialValues(appName: 'FullPOS UAT', packageName: 'uat',
      version: '1.0.6', buildNumber: '130', buildSignature: '');
  });

  Future<void> rejected(PersistedUpdateState state, String message) async {
    await expectLater(
      const WindowsAppUpdateInstaller().launchPreparedWindowsUpdate(persisted: state),
      throwsA(isA<AppUpdateInstallException>().having((error) => error.message,
        'message', contains(message))),
    );
  }

  test('cached unsigned approval cannot override current signed-only policy', () async {
    await rejected(_prepared(131), 'publisher esperado');
  }, skip: _notWindows ? _windowsOnlyReason : null);

  test('disabled updates reject a cached prepared artifact before handoff', () async {
    dotenv.env['DISABLE_APP_UPDATES'] = 'true';
    await rejected(_prepared(131), 'deshabilitadas');
  }, skip: _notWindows ? _windowsOnlyReason : null);

  for (final target in [129, 130]) {
    test('cached target $target cannot replace installed build 130', () async {
      await rejected(_prepared(target), 'más reciente');
    }, skip: _notWindows ? _windowsOnlyReason : null);
  }

  test('unverifiable installed build cannot launch a prepared package', () async {
    PackageInfo.setMockInitialValues(appName: 'FullPOS UAT', packageName: 'uat',
      version: '1.0.6', buildNumber: 'invalid', buildSignature: '');
    await rejected(_prepared(131), 'versión instalada');
  }, skip: _notWindows ? _windowsOnlyReason : null);
}

PersistedUpdateState _prepared(int build) => PersistedUpdateState.initial().copyWith(
  phase: AppUpdatePhase.readyToInstall, targetBuild: build,
  artifactRelativePath: '$build/fixture.exe.ready', sha256Expected: 'a' * 64,
  signatureStatus: 'NotSigned', signatureAcceptedBy: 'ProductionUnsignedPolicy',
);
