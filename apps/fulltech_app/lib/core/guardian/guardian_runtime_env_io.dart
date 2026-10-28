import 'dart:io';

/// Variable de entorno del proceso (escritorio/móvil). Nunca contiene secretos
/// que no estén ya en el entorno del sistema.
String? guardianRuntimeEnv(String name) {
  final value = (Platform.environment[name] ?? '').trim();
  return value.isEmpty ? null : value;
}
