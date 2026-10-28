/// Utilidades de sanitización del lado del cliente.
///
/// El servidor vuelve a sanitizar; aquí solo se evita enviar datos personales o
/// credenciales que no aportan nada al diagnóstico.
library;

final RegExp _windowsPath = RegExp(r'[A-Za-z]:\\[^\s"\)]+');
final RegExp _unixPath = RegExp(r'/(?:Users|home|var|opt|srv)/[^\s"\)]+');
final RegExp _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final RegExp _bearer = RegExp(r'\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false);
final RegExp _jwt = RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\b');
final RegExp _longDigits = RegExp(r'\b\d{8,}\b');

String redactText(String? input, {int maxChars = 20000}) {
  final text = input ?? '';
  if (text.isEmpty) return '';
  final redacted = text
      .replaceAll(_windowsPath, '<ruta>')
      .replaceAll(_unixPath, '<ruta>')
      .replaceAll(_jwt, '[token]')
      .replaceAll(_bearer, '[credencial]')
      .replaceAll(_email, '[email]')
      .replaceAll(_longDigits, '[numero]');
  return redacted.length <= maxChars ? redacted : redacted.substring(0, maxChars);
}

/// Hash estable (FNV-1a 64) sin dependencias externas.
String stableHash(String input) {
  var hash = 0xcbf29ce484222325;
  for (final code in input.codeUnits) {
    hash ^= code;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Firma de deduplicación: mismo módulo/operación/tipo y primer marco relevante.
String guardianFingerprint({
  required String module,
  required String operation,
  String? exceptionType,
  String? stack,
}) {
  final firstFrame = (stack ?? '')
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.startsWith('at ') || line.startsWith('#'), orElse: () => '');
  return stableHash(
    '${module.toLowerCase()}|${operation.toLowerCase()}|'
    '${(exceptionType ?? '').toLowerCase()}|${firstFrame.toLowerCase()}',
  );
}
