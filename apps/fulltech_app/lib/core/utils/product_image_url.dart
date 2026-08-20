import 'package:flutter/foundation.dart';

bool _isInvalidImageValue(String? value) {
  if (value == null) return true;
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'null' ||
      normalized == 'undefined';
}

String _trimTrailingSlash(String value) {
  var current = value.trim();
  while (current.length > 1 && current.endsWith('/')) {
    current = current.substring(0, current.length - 1);
  }
  return current;
}

String _normalizeRawPath(String value) {
  final normalized = value.replaceAll('\\', '/').trim();
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  if (segments.isEmpty) return '';
  return '/${segments.join('/')}';
}

bool _isAbsoluteUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String? _extractUploadsPath(String value) {
  final normalized = value.replaceAll('\\', '/').trim();
  const marker = '/uploads/';
  final markerIndex = normalized.indexOf(marker);
  if (markerIndex >= 0) {
    return normalized.substring(markerIndex);
  }
  if (normalized.startsWith('uploads/')) {
    return '/$normalized';
  }
  if (normalized.startsWith('./uploads/')) {
    return normalized.substring(1);
  }
  return null;
}

String? _extractR2ObjectKey(String value) {
  final normalized = value.replaceAll('\\', '/').trim();

  String? normalizeKey(String candidate) {
    final key = candidate.trim().replaceFirst(RegExp(r'^/+'), '');
    if (key.isEmpty || key.contains('..') || key.contains('\\')) return null;
    return key.startsWith('uploads/companies/') ? key : null;
  }

  final direct = normalizeKey(normalized);
  if (direct != null) return direct;

  try {
    final parsed = Uri.parse(normalized);
    final queryKey = parsed.queryParameters['key'];
    final fromQuery = normalizeKey(queryKey ?? '');
    if (fromQuery != null) return fromQuery;

    const marker = '/uploads/companies/';
    final markerIndex = parsed.path.indexOf(marker);
    if (markerIndex >= 0) {
      return normalizeKey(parsed.path.substring(markerIndex + 1));
    }
  } catch (_) {
    // Keep falling through to path-style checks.
  }

  const marker = '/uploads/companies/';
  final markerIndex = normalized.indexOf(marker);
  if (markerIndex >= 0) {
    return normalizeKey(normalized.substring(markerIndex + 1));
  }

  return null;
}

String _buildMediaObjectUrl(String objectKey, String baseUrl) {
  final path = '/media/object?key=${Uri.encodeQueryComponent(objectKey)}';
  return _joinBaseAndPath(baseUrl, path);
}

String buildPublicProductMediaUrl({
  required String productId,
  required String? baseUrl,
}) {
  final cleanProductId = productId.trim();
  if (cleanProductId.isEmpty) return '';
  final path = '/media/products/${Uri.encodeComponent(cleanProductId)}';
  return _joinBaseAndPath(baseUrl ?? '', path);
}

String _stringifyUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return value.replaceAll(' ', '%20');
  }
  return uri.toString();
}

String _joinBaseAndPath(String baseUrl, String path) {
  final base = _trimTrailingSlash(baseUrl);
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  if (base.isEmpty) {
    return _stringifyUri(normalizedPath);
  }
  if (_isAbsoluteUrl(base)) {
    return _stringifyUri('$base$normalizedPath');
  }
  if (base.startsWith('/')) {
    return _stringifyUri('${_trimTrailingSlash(base)}$normalizedPath');
  }
  return _stringifyUri('${_trimTrailingSlash('/$base')}$normalizedPath');
}

