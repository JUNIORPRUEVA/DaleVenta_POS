import 'dart:async';
import 'dart:io';

class TraceLogSink {
  static const int _maxBytes = 1024 * 1024;
  static File? _logFile;

  static void write(String line) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    unawaited(_append('${_redact(line)}\n'));
  }

  static Future<void> _append(String line) async {
    try {
      final file = await _resolveFile();
      await _rotateIfNeeded(file);
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Diagnostics must never interrupt customer work.
    }
  }

  static Future<File> _resolveFile() async {
    final cached = _logFile;
    if (cached != null) return cached;

    final directory = await _resolveDirectory();
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}fullpos-client.log',
    );
    _logFile = file;
    return file;
  }

  static Future<Directory> _resolveDirectory() async {
    if (Platform.isWindows) {
      final programFiles = Platform.environment['ProgramFiles']?.trim();
      if (programFiles != null && programFiles.isNotEmpty) {
        final official = Directory(
          '$programFiles${Platform.pathSeparator}DaleVentas POS${Platform.pathSeparator}logs',
        );
        if (await official.exists()) return official;
      }

      final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(
          '$localAppData${Platform.pathSeparator}FullPOS${Platform.pathSeparator}logs',
        );
      }
    }

    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}FullPOS${Platform.pathSeparator}logs',
    );
  }

  static Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) return;
    final length = await file.length();
    if (length < _maxBytes) return;
    final rotated = File('${file.path}.1');
    if (await rotated.exists()) {
      await rotated.delete();
    }
    await file.rename(rotated.path);
    _logFile = File(file.path);
  }

  static String _redact(String value) {
    return value
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer ***')
        .replaceAll(
          RegExp(
            r'("?(?:access|refresh)?token"?\s*[:=]\s*)"?[^",\s}]+"?',
            caseSensitive: false,
          ),
          r'$1***',
        )
        .replaceAll(
          RegExp(
            r'("?(?:password|contrasena|contraseña)"?\s*[:=]\s*)"?[^",\s}]+"?',
            caseSensitive: false,
          ),
          r'$1***',
        );
  }
}
