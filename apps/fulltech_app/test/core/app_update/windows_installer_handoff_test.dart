import 'package:daleventa_pos/core/app_update/app_update_installer_contract.dart';
import 'package:daleventa_pos/core/app_update/app_update_installer_io.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  });

  test('disabled updates reject a cached prepared artifact before handoff', () async {
    dotenv.env['DISABLE_APP_UPDATES'] = 'true';
    await rejected(_prepared(131), 'deshabilitadas');
  });

  for (final target in [129, 130]) {
    test('cached target $target cannot replace installed build 130', () async {
      await rejected(_prepared(target), 'más reciente');
    });
  }

  test('unverifiable installed build cannot launch a prepared package', () async {
    PackageInfo.setMockInitialValues(appName: 'FullPOS UAT', packageName: 'uat',
      version: '1.0.6', buildNumber: 'invalid', buildSignature: '');
    await rejected(_prepared(131), 'versión instalada');
  });
}

PersistedUpdateState _prepared(int build) => PersistedUpdateState.initial().copyWith(
  phase: AppUpdatePhase.readyToInstall, targetBuild: build,
  artifactRelativePath: '$build/fixture.exe.ready', sha256Expected: 'a' * 64,
  signatureStatus: 'NotSigned', signatureAcceptedBy: 'ProductionUnsignedPolicy',
);
