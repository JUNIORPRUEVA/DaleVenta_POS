import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_info.dart';
import 'ticket_data.dart';
import 'ticket_layout_config.dart';
import 'ticket_renderer.dart';

class TicketBuilder {
  const TicketBuilder({required this.layout, required this.company});

  final TicketLayoutConfig layout;
  final CompanyInfo company;

  List<String> buildLines(TicketData data) {
    return TicketRenderer(layout: layout, company: company).buildLines(data);
  }

  String buildPlainText(TicketData data) => buildLines(data).join('\n');

  Future<Uint8List> buildPdf(TicketData data) {
    return buildPdfFromLines(buildLines(data));
  }

  Future<Uint8List> buildPdfFromLines(List<String> lines) async {
    final doc = pw.Document(author: 'FullTech', title: 'Ticket');
    final pageWidth = layout.paperWidthMm * PdfPageFormat.mm;
    final margins = 3 * PdfPageFormat.mm;
    final lineHeight = layout.adjustedFontSize * 1.36;
    final contentHeight = (lines.length + 8) * lineHeight;
    final minHeight = 90 * PdfPageFormat.mm;
    final maxHeight = 2000 * PdfPageFormat.mm;
    final pageHeight = contentHeight.clamp(minHeight, maxHeight).toDouble();

    final font = switch (layout.fontFamilyName) {
      'Helvetica' => pw.Font.helvetica(),
      'Times' => pw.Font.times(),
      _ => pw.Font.courier(),
    };
    final bold = switch (layout.fontFamilyName) {
      'Helvetica' => pw.Font.helveticaBold(),
      'Times' => pw.Font.timesBold(),
      _ => pw.Font.courierBold(),
    };
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.all(margins),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (layout.showLogo && company.logoBytes != null) ...[
              pw.Center(
                child: pw.Image(
                  pw.MemoryImage(company.logoBytes!),
                  width: layout.logoSize.toDouble(),
                  height: layout.logoSize.toDouble(),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(height: 4),
            ],
            ...lines.map((line) {
              final strong =
                  line.trim().startsWith('TOTAL') ||
                  line.trim() == company.name ||
                  line.trim().contains('FACTURA') ||
                  line.trim().contains('DEVOLUCION');
              return pw.Text(
                line,
                style: pw.TextStyle(
                  font: strong ? bold : font,
                  fontSize: layout.adjustedFontSize,
                  height: 1.12,
                ),
              );
            }),
          ],
        ),
      ),
    );
    return doc.save();
  }

  List<String> buildDebugRuler() {
    final width = layout.printableChars;
    final digits = List.generate(
      width,
      (i) => ((i + 1) % 10).toString(),
    ).join();
    return [
      'ANCHO ${layout.paperWidthMm}mm / $width chars',
      digits,
      '-' * width,
    ];
  }
}
