import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/env.dart';
import '../cache/fulltech_cache_manager.dart';
import '../utils/product_image_url.dart';

class ProductNetworkImage extends StatefulWidget {
  final String imageUrl;
  final String productId;
  final String productName;
  final String? originalUrl;
  final BoxFit fit;
  final Widget fallback;
  final Widget? loading;
  final int maxRetries;
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
    this.maxRetries = 3,
    this.width,
    this.height,
  });

  @override
  State<ProductNetworkImage> createState() => _ProductNetworkImageState();
}

class _ProductNetworkImageState extends State<ProductNetworkImage> {
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 12),
  ];

  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _retryScheduled = false;
  bool _usingBackupUrl = false;

  String? _buildBackupUrl(String primaryUrl, String? originalUrl) {
    final rawOriginal = (originalUrl ?? '').trim();
    if (rawOriginal.isEmpty) return null;

    final normalized = buildProductImageUrl(
      imageUrl: rawOriginal,
      baseUrl: Env.apiBaseUrl,
      proxyUploadsOnWeb: false,
    );
    final value = normalized.trim();
    if (value.isEmpty || value == primaryUrl) return null;
    return value;
  }

  @override
  void didUpdateWidget(covariant ProductNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.originalUrl != widget.originalUrl) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      _retryScheduled = false;
      _usingBackupUrl = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryUrl = (widget.imageUrl).trim();
    if (primaryUrl.isEmpty) return widget.fallback;

    final backupUrl = _buildBackupUrl(primaryUrl, widget.originalUrl);
    final selectedBaseUrl = _usingBackupUrl && backupUrl != null
        ? backupUrl
        : primaryUrl;
    final imageUrl = _buildAttemptUrl(selectedBaseUrl, _retryAttempt);

    return CachedNetworkImage(
      imageUrl: imageUrl,
      key: ValueKey(imageUrl),
      cacheManager: FulltechImageCacheManager.instance,
      useOldImageOnUrlChange: true,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) {
        return widget.loading ?? widget.fallback;
      },
      errorWidget: (context, _, error) {
        final canUseBackup =
            !_usingBackupUrl &&
            backupUrl != null &&
            backupUrl.trim().isNotEmpty &&
            backupUrl.trim() != primaryUrl;
        if (canUseBackup) {
          _retryTimer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _usingBackupUrl = true;
              _retryAttempt = 0;
              _retryScheduled = false;
            });
          });
          return widget.loading ?? widget.fallback;
        }

        if (_retryAttempt < widget.maxRetries) {
          _scheduleRetry();
          return widget.loading ?? widget.fallback;
        }

        debugLogProductImageFailure(
          productId: widget.productId,
          productName: widget.productName,
          originalUrl: widget.originalUrl,
          attemptedUrl: imageUrl,
          error: error,
        );
        return widget.fallback;
      },
    );
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    final delay =
        _retryDelays[(_retryAttempt).clamp(0, _retryDelays.length - 1)];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _retryAttempt += 1;
        _retryScheduled = false;
      });
    });
  }

  String _buildAttemptUrl(String url, int attempt) {
    if (attempt <= 0) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}rt=$attempt';
    }
    final queryParameters = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: List<String>.from(entry.value),
    };
    queryParameters['rt'] = [
      '${DateTime.now().millisecondsSinceEpoch}-$attempt',
    ];
    final query = queryParameters.entries
        .expand(
          (entry) => entry.value.map(
            (value) =>
                '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
          ),
        )
        .join('&');
    return uri.replace(query: query).toString();
  }
}
