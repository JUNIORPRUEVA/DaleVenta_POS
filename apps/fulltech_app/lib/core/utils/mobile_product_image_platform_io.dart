import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Copia el archivo optimizado (devuelto por `image_picker`) a una ruta
/// temporal propia de la aplicación con un nombre único y la extensión real
/// del contenido, para no depender del ciclo de vida del archivo temporal del
/// picker y para poder limpiarlo al terminar el flujo.
Future<String> copyToUniqueAppPath(
  String sourcePath, {
  String extension = '.jpg',
}) async {
  final baseDir = await getTemporaryDirectory();
  final dir = Directory('${baseDir.path}/fulltech_product_images');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final safeExtension = _normalizeExtension(extension);
  final uniqueName =
      'product_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0xFFFFFF)}$safeExtension';
  final target = File('${dir.path}/$uniqueName');
  await File(sourcePath).copy(target.path);
  return target.path;
}

String _normalizeExtension(String extension) {
  final value = extension.trim().toLowerCase();
  if (value.isEmpty) return '.jpg';
  final withDot = value.startsWith('.') ? value : '.$value';
  return (withDot == '.jpeg') ? '.jpg' : withDot;
}

/// Detecta el formato real del archivo leyendo sus primeros bytes (magic
/// bytes). Devuelve (extensión, MIME) o `null` si no puede determinarlo.
/// Es la señal más confiable: refleja el contenido real tras la
/// transformación que haya hecho el picker (p. ej. HEIC → JPEG en iOS).
Future<({String extension, String mime})?> detectImageContentType(
  String path,
) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final raf = await file.open();
    final List<int> bytes;
    try {
      bytes = await raf.read(16);
    } finally {
      await raf.close();
    }
    // JPEG: FF D8 FF
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return (extension: '.jpg', mime: 'image/jpeg');
    }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return (extension: '.png', mime: 'image/png');
    }
    // WebP: RIFF....WEBP (bytes 0..3 = 'RIFF', bytes 8..11 = 'WEBP')
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return (extension: '.webp', mime: 'image/webp');
    }
    return null;
  } catch (_) {
    return null;
  }
}

String fileNameFromPath(String path) {
  final segments = path.replaceAll('\\', '/').split('/');
  return segments.isEmpty ? 'producto.jpg' : segments.last;
}

/// Tamaño del archivo en bytes (para logs de observabilidad) o null si no
/// puede leerse. Nunca lanza.
Future<int?> fileSizeBytes(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    return stat.size;
  } catch (_) {
    return null;
  }
}

/// Elimina de forma segura el temporal creado por `image_picker` después de
/// confirmar que nuestra copia propia existe, no está vacía y no es la misma
/// ruta. Nunca borra archivos originales de la galería del usuario ni rutas
/// que todavía puedan necesitarse.
Future<void> deletePluginTempSafely(
  String? pluginPath, {
  required String ownCopyPath,
}) async {
  final source = (pluginPath ?? '').trim();
  final copy = ownCopyPath.trim();
  if (source.isEmpty || copy.isEmpty) return;
  if (source == copy) return; // Nunca borrar si es la misma ruta.
  try {
    final copyFile = File(copy);
    if (!await copyFile.exists()) return;
    final stat = await copyFile.stat();
    if (stat.size <= 0) return; // La copia debe estar completa.
    final pluginFile = File(source);
    if (!await pluginFile.exists()) return;
    await pluginFile.delete();
  } catch (_) {
    // Limpieza best-effort: nunca debe romper el flujo.
  }
}

/// Elimina el archivo temporal optimizado. Nunca borra archivos originales de
/// la galería del usuario.
Future<void> deleteTemp(String? path) async {
  final value = (path ?? '').trim();
  if (value.isEmpty) return;
  try {
    final file = File(value);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Limpieza best-effort: nunca debe romper el flujo.
  }
}

/// Preview optimizada usando `Image.file` con dimensiones de caché limitadas,
/// para no decodificar una fotografía gigante.
Widget buildPreview({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  int? cacheHeight,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
  );
}
