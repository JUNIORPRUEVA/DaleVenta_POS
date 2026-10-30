import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'dgii_document_saver.dart';

/// Implementación para Web.
///
/// Descarga REAL en el navegador: construye un `Blob` con los bytes recibidos
/// del backend, crea un enlace temporal con atributo `download` y lo pulsa. No
/// simula nada ni escribe en un almacenamiento ficticio: el archivo lo entrega
/// el navegador al usuario.
///
/// Limitación honesta: el nombre lo propone el servidor y el navegador puede
/// anteponer un sufijo si ya existe un archivo con ese nombre; el guardado final
/// lo decide la política de descargas del navegador.
class PlatformDgiiDocumentSaver implements DgiiDocumentSaver {
  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('ECF_DGII_DOCUMENT_EMPTY');
    }

    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);

    // En navegador no existe una ruta en disco verificable: se devuelve el
    // nombre entregado, que es lo único que el código puede afirmar.
    return fileName;
  }
}
