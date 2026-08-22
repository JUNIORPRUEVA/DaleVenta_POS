import 'package:flutter/material.dart';

/// Stub para plataformas sin acceso a archivos locales (web/otros). El flujo
/// móvil solo invoca estas funciones en Android/iOS, por lo que aquí devuelven
/// valores seguros sin realizar operaciones de archivo.
Future<String> copyToUniqueAppPath(
  String sourcePath, {
  String extension = '.jpg',
}) async => sourcePath;

Future<({String extension, String mime})?> detectImageContentType(
  String path,
) async => null;

String fileNameFromPath(String path) => 'producto.jpg';

Future<int?> fileSizeBytes(String path) async => null;

Future<void> deletePluginTempSafely(
  String? pluginPath, {
  required String ownCopyPath,
}) async {}

Future<void> deleteTemp(String? path) async {}

Widget buildPreview({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  int? cacheHeight,
}) {
  return const SizedBox.shrink();
}
