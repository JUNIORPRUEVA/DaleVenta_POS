import 'dart:typed_data';

class RawPrintResult {
  const RawPrintResult({
    required this.success,
    required this.message,
    required this.printerName,
    required this.bytesWritten,
    required this.datatype,
  });

  final bool success;
  final String message;
  final String printerName;
  final int bytesWritten;
  final String datatype;
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
  const RawPrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}
