import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/product_image_url.dart';

class FulltechImageCacheManager {
  static const _key = 'fulltechProductImagesV5';

  // Product images are versioned by URL/cache key. Thirty days keeps the POS
  // fast across restarts without allowing the disk cache to grow indefinitely.
  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1200,
    ),
  );

  static Future<void> warmImageUrls(
    Iterable<String?> urls, {
    int maxUrls = 24,
  }) async {
    // On Flutter Web, especially iOS/Safari, preloading many product images can
    // create unnecessary memory pressure. Desktop uses the persistent disk cache.
    if (kIsWeb) return;

    final unique = <String>{};
    for (final raw in urls) {
      final url = (raw ?? '').trim();
      if (url.isEmpty) continue;
      if (!unique.add(url)) continue;
      if (unique.length >= maxUrls) break;
    }

    for (final url in unique) {
      try {
        final cacheKey = buildProductImageCacheKey(url);
        await instance.downloadFile(
          url,
          key: cacheKey.isEmpty ? url : cacheKey,
        );
      } catch (_) {
        // A warm-up failure must never block catalog rendering.
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
      final cacheKey = buildProductImageCacheKey(normalizedUrl);
      await instance.putFile(
        normalizedUrl,
        Uint8List.fromList(bytes),
        key: cacheKey.isEmpty ? normalizedUrl : cacheKey,
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
