import 'env.dart';

/// Si [value] apunta a una foto de perfil servida por `/media/object` (que
/// exige JWT), la reescribe a la ruta pública `/uploads/...` para que la
/// imagen pueda cargarse en cualquier plataforma (escritorio y web) sin token.
/// Las URLs que no correspondan a fotos de perfil se devuelven sin cambios
/// (p. ej. cédula/licencia, que siguen protegidas por autenticación).
String rewriteProfileMediaUrl(String value) {
  const marker = '/media/object?key=';
  final idx = value.indexOf(marker);
  if (idx < 0) return value;
  final base = value.substring(0, idx);
  final encodedKey = value.substring(idx + marker.length);
  try {
    final key = Uri.decodeComponent(encodedKey);
    if (!key.contains('/users/profile/')) return value;
    return '$base/$key';
  } catch (_) {
    return value;
  }
}

/// Resuelve la URL de una imagen a una URL absoluta utilizable por la app.
String resolvePublicMediaUrl(String? rawUrl) {
  final value = (rawUrl ?? '').trim();
  if (value.isEmpty) return '';
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
