import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_file_actions.dart';

/// Resultado de intentar compartir un PDF.
enum PdfShareOutcome {
  /// Se abrió la hoja de compartir del sistema.
  shared,

  /// No se pudo abrir la hoja de compartir y el PDF se guardó en Descargas.
  savedToDownloads,

  /// No se pudo compartir ni guardar.
  failed,
}

/// Comparte un PDF con la hoja de compartir del sistema operativo.
///
/// **No** usa `Printing.sharePdf`: en Windows esa función no comparte nada,
/// escribe el archivo en `%TEMP%` y lo abre con la aplicación asociada, lo que
/// lanza el visor de PDF por encima de FullPOS (el botón "Compartir" acababa
/// abriendo otra ventana en lugar de compartir).
///
/// Con `share_plus` se usa la hoja nativa: panel Compartir de Windows,
/// `ACTION_SEND`/`UIActivityViewController` en Android/iOS y `navigator.share`
/// en web. Si la plataforma no lo permite, el PDF se guarda en Descargas para
/// que el usuario no se quede sin el archivo.
Future<PdfShareOutcome> sharePdfWithSystem({
  required Uint8List bytes,
  required String fileName,
  String? subject,
  String? text,
  Rect? sharePositionOrigin,
}) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        // `share_plus` escribe el contenido en una carpeta temporal única cuando
        // el `XFile` no tiene ruta, así que sirve en todas las plataformas.
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
        ],
        fileNameOverrides: [fileName],
        subject: subject,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    // En Windows el complemento no puede informar del resultado y devuelve
    // `unavailable` aunque la hoja se haya abierto: no se trata como fallo.
    return PdfShareOutcome.shared;
  } catch (error, stackTrace) {
    debugPrint(
      'PdfShare: no se pudo abrir la hoja de compartir ($error)\n$stackTrace',
    );
    try {
      final saved = await savePdfBytes(bytes: bytes, fileName: fileName);
      return saved ? PdfShareOutcome.savedToDownloads : PdfShareOutcome.failed;
    } catch (fallbackError, fallbackStack) {
      debugPrint(
        'PdfShare: tampoco se pudo guardar el PDF ($fallbackError)\n'
        '$fallbackStack',
      );
      return PdfShareOutcome.failed;
    }
  }
}
