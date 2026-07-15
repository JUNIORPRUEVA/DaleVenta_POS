import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FulltechImageCacheManager {
  static const _key = 'fulltechProductImagesV4';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2500,
    ),
  );

  static Future<void> warmImageUrls(
    Iterable<String?> urls, {
    int maxUrls = 120,
  }) async {
    final unique = <String>{};
    for (final raw in urls) {
      final url = (raw ?? '').trim();
      if (url.isEmpty) continue;
      if (!unique.add(url)) continue;
      if (unique.length >= maxUrls) break;
    }

    for (final url in unique) {
      try {
        await instance.downloadFile(url);
      } catch (_) {
        // Ignore individual warm-up failures.
      }
    }
  }

  static Future<void> clear() => instance.emptyCache();

  static Future<void> putImageBytes({
    required String url,
    required List<int> bytes,
    String? filename,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty || bytes.isEmpty) return;

    try {
      await instance.putFile(
        normalizedUrl,
        Uint8List.fromList(bytes),
        fileExtension: _extensionFromFilename(filename),
      );
    } catch (_) {
      // The network URL remains the source of truth if local caching fails.
    }
  }

  static String _extensionFromFilename(String? filename) {
    final value = (filename ?? '').trim().toLowerCase();
    final dotIndex = value.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == value.length - 1) return 'jpg';
    final ext = value.substring(dotIndex + 1);
    if (ext == 'jpeg') return 'jpg';
    if (ext == 'png' || ext == 'jpg' || ext == 'webp' || ext == 'gif') {
      return ext;
    }
    return 'jpg';
  }
}
