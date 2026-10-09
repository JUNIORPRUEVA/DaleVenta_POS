import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/env.dart';
import '../debug/trace_log.dart';
import 'app_update_installer_contract.dart';
import 'app_update_models.dart';

AppUpdateInstaller createAppUpdateInstaller() =>
    const WindowsAppUpdateInstaller();

class WindowsAppUpdateInstaller implements AppUpdateInstaller {
  const WindowsAppUpdateInstaller();

  @override
  Future<void> launchPreparedWindowsUpdate({
    required PersistedUpdateState persisted,
  }) async {
    if (!Platform.isWindows) {
      throw const AppUpdateInstallException(
        'La instalación automática solo está disponible en Windows.',
      );
    }
    final targetBuild = persisted.targetBuild;
    final artifactRelativePath = persisted.artifactRelativePath;
    final expectedSha256 = persisted.sha256Expected;
    if (targetBuild == null ||
        artifactRelativePath == null ||
        expectedSha256 == null) {
      throw const AppUpdateInstallException(
        'La actualización no está lista para instalar.',
      );
    }

    final publisher = Env.expectedUpdatePublisher;
    final allowUnsigned = Env.allowUnsignedUpdatesForUat;
    if (!allowUnsigned && publisher.isEmpty) {
      throw const AppUpdateInstallException(
        'Falta configurar el publisher esperado para validar la actualización.',
      );
    }

    final updateRoot = _defaultUpdateRoot();
    final packagePath = p.normalize(
      p.join(updateRoot.path, artifactRelativePath),
    );
    final updater = _resolveUpdaterExecutable();
    if (!await updater.exists()) {
      throw const AppUpdateInstallException(
        'No se encontró el actualizador seguro de Windows.',
      );
    }

    final logPath = _updateLogPath(targetBuild);
    await File(logPath).parent.create(recursive: true);

    final args = <String>[
      '--package',
      packagePath,
      '--parent-pid',
      pid.toString(),
      '--target-build',
      targetBuild.toString(),
      '--restart-exe',
      Platform.resolvedExecutable,
      '--log-path',
      logPath,
      '--update-root',
      updateRoot.path,
      '--expected-sha256',
      expectedSha256,
      '--expected-publisher',
      publisher,
      if (allowUnsigned) '--allow-unsigned',
    ];

    TraceLog.log('AppUpdate', 'launching FullposUpdater.exe');
    await Process.start(
      updater.path,
      args,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        exit(0);
      }),
    );
  }

  @override
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  }) async {
    throw const AppUpdateInstallException(
      'La descarga directa fue reemplazada por el flujo seguro de actualización preparada.',
    );
  }

  Directory _defaultUpdateRoot() {
    final localAppData = (Platform.environment['LOCALAPPDATA'] ?? '').trim();
    if (localAppData.isNotEmpty) {
      return Directory(p.join(localAppData, 'DaleVentas POS', 'updates'));
    }
    return Directory(
      p.join(
        Platform.environment['USERPROFILE'] ?? '.',
        'AppData',
        'Local',
        'DaleVentas POS',
        'updates',
      ),
    );
  }

  File _resolveUpdaterExecutable() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final installedRoot = p.dirname(exeDir);
    final candidates = <String>[
      p.join(installedRoot, 'updater', 'FullposUpdater.exe'),
      p.join(exeDir, 'updater', 'FullposUpdater.exe'),
    ];
    return File(
      candidates.firstWhere(
        (path) => File(path).existsSync(),
        orElse: () => candidates.first,
      ),
    );
  }

  String _updateLogPath(int targetBuild) {
    final localAppData = (Platform.environment['LOCALAPPDATA'] ?? '').trim();
    final root = localAppData.isNotEmpty
        ? localAppData
        : p.join(
            Platform.environment['USERPROFILE'] ?? '.',
            'AppData',
            'Local',
          );
    return p.join(
      root,
      'DaleVentas POS',
      'logs',
      'updates',
      'update-$targetBuild.log',
    );
  }
}
