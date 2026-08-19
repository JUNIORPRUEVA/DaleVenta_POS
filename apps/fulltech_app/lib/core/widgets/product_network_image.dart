import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/token_storage.dart';
import '../api/env.dart';
import '../cache/fulltech_cache_manager.dart';
import '../utils/is_flutter_test.dart';
import '../utils/product_image_url.dart';

class ProductNetworkImage extends StatelessWidget {
  static final TokenStorage _tokenStorage = TokenStorage();

  final String imageUrl;
  final String productId;
  final String productName;
  final String? originalUrl;
  final BoxFit fit;
  final Widget fallback;
  final Widget? loading;
  final double? width;
  final double? height;
  final int thumbnailSize;

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
    this.thumbnailSize = 320,
    int maxRetries = 0,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    if (url.isEmpty) return fallback;
    final baseUrl = Env.apiBaseUrl.trim();
    final webProductUrl = kIsWeb
        ? buildPublicProductMediaUrl(productId: productId, baseUrl: baseUrl)
        : '';
    final sourceUrl = url;
    final effectiveUrl = buildProductThumbnailUrl(
      imageUrl: sourceUrl,
      width: thumbnailSize,
      height: thumbnailSize,
    );
    final cacheKey = buildProductImageCacheKey(effectiveUrl);
    final shouldSendAuth = !kIsWeb && _shouldSendAuthHeader(sourceUrl);

    if (kIsWeb) {
      final productEffectiveUrl = webProductUrl.isEmpty
          ? ''
          : buildProductThumbnailUrl(
              imageUrl: webProductUrl,
              width: thumbnailSize,
              height: thumbnailSize,
            );
      final fallbackEffectiveUrl =
          productEffectiveUrl.isEmpty || productEffectiveUrl == effectiveUrl
          ? ''
          : productEffectiveUrl;
      return _WebProductImage(
        primaryUrl: effectiveUrl,
        fallbackUrl: fallbackEffectiveUrl,
        productId: productId,
        productName: productName,
        originalUrl: originalUrl,
        fit: fit,
        fallback: fallback,
        loading: loading,
        width: width,
        height: height,
      );
    }

    return FutureBuilder<String?>(
      future: isFlutterTest || !shouldSendAuth
          ? Future<String?>.value()
          : _tokenStorage.getAccessToken(),
      builder: (context, snapshot) {
        final token = snapshot.data?.trim();
        final headers = token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'};

        return CachedNetworkImage(
          key: ValueKey('$effectiveUrl:${token?.isNotEmpty ?? false}'),
          imageUrl: effectiveUrl,
          httpHeaders: headers,
          cacheKey: cacheKey.isEmpty ? effectiveUrl : cacheKey,
          cacheManager: FulltechImageCacheManager.instance,
          fit: fit,
          width: width,
          height: height,
          memCacheWidth: thumbnailSize,
          memCacheHeight: thumbnailSize,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (context, _) => loading ?? fallback,
          errorWidget: (context, _, error) {
            debugLogProductImageFailure(
              productId: productId,
              productName: productName,
              originalUrl: originalUrl,
              attemptedUrl: effectiveUrl,
              error: error,
            );
            return fallback;
          },
        );
      },
    );
  }

  bool _shouldSendAuthHeader(String url) {
    final imageUri = Uri.tryParse(url);
    if (imageUri == null || !imageUri.hasScheme) return true;
    final apiUri = Uri.tryParse(Env.apiBaseUrl.trim());
    if (apiUri == null || !apiUri.hasScheme) return false;
    return imageUri.host.toLowerCase() == apiUri.host.toLowerCase();
  }
}

class _WebProductImage extends StatelessWidget {
  const _WebProductImage({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.productId,
    required this.productName,
    required this.originalUrl,
    required this.fit,
    required this.fallback,
    required this.loading,
    required this.width,
    required this.height,
  });

  final String primaryUrl;
  final String fallbackUrl;
  final String productId;
  final String productName;
  final String? originalUrl;
  final BoxFit fit;
  final Widget fallback;
  final Widget? loading;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return _buildImage(primaryUrl, allowFallbackUrl: fallbackUrl.isNotEmpty);
  }

  Widget _buildImage(String url, {required bool allowFallbackUrl}) {
    return Image.network(
      url,
      key: ValueKey(url),
      fit: fit,
      width: width,
      height: height,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return loading ?? fallback;
      },
      errorBuilder: (context, error, _) {
        debugLogProductImageFailure(
          productId: productId,
          productName: productName,
          originalUrl: originalUrl,
          attemptedUrl: url,
          error: error,
        );
        if (allowFallbackUrl) {
          return _buildImage(fallbackUrl, allowFallbackUrl: false);
        }
        return fallback;
      },
    );
  }
}
