import 'dart:typed_data';

import 'dgii_document_saver.dart';

/// Implementación de reserva para plataformas sin guardado disponible.
///
/// Web ya **no** usa este archivo: tiene su propia descarga con `Blob`. Esto solo
/// cubre un destino sin `dart:io` ni `dart:js_interop`, y falla de forma
/// explícita en vez de simular un guardado.
class PlatformDgiiDocumentSaver implements DgiiDocumentSaver {
  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    throw UnsupportedError('ECF_DGII_DOWNLOAD_NOT_SUPPORTED_ON_PLATFORM');
  }
}
