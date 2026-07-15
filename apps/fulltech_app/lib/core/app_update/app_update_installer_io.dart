import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/env.dart';
import '../debug/trace_log.dart';
import 'app_update_installer_contract.dart';
import 'app_update_models.dart';

AppUpdateInstaller createAppUpdateInstaller() =>
    const WindowsAppUpdateInstaller();

class WindowsAppUpdateInstaller implements AppUpdateInstaller {
  const WindowsAppUpdateInstaller();

  static const Duration _downloadTimeout = Duration(minutes: 10);

  @override
  Future<void> downloadAndLaunchWindowsInstaller(
    AppUpdateInfo updateInfo, {
    required void Function(double progress) onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw const AppUpdateInstallException(
        'La instalación automática solo está disponible en Windows.',
      );
    }

    final downloadUrl = (updateInfo.downloadUrl ?? '').trim();
    if (downloadUrl.isEmpty) {
      throw const AppUpdateInstallException(
        'El release de Windows no tiene un enlace de descarga válido.',
      );
    }

    final seq = TraceLog.nextSeq();
    TraceLog.log('AppUpdate', 'windows auto-update download start', seq: seq);

    final targetFile = await _resolveTargetFile(updateInfo);
    final dio = Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        sendTimeout: _downloadTimeout,
        receiveTimeout: _downloadTimeout,
        followRedirects: true,
        responseType: ResponseType.bytes,
      ),
    );

    try {
      await dio.download(
        downloadUrl,
        targetFile.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress((received / total).clamp(0, 1).toDouble());
        },
      );

      onProgress(1);
      await _launchInstaller(targetFile.path);

      TraceLog.log(
        'AppUpdate',
        'windows auto-update installer launched',
        seq: seq,
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          exit(0);
        }),
      );
    } on DioException catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'windows auto-update download failed',
        seq: seq,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppUpdateInstallException(
        'No se pudo descargar el instalador de Windows. Verifica la URL del release y la conectividad.',
      );
    } catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'windows auto-update launch failed',
        seq: seq,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppUpdateInstallException(
        'No se pudo iniciar el instalador automático de Windows.',
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<File> _resolveTargetFile(AppUpdateInfo updateInfo) async {
    final tempDir = await getTemporaryDirectory();
    final targetDir = Directory(p.join(tempDir.path, 'fulltech_updates'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final fileName = _buildFileName(updateInfo);
    return File(p.join(targetDir.path, fileName));
  }

  String _buildFileName(AppUpdateInfo updateInfo) {
    final uri = Uri.tryParse(updateInfo.downloadUrl ?? '');
    final candidate = uri != null && uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : '';
    final sanitized = candidate.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isNotEmpty) {
      return sanitized;
    }

    final buildSuffix =
        updateInfo.latestBuild?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return 'fulltech_update_$buildSuffix.exe';
  }

  Future<void> _launchInstaller(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();

    if (extension == '.msi') {
      await Process.start(
        'msiexec',
        ['/i', filePath, '/quiet', '/norestart'],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return;
    }

    if (extension == '.exe') {
      await Process.start(
        filePath,
        const ['/VERYSILENT', '/NORESTART', '/SP-'],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return;
    }

    await Process.start(
      'explorer.exe',
      [filePath],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  }
}
