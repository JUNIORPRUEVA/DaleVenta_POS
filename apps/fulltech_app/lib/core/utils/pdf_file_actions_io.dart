import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<bool> savePdfBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final downloads = await getDownloadsDirectory();
  final baseDirectory = downloads ?? Directory.current;
  if (!await baseDirectory.exists()) {
    await baseDirectory.create(recursive: true);
  }

  final safeName = _safePdfFileName(fileName);
  var target = File('${baseDirectory.path}${Platform.pathSeparator}$safeName');
  if (await target.exists()) {
    final dot = safeName.toLowerCase().endsWith('.pdf')
        ? safeName.length - 4
        : safeName.length;
    final base = safeName.substring(0, dot);
    final extension = safeName.substring(dot);
    var index = 1;
    do {
      target = File(
        '${baseDirectory.path}${Platform.pathSeparator}$base ($index)$extension',
      );
      index += 1;
    } while (await target.exists());
  }

  await target.writeAsBytes(bytes, flush: true);
  return true;
}

String _safePdfFileName(String value) {
  final cleaned = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'_+'), '_');
  final fallback = cleaned.isEmpty ? 'cotizacion.pdf' : cleaned;
  return fallback.toLowerCase().endsWith('.pdf') ? fallback : '$fallback.pdf';
}
