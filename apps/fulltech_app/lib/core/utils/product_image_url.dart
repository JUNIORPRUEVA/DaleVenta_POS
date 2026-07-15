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

bool _hasDifferentHost(String value, String baseUrl) {
  if (!_isAbsoluteUrl(value) || !_isAbsoluteUrl(baseUrl)) {
    return false;
  }

  final valueUri = Uri.tryParse(value);
  final baseUri = Uri.tryParse(baseUrl);
  if (valueUri == null || baseUri == null) {
    return false;
  }

  return valueUri.host.trim().toLowerCase() !=
      baseUri.host.trim().toLowerCase();
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
    return _stringifyUri(raw);
  }

  if (_isAbsoluteUrl(raw)) {
    final absolute = _stringifyUri(raw);
    final uploadsPath = _extractUploadsPath(raw);
    final shouldProxyUploads =
        normalizedBase.isNotEmpty &&
        uploadsPath != null &&
        (proxyUploadsOnWeb || _hasDifferentHost(absolute, normalizedBase));
    if (shouldProxyUploads) {
      final encodedUrl = Uri.encodeQueryComponent(absolute);
      return _stringifyUri(
        '$normalizedBase/products/image-proxy?url=$encodedUrl',
      );
    }
    return absolute;
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

void debugLogProductImageResolution({
  required String productId,
  required String productName,
  required String? originalUrl,
  required String finalUrl,
}) {
  if (!kDebugMode) return;
  debugPrint(
    '[product-image][resolve] id=$productId name="$productName" original="${originalUrl ?? ''}" final="$finalUrl"',
  );
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
