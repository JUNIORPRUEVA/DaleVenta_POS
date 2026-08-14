import '../api/env.dart';

/// Si [value] apunta a una foto de perfil servida por `/media/object` (que
/// exige JWT), la reescribe a la ruta pública `/media/photo` para que la
/// imagen pueda cargarse en cualquier plataforma (escritorio y web) sin token.
/// Las URLs que no correspondan a fotos de perfil se devuelven sin cambios
/// (p. ej. cédula/licencia, que siguen protegidas por autenticación).
String rewriteProfileMediaUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri != null && uri.path == '/media/photo') {
    final fixedKey = _normalizeProfileObjectKey(uri.queryParameters['key']);
    if (fixedKey == null) return value;
    return uri.replace(queryParameters: {'key': fixedKey}).toString();
  }

  if (uri != null && uri.path == '/media/object') {
    final fixedKey = _normalizeProfileObjectKey(uri.queryParameters['key']);
    if (fixedKey == null) return value;
    return uri
        .replace(path: '/media/photo', queryParameters: {'key': fixedKey})
        .toString();
  }

  final uploadsIndex = value.indexOf('/uploads/');
  if (uploadsIndex >= 0) {
    final base = value.substring(0, uploadsIndex);
    final key = value.substring(uploadsIndex + 1).split('?').first;
    final fixedKey = _normalizeProfileObjectKey(key);
    if (fixedKey == null) return value;
    return '$base/media/photo?key=${Uri.encodeComponent(fixedKey)}';
  }

  final fixedKey = _normalizeProfileObjectKey(value);
  if (fixedKey == null) return value;
  return '/media/photo?key=${Uri.encodeComponent(fixedKey)}';
}

/// Resuelve la URL de una imagen a una URL absoluta utilizable por la app.
String resolvePublicMediaUrl(String? rawUrl) {
  final value = (rawUrl ?? '').trim();
  if (value.isEmpty) return '';
  if (value.startsWith('data:image/')) return value;
  final rewritten = rewriteProfileMediaUrl(value);
  if (rewritten.startsWith('http://') || rewritten.startsWith('https://')) {
    return rewritten;
  }
  final base = Env.apiBaseUrl.trim();
  if (base.isEmpty) return rewritten;
  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedPath = rewritten.startsWith('/')
      ? rewritten
      : (rewritten.startsWith('uploads/')
            ? '/$rewritten'
            : '/uploads/$rewritten');
  return '$normalizedBase$normalizedPath';
}

String? _normalizeProfileObjectKey(String? rawKey) {
  final decoded = Uri.decodeComponent((rawKey ?? '').trim()).replaceAll(
    '\\',
    '/',
  );
  if (decoded.isEmpty || decoded.contains('..')) return null;

  final uploadsIndex = decoded.indexOf('uploads/companies/');
  final companyIndex = decoded.indexOf('companies/');
  final normalized = uploadsIndex >= 0
      ? decoded.substring(uploadsIndex)
      : (companyIndex >= 0 ? 'uploads/${decoded.substring(companyIndex)}' : '');

  if (!normalized.contains('/users/profile/')) return null;
  return normalized;
}
