import 'dart:typed_data';

import 'raw_printer_transport.dart';

class WindowsRawPrinterTransport implements RawPrinterTransport {
  const WindowsRawPrinterTransport();

  static const String datatype = 'RAW';

  @override
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  }) {
    throw const RawPrinterException(
      'La impresion RAW de Windows solo esta disponible en Windows.',
    );
  }
}
