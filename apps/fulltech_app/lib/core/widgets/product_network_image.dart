import 'package:cached_network_image/cached_network_image.dart';
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
    final shouldSendAuth = _shouldSendAuthHeader(url);

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
          key: ValueKey('$url:${token?.isNotEmpty ?? false}'),
          imageUrl: url,
          httpHeaders: headers,
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
