import 'dart:typed_data';

/// Etapa final de un trabajo RAW.
///
/// Permite distinguir con precisión dónde falló el transporte y, sobre todo,
/// evita confundir "el comando llegó al spooler" con "el hardware ejecutó la
/// acción". `rawWriteSucceeded` significa **comando enviado correctamente**,
/// NO que la gaveta se haya abierto físicamente (eso solo lo confirma el
/// usuario con el hardware delante).
enum RawPrintStage {
  /// Windows no conoce la impresora indicada (OpenPrinterW 1801/1905).
  printerNotFound,

  /// OpenPrinterW falló por otro motivo (permisos, servicio, etc.).
  openPrinterFailed,

  /// StartDocPrinterW falló.
  startDocumentFailed,

  /// StartPagePrinter falló.
  startPageFailed,

  /// WritePrinter falló.
  rawWriteFailed,

  /// WritePrinter escribió menos bytes de los solicitados.
  partialWrite,

  /// Todos los bytes se entregaron al spooler de Windows.
  rawWriteSucceeded;

  /// `true` solo cuando el trabajo completo llegó al spooler.
  bool get isSent => this == RawPrintStage.rawWriteSucceeded;

  /// Nombre estable para logs/reportes de soporte (no se muestra al cliente).
  String get label {
    switch (this) {
      case RawPrintStage.printerNotFound:
        return 'PRINTER_NOT_FOUND';
      case RawPrintStage.openPrinterFailed:
        return 'OPEN_PRINTER_FAILED';
      case RawPrintStage.startDocumentFailed:
        return 'START_DOCUMENT_FAILED';
      case RawPrintStage.startPageFailed:
        return 'START_PAGE_FAILED';
      case RawPrintStage.rawWriteFailed:
        return 'RAW_WRITE_FAILED';
      case RawPrintStage.partialWrite:
        return 'PARTIAL_WRITE';
      case RawPrintStage.rawWriteSucceeded:
        return 'RAW_WRITE_SUCCEEDED';
    }
  }
}

class RawPrintResult {
  const RawPrintResult({
    required this.success,
    required this.message,
    required this.printerName,
    required this.bytesWritten,
    required this.datatype,
    this.stage = RawPrintStage.rawWriteSucceeded,
  });

  final bool success;
  final String message;
  final String printerName;
  final int bytesWritten;
  final String datatype;

  /// Etapa final del trabajo. Ver [RawPrintStage].
  final RawPrintStage stage;
}

abstract class RawPrinterTransport {
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  });
}

class RawPrinterException implements Exception {
  const RawPrinterException(
    this.message, {
    this.stage,
    this.win32Error,
    this.bytesWritten,
  });

  final String message;

  /// Etapa del transporte donde se produjo el fallo (si se conoce).
  final RawPrintStage? stage;

  /// Código `GetLastError()` de Win32 cuando aplica.
  final int? win32Error;

  /// Bytes realmente escritos cuando aplica (p. ej. escritura parcial).
  final int? bytesWritten;

  @override
  String toString() => message;
}
