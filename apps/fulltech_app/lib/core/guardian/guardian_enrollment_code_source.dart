import 'dart:io';

import 'package:flutter/foundation.dart';

/// Origen del código de enrolamiento **en tiempo de ejecución**.
///
/// El código de un solo uso nunca se compila dentro del ejecutable. Se admite:
/// 1. Un archivo local cuya ruta sí puede compilarse (`GUARDIAN_ENROLLMENT_CODE_FILE`).
/// 2. La variable de entorno `GUARDIAN_ENROLLMENT_CODE` del proceso que lanza la app.
///
/// Tras un canje correcto, el archivo se elimina para que el código no pueda
/// reutilizarse desde el mismo equipo.
class GuardianEnrollmentCodeSource {
  GuardianEnrollmentCodeSource({this.filePath = '', Map<String, String>? environment})
      : _environment = environment ?? Platform.environment;

  static const String envVar = 'GUARDIAN_ENROLLMENT_CODE';

  final String filePath;
  final Map<String, String> _environment;

  Future<String?> read() async {
    final fromFile = await _readFile();
    if (fromFile != null) return fromFile;
    final fromEnv = (_environment[envVar] ?? '').trim();
    return fromEnv.isEmpty ? null : fromEnv;
  }

  /// Elimina el archivo del código (best-effort, nunca lanza).
  Future<void> consume() async {
    if (filePath.trim().isEmpty) return;
    try {
      final file = File(filePath.trim());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('GUARDIAN: no se pudo eliminar el archivo de enrolamiento ($error)');
    }
  }

  Future<String?> _readFile() async {
    final path = filePath.trim();
    if (path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = (await file.readAsString()).trim();
      return content.isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }
}
