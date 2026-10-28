import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Registro local mínimo del agente Guardian (solo diagnóstico).
///
/// Motivo: si el agente no puede enviar nada, el soporte necesita saber por qué
/// sin depender de un build de depuración. Nunca escribe datos de cliente ni
/// credenciales: solo eventos del ciclo de vida y motivos de fallo.
///
/// - Archivo acotado (32 KB, rotación simple) en el directorio de datos de la app.
/// - Siempre best-effort: no puede lanzar ni bloquear.
class GuardianAgentLog {
  GuardianAgentLog._();

  static const int _maxBytes = 32 * 1024;
  static const String _fileName = 'guardian_agent.log';
  static File? _file;
  /// Cola de escritura: evita líneas intercaladas por llamadas concurrentes.
  static Future<void> _queue = Future<void>.value();

  static Future<void> info(String message) => _write('INFO', message);

  static Future<void> warn(String message) => _write('WARN', message);

  static Future<void> _write(String level, String message) {
    _queue = _queue.then((_) => _writeNow(level, message)).catchError((_) {});
    return _queue;
  }

  static Future<void> _writeNow(String level, String message) async {
    if (kIsWeb) return;
    try {
      final file = await _resolve();
      final line = '${DateTime.now().toUtc().toIso8601String()} [$level] $message\n';
      final length = await file.exists() ? await file.length() : 0;
      if (length > _maxBytes) {
        await file.writeAsString(line, mode: FileMode.write);
      } else {
        await file.writeAsString(line, mode: FileMode.append);
      }
    } catch (_) {
      // Silencio absoluto: el diagnóstico no puede romper el agente.
    }
  }

  static Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_fileName');
    _file = file;
    return file;
  }

  @visibleForTesting
  static Future<String> readForTest() async {
    try {
      final file = await _resolve();
      return await file.exists() ? await file.readAsString() : '';
    } catch (_) {
      return '';
    }
  }
}
