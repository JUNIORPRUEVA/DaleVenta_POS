import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../cache/fulltech_cache_manager.dart';
import '../utils/product_image_url.dart';

class ProductNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String productId;
  final String productName;
  final String? originalUrl;
  final BoxFit fit;
  final Widget fallback;
  final Widget? loading;
  final double? width;
  final double? height;

  const ProductNetworkImage({
    super.key,
    required this.imageUrl,
    required this.productId,
    required this.productName,
    required this.originalUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.loading,
    this.width,
    this.height,
    int maxRetries = 0,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    if (url.isEmpty) return fallback;

    return CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      cacheKey: url,
      cacheManager: FulltechImageCacheManager.instance,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, _) => loading ?? fallback,
      errorWidget: (context, _, error) {
        debugLogProductImageFailure(
          productId: productId,
          productName: productName,
          originalUrl: originalUrl,
          attemptedUrl: url,
          error: error,
        );
        return fallback;
      },
    );
  }
}
