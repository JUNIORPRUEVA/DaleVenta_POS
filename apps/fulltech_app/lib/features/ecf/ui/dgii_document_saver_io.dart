import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'dgii_document_saver.dart';

/// Implementación para escritorio y móvil: escribe en el directorio temporal de
/// la aplicación (nunca en una carpeta pública) y devuelve la ruta para que el
/// usuario sepa dónde quedó.
class PlatformDgiiDocumentSaver implements DgiiDocumentSaver {
  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File('${dir.path}${Platform.pathSeparator}$safeName');
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }
}
