import 'dart:typed_data';

/// Contrato mínimo del guardado de un documento descargado.
///
/// Existe para que la descarga funcione en escritorio/móvil **y** no rompa la
/// compilación Web: `dart:io` no existe en navegador.
abstract class DgiiDocumentSaver {
  /// Guarda [bytes] y devuelve una descripción legible para el usuario.
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  });
}
