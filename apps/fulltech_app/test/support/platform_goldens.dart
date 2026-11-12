import 'dart:io';

/// Skia y las fuentes de sistema rasterizan algunos glifos de forma distinta
/// en Linux y Windows. Cada entorno compara contra su referencia revisada,
/// conservando la igualdad exacta de píxeles y todas las aserciones de layout.
String platformGolden(String path) {
  if (!Platform.isLinux) return path;
  final separator = path.lastIndexOf('/');
  return '${path.substring(0, separator)}/linux/${path.substring(separator + 1)}';
}