String normalizeProductImageUrl({
  String? imageUrl,
  String? baseUrl,
  bool proxyUploadsOnWeb = false,
}) {
  if (_isInvalidImageValue(imageUrl)) return '';

  final raw = imageUrl!.trim();
  final normalizedBase = _isInvalidImageValue(baseUrl)
      ? ''
      : _trimTrailingSlash(baseUrl!);

  if (normalizedBase.isNotEmpty &&
      (raw == normalizedBase || raw.startsWith('$normalizedBase/'))) {
    final objectKey = _extractR2ObjectKey(raw);
    if (objectKey != null) {
      if (proxyUploadsOnWeb) {
        return _joinBaseAndPath(normalizedBase, objectKey);
      }
      return _buildMediaObjectUrl(objectKey, normalizedBase);
    }
    return _stringifyUri(raw);
  }

  if (_isAbsoluteUrl(raw)) {
    final absolute = _stringifyUri(raw);
    final objectKey = _extractR2ObjectKey(raw);
    if (objectKey != null && normalizedBase.isNotEmpty) {
      if (proxyUploadsOnWeb) {
        return _joinBaseAndPath(normalizedBase, objectKey);
      }
      return _buildMediaObjectUrl(objectKey, normalizedBase);
    }
    return absolute;
  }

  final objectKey = _extractR2ObjectKey(raw);
  if (objectKey != null && normalizedBase.isNotEmpty) {
    if (proxyUploadsOnWeb) {
      return _joinBaseAndPath(normalizedBase, objectKey);
    }
    return _buildMediaObjectUrl(objectKey, normalizedBase);
  }

  final uploadsPath = _extractUploadsPath(raw);
  final normalizedPath = uploadsPath ?? _normalizeRawPath(raw);
  if (normalizedPath.isEmpty) return '';
  return _joinBaseAndPath(normalizedBase, normalizedPath);
}

String buildProductImageUrl({
  required String? imageUrl,
  String? version,
  String? baseUrl,
  bool proxyUploadsOnWeb = false,
}) {
  final normalizedUrl = normalizeProductImageUrl(
    imageUrl: imageUrl,
    baseUrl: baseUrl,
    proxyUploadsOnWeb: proxyUploadsOnWeb,
  );
  if (normalizedUrl.isEmpty) return '';

  final trimmedVersion = version?.trim() ?? '';
  if (trimmedVersion.isEmpty) {
    return normalizedUrl;
  }

  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null) {
    final separator = normalizedUrl.contains('?') ? '&' : '?';
    return '$normalizedUrl${separator}v=${Uri.encodeQueryComponent(trimmedVersion)}';
  }

  final queryParameters = <String, List<String>>{
    for (final entry in uri.queryParametersAll.entries)
      entry.key: List<String>.from(entry.value),
  };
  queryParameters['v'] = [trimmedVersion];

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

String buildProductThumbnailUrl({
  required String imageUrl,
  required int width,
  required int height,
}) {
  final cleanWidth = width.clamp(48, 512);
  final cleanHeight = height.clamp(48, 512);
  final uri = Uri.tryParse(imageUrl.trim());
  if (uri == null) return imageUrl;

  final isMediaEndpoint =
      uri.path == '/media/object' ||
      uri.path == '/api/media/object' ||
      uri.path.startsWith('/media/products/') ||
      uri.path.startsWith('/api/media/products/');
  if (!isMediaEndpoint) return imageUrl;

  final queryParameters = <String, List<String>>{
    for (final entry in uri.queryParametersAll.entries)
      entry.key: List<String>.from(entry.value),
  };
  queryParameters['w'] = ['$cleanWidth'];
  queryParameters['h'] = ['$cleanHeight'];

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

String buildProductImageCacheKey(String imageUrl) {
  final value = imageUrl.trim();
  if (value.isEmpty) return '';

  final uri = Uri.tryParse(value);
  final objectKey = _extractR2ObjectKey(value);
  final version = uri?.queryParameters['v']?.trim() ?? '';
  final width = uri?.queryParameters['w']?.trim() ?? '';
  final height = uri?.queryParameters['h']?.trim() ?? '';
  final source = objectKey ?? uri?.replace(fragment: '').toString() ?? value;
  final parts = <String>[
    source,
    if (version.isNotEmpty) 'v=$version',
    if (width.isNotEmpty) 'w=$width',
    if (height.isNotEmpty) 'h=$height',
  ].join('|');
  final safe = parts
      .replaceAll(RegExp(r'[^A-Za-z0-9._=-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return 'product-image:${safe.length > 220 ? safe.substring(0, 220) : safe}';
}

void debugLogProductImageResolution({
  required String productId,
  required String productName,
  required String? originalUrl,
  required String finalUrl,
}) {
  // Intencionalmente silencioso: se invoca por cada tarjeta de producto.
}

void debugLogProductImageFailure({
  required String productId,
  required String productName,
  required String? originalUrl,
  required String attemptedUrl,
  required Object error,
}) {
  if (!kDebugMode) return;
  debugPrint(
    '[product-image][error] id=$productId name="$productName" original="${originalUrl ?? ''}" attempted="$attemptedUrl" error="$error"',
  );
}
