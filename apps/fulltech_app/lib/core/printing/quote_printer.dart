import 'dart:typed_data';

import 'package:printing/printing.dart';

class QuotePrinter {
  static Future<void> printQuoteBytes({
    required Uint8List bytes,
    String documentName = 'Cotizacion',
  }) async {
    await Printing.layoutPdf(name: documentName, onLayout: (_) async => bytes);
  }

  static Future<void> shareQuoteBytes({
    required Uint8List bytes,
    String filename = 'cotizacion.pdf',
  }) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
