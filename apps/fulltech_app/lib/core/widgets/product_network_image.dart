import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/token_storage.dart';
import '../api/env.dart';
import '../cache/fulltech_cache_manager.dart';
import '../utils/is_flutter_test.dart';
import '../utils/product_image_url.dart';

class ProductNetworkImage extends StatefulWidget {
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
  State<ProductNetworkImage> createState() => _ProductNetworkImageState();
}

class _ProductNetworkImageState extends State<ProductNetworkImage> {
  static final TokenStorage _tokenStorage = TokenStorage();

  late Future<String?> _tokenFuture;
  late bool _needsAuth;
  late String _sourceUrl;

  @override
  void initState() {
    super.initState();
    _configureAuthFuture();
  }

  @override
  void didUpdateWidget(covariant ProductNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSource = widget.imageUrl.trim();
    final nextNeedsAuth = !kIsWeb && _shouldSendAuthHeader(nextSource);
    if (nextSource != _sourceUrl || nextNeedsAuth != _needsAuth) {
      _configureAuthFuture();
    }
  }

  void _configureAuthFuture() {
    _sourceUrl = widget.imageUrl.trim();
    _needsAuth = !kIsWeb && _shouldSendAuthHeader(_sourceUrl);
    _tokenFuture = isFlutterTest || !_needsAuth
        ? Future<String?>.value()
        : _tokenStorage.getAccessToken();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) return widget.fallback;
    final baseUrl = Env.apiBaseUrl.trim();
    final webProductUrl = kIsWeb
        ? buildPublicProductMediaUrl(
            productId: widget.productId,
            baseUrl: baseUrl,
          )
        : '';
    final effectiveUrl = buildProductThumbnailUrl(
      imageUrl: url,
      width: widget.thumbnailSize,
      height: widget.thumbnailSize,
    );
    final cacheKey = buildProductImageCacheKey(effectiveUrl);

    if (kIsWeb) {
      final productEffectiveUrl = webProductUrl.isEmpty
          ? ''
          : buildProductThumbnailUrl(
              imageUrl: webProductUrl,
              width: widget.thumbnailSize,
              height: widget.thumbnailSize,
            );
      final fallbackEffectiveUrl =
          productEffectiveUrl.isEmpty || productEffectiveUrl == effectiveUrl
          ? ''
          : productEffectiveUrl;
      return _WebProductImage(
        primaryUrl: effectiveUrl,
        fallbackUrl: fallbackEffectiveUrl,
        productId: widget.productId,
        productName: widget.productName,
        originalUrl: widget.originalUrl,
        fit: widget.fit,
        fallback: widget.fallback,
        loading: widget.loading,
        width: widget.width,
        height: widget.height,
      );
    }

    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        final token = snapshot.data?.trim();
        final headers = token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'};

        return CachedNetworkImage(
          key: ValueKey(effectiveUrl),
          imageUrl: effectiveUrl,
          httpHeaders: headers,
          cacheKey: cacheKey.isEmpty ? effectiveUrl : cacheKey,
          cacheManager: FulltechImageCacheManager.instance,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          memCacheWidth: widget.thumbnailSize,
          memCacheHeight: widget.thumbnailSize,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (context, _) => widget.loading ?? widget.fallback,
          errorWidget: (context, _, error) {
            debugLogProductImageFailure(
              productId: widget.productId,
              productName: widget.productName,
              originalUrl: widget.originalUrl,
              attemptedUrl: effectiveUrl,
              error: error,
            );
            return widget.fallback;
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
