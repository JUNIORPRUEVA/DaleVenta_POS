import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/product_image_url.dart';
import 'cache_repair.dart';

class FulltechImageCacheManager {
  static const _key = 'fulltechProductImagesV5';
  static const _defaultThumbnailSize = 320;

  // Instancia estable (singleton) creada una sola vez. Se usa un repositorio
  // de metadatos auto-recuperable para que un índice JSON vacío/corrupto se
  // reconstruya limpio al abrir en vez de reportar `FormatException`.
  static CacheManager? _instance;

  // Product images are versioned by URL/cache key. Thirty days keeps the POS
  // fast across restarts without allowing the disk cache to grow indefinitely.
  static CacheManager get instance {
    var manager = _instance;
    if (manager == null) {
      manager = CacheManager(
        Config(
          _key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 1200,
          repo: buildCacheInfoRepositoryForPlatform(_key),
        ),
      );
      _instance = manager;
    }
    return manager;
  }

  static Future<void> warmImageUrls(
    Iterable<String?> urls, {
    int maxUrls = 24,
    int thumbnailSize = _defaultThumbnailSize,
  }) async {
    // On Flutter Web, especially iOS/Safari, preloading many product images can
    // create unnecessary memory pressure. Desktop uses the persistent disk cache.
    if (kIsWeb) return;

    final unique = <String>{};
    for (final raw in urls) {
      final sourceUrl = (raw ?? '').trim();
      if (sourceUrl.isEmpty) continue;
      final effectiveUrl = buildProductThumbnailUrl(
        imageUrl: sourceUrl,
        width: thumbnailSize,
        height: thumbnailSize,
      );
      if (!unique.add(effectiveUrl)) continue;
      if (unique.length >= maxUrls) break;
    }

    for (final effectiveUrl in unique) {
      try {
        final cacheKey = buildProductImageCacheKey(effectiveUrl);
        await instance.downloadFile(
          effectiveUrl,
          key: cacheKey.isEmpty ? effectiveUrl : cacheKey,
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
    int thumbnailSize = _defaultThumbnailSize,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty || bytes.isEmpty) return;

    try {
      final data = Uint8List.fromList(bytes);
      final extension = _extensionFromFilename(filename);
      final fullCacheKey = buildProductImageCacheKey(normalizedUrl);
      await instance.putFile(
        normalizedUrl,
        data,
        key: fullCacheKey.isEmpty ? normalizedUrl : fullCacheKey,
        fileExtension: extension,
      );

      // ProductNetworkImage requests media thumbnails on desktop. Seed that
      // exact cache key too so a newly uploaded photo appears instantly and is
      // not downloaded again on the next rebuild.
      final thumbnailUrl = buildProductThumbnailUrl(
        imageUrl: normalizedUrl,
        width: thumbnailSize,
        height: thumbnailSize,
      );
      if (thumbnailUrl != normalizedUrl) {
        final thumbnailCacheKey = buildProductImageCacheKey(thumbnailUrl);
        await instance.putFile(
          thumbnailUrl,
          data,
          key: thumbnailCacheKey.isEmpty ? thumbnailUrl : thumbnailCacheKey,
          fileExtension: extension,
        );
      }
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
