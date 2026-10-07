import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/env.dart';
import 'app_update_models.dart';

final updateDownloaderProvider = Provider<UpdateDownloader>((ref) {
  return UpdateDownloader();
});

class UpdateDownloadException implements Exception {
  final String code;
  final Object? cause;

  const UpdateDownloadException(this.code, [this.cause]);

  @override
  String toString() => 'UpdateDownloadException($code)';
}

class UpdateDownloadResult {
  final String partPath;
  final String readyPath;
  final String artifactRelativePath;
  final String updateRootPath;
  final int bytesDownloaded;
  final int fileSizeExpected;

  const UpdateDownloadResult({
    required this.partPath,
    required this.readyPath,
    required this.artifactRelativePath,
    required this.updateRootPath,
    required this.bytesDownloaded,
    required this.fileSizeExpected,
  });
}

class UpdateInstallerResult {
  final int targetBuild;
  final String result;
  final int? exitCode;
  final DateTime? timestamp;

  const UpdateInstallerResult({
    required this.targetBuild,
    required this.result,
    this.exitCode,
    this.timestamp,
  });
}

class UpdateDownloader {
  UpdateDownloader({Dio? dio, Directory? rootDirectory})
    : _dio = dio,
      _rootDirectory = rootDirectory;

  final Dio? _dio;
  final Directory? _rootDirectory;

  Future<UpdateDownloadResult> download(
    UpdateManifest manifest, {
    void Function(UpdateDownloadProgress progress)? onProgress,
  }) async {
    if (kIsWeb || !Platform.isWindows) {
      throw const UpdateDownloadException('UNSUPPORTED_PLATFORM');
    }

    final build = manifest.buildNumber;
    final expectedSize = manifest.fileSize;
    final url = _validateUrl(manifest.downloadUrl);
    final fileName = _validateFileName(manifest.fileName);
    if (build == null ||
        build <= 0 ||
        expectedSize == null ||
        expectedSize <= 0) {
      throw const UpdateDownloadException('INVALID_MANIFEST');
    }

    final buildDirectory = await _buildDirectory(build);
    final updateRoot = buildDirectory.parent;
    await buildDirectory.create(recursive: true);

    final partFile = File(p.join(buildDirectory.path, '$fileName.part'));
    final readyFile = File(p.join(buildDirectory.path, '$fileName.ready'));
    await _deleteIfExists(partFile);

    final dio = _dio ?? _createDio();
    IOSink? sink;
    var bytesDownloaded = 0;

    try {
      final response = await dio.get<ResponseBody>(
        url.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200) {
        throw UpdateDownloadException(
          statusCode == 404 ? 'HTTP_404' : 'DOWNLOAD_HTTP_ERROR',
        );
      }

      sink = partFile.openWrite();
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        onProgress?.call(
          UpdateDownloadProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: expectedSize,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final actualSize = await partFile.length();
      if (actualSize != expectedSize || bytesDownloaded != expectedSize) {
        await _deleteIfExists(partFile);
        throw const UpdateDownloadException('SIZE_MISMATCH');
      }

      return UpdateDownloadResult(
        partPath: partFile.path,
        readyPath: readyFile.path,
        artifactRelativePath: p.join(build.toString(), '$fileName.ready'),
        updateRootPath: updateRoot.path,
        bytesDownloaded: bytesDownloaded,
        fileSizeExpected: expectedSize,
      );
    } on UpdateDownloadException {
      rethrow;
    } on FileSystemException catch (error) {
      await _deleteIfExists(partFile);
      throw UpdateDownloadException('DISK_WRITE_FAILED', error);
    } on DioException catch (error) {
      await _deleteIfExists(partFile);
      final statusCode = error.response?.statusCode;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw UpdateDownloadException('DOWNLOAD_TIMEOUT', error);
      }
      throw UpdateDownloadException(
        statusCode == 404 ? 'HTTP_404' : 'DOWNLOAD_FAILED',
        error,
      );
    } catch (error) {
      await _deleteIfExists(partFile);
      throw UpdateDownloadException('DOWNLOAD_FAILED', error);
    } finally {
      if (sink != null) {
        await sink.close();
      }
      if (_dio == null) dio.close(force: true);
    }
  }

  Future<void> promoteToReady(UpdateDownloadResult result) async {
    final partFile = File(result.partPath);
    final readyFile = File(result.readyPath);
    if (!await partFile.exists()) {
      throw const UpdateDownloadException('PART_FILE_MISSING');
    }
    await readyFile.parent.create(recursive: true);
    await _deleteIfExists(readyFile);
    await partFile.rename(readyFile.path);
    if (!await readyFile.exists()) {
      throw const UpdateDownloadException('READY_FILE_MISSING');
    }
  }

  Future<void> discardBuild(int buildNumber) async {
    if (buildNumber <= 0) return;
    final directory = await _buildDirectory(buildNumber);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<UpdateInstallerResult?> readInstallerResult(int buildNumber) async {
    if (buildNumber <= 0) return null;
    final directory = await _buildDirectory(buildNumber);
    final file = File(p.join(directory.path, 'installer_result.json'));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final result = decoded['result']?.toString().trim().toUpperCase();
      if (result == null || result.isEmpty) return null;
      return UpdateInstallerResult(
        targetBuild:
            int.tryParse(decoded['targetBuild']?.toString() ?? '') ??
            buildNumber,
        result: result,
        exitCode: int.tryParse(decoded['exitCode']?.toString() ?? ''),
        timestamp: DateTime.tryParse(decoded['timestamp']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        headers: {'Accept': 'application/octet-stream'},
      ),
    );
  }

  Future<Directory> _buildDirectory(int buildNumber) async {
    final root = _rootDirectory ?? await _defaultRoot();
    return Directory(p.join(root.path, buildNumber.toString()));
  }

  Future<Directory> _defaultRoot() async {
    if (Platform.isWindows) {
      final localAppData = (Platform.environment['LOCALAPPDATA'] ?? '').trim();
      if (localAppData.isNotEmpty) {
        return Directory(p.join(localAppData, 'DaleVentas POS', 'updates'));
      }
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'updates'));
  }

  Uri _validateUrl(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority) {
      throw const UpdateDownloadException('INVALID_DOWNLOAD_URL');
    }
    return uri;
  }

  String _validateFileName(String? value) {
    final fileName = (value ?? '').trim();
    final hasSeparator = fileName.contains('/') || fileName.contains(r'\');
    final hasTraversal = fileName == '..' || fileName.contains('..');
    if (fileName.isEmpty ||
        hasSeparator ||
        hasTraversal ||
        p.isAbsolute(fileName) ||
        p.basename(fileName) != fileName) {
      throw const UpdateDownloadException('INVALID_FILE_NAME');
    }
    return fileName;
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
