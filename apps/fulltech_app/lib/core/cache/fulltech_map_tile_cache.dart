import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'cache_repair.dart';

class FulltechMapTileCacheManager {
  static const _key = 'fulltechMapTilesV1';
  static CacheManager? _instance;
  static bool _cacheUnavailable = false;

  static CacheManager? get instance {
    if (_cacheUnavailable) return null;
    return _instance ??= CacheManager(
      Config(
        _key,
        stalePeriod: const Duration(days: 45),
        maxNrOfCacheObjects: 8000,
        repo: buildCacheInfoRepositoryForPlatform(_key),
      ),
    );
  }

  static Future<Uint8List> getTileBytes(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final manager = instance;
    if (manager != null) {
      try {
        final file = await manager.getSingleFile(url, headers: headers);
        return await file.readAsBytes();
      } on MissingPluginException {
        _cacheUnavailable = true;
      }
    }

    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  static Future<void> removeFile(String url) async {
    final manager = instance;
    if (manager == null) return;

    try {
      await manager.removeFile(url);
    } on MissingPluginException {
      _cacheUnavailable = true;
    }
  }

  static Future<void> warmTileUrls(
    Iterable<String> urls, {
    int maxUrls = 64,
  }) async {
    final unique = <String>{};
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (!unique.add(url)) continue;
      if (unique.length >= maxUrls) break;
    }

    final manager = instance;
    if (manager == null) return;

    for (final url in unique) {
      try {
        await manager.downloadFile(url);
      } on MissingPluginException {
        _cacheUnavailable = true;
        return;
      } catch (_) {
        // Ignore individual warm-up failures.
      }
    }
  }
}
