import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_routes.dart';
import '../api/env.dart';
import '../debug/trace_log.dart';
import 'app_update_models.dart';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository();
});

class AppUpdateRepository {
  AppUpdateRepository({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  bool get isConfigured => Env.apiBaseUrl.trim().isNotEmpty;

  ReleasePlatform? getSupportedPlatform() {
    if (kIsWeb) return null;
    return defaultTargetPlatform == TargetPlatform.windows
        ? ReleasePlatform.windows
        : null;
  }

  Future<InstalledReleaseInfo?> readInstalledRelease() async {
    final platform = getSupportedPlatform();
    if (platform == null) return null;

    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version.trim().isEmpty
        ? '0.0.0'
        : info.version.trim();
    final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

    return InstalledReleaseInfo(
      platform: platform,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  Future<UpdateManifest> checkForUpdate(
    InstalledReleaseInfo installedRelease,
  ) async {
    if (installedRelease.platform != ReleasePlatform.windows) {
      return UpdateManifest.noUpdate();
    }

    final seq = TraceLog.nextSeq();
    TraceLog.log(
      'AppUpdate',
      'check start ${installedRelease.platform.apiValue} ${installedRelease.currentVersion}+${installedRelease.currentBuild}',
      seq: seq,
    );

    final ownsDio = _dio == null;
    final dio =
        _dio ??
        Dio(
          BaseOptions(
            baseUrl: Env.apiBaseUrl,
            connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
            sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
            receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
            headers: {'Accept': 'application/json'},
          ),
        );

    try {
      final response = await dio.get<Map<String, dynamic>>(
        ApiRoutes.releaseCheckUpdate,
        queryParameters: {
          'platform': installedRelease.platform.apiValue,
          'channel': 'stable',
          'version': installedRelease.currentVersion,
          'build': installedRelease.currentBuild,
        },
      );

      final data = response.data ?? const <String, dynamic>{};
      final parsed = UpdateManifest.fromJson(data);
      final safe = parsed.isNewerThan(installedRelease.currentBuild)
          ? parsed
          : UpdateManifest.noUpdate();
      TraceLog.log(
        'AppUpdate',
        'check done update=${safe.updateAvailable} build=${safe.buildNumber ?? 'none'}',
        seq: seq,
      );
      return safe;
    } catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'check failed',
        seq: seq,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (ownsDio) dio.close(force: true);
    }
  }
}

typedef UpdateCheckService = AppUpdateRepository;
