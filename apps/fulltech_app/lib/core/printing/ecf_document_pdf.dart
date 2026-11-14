import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/ecf/ecf_print_document.dart';
import 'ecf_print_footer.dart';
import 'models/ticket_data.dart';

/// Representation of a frozen fiscal document without inventing a sale.
/// Sales continue using their existing invoice renderer.
Future<Uint8List> buildEcfDocumentPdf(EcfPrintDocument fiscal) async {
  final ticket = TicketData.fromEcf(fiscal);
  final pages = <int, List<TicketItemData>>{};
  final doc = pw.Document(
    title: '${fiscal.label} ${fiscal.encf}',
    author: 'FullPOS Cloud',
  );
  String money(double value) => 'RD\$ ${value.toStringAsFixed(2)}';
  pw.Widget text(String value, {bool bold = false}) => pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  );
  pw.Widget cell(String value, {bool amount = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: amount
        ? pw.SizedBox(
            height: 12,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: text(value),
            ),
          )
        : text(value),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 1000,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text(fiscal.issuerName, bold: true),
          text('RNC: ${fiscal.issuerRnc}'),
          if (fiscal.issuerAddress != null) text(fiscal.issuerAddress!),
          pw.SizedBox(height: 8),
          for (final line in fiscal.identityLines) text(line, bold: true),
          pw.SizedBox(height: 8),
          text('Receptor: ${fiscal.buyerName ?? "Consumidor final"}'),
          if (fiscal.buyerRnc != null) text('RNC/Cédula: ${fiscal.buyerRnc}'),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: 56,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (context.pageNumber < context.pagesCount) ...[
                  text(
                    'Subtotal gravado página: ${money((pages[context.pageNumber] ?? []).fold(0, (sum, line) => sum + line.taxableBase))}',
                  ),
                  text(
                    'Subtotal exento página: ${money((pages[context.pageNumber] ?? []).fold(0, (sum, line) => sum + line.exemptAmount))}',
                  ),
                  text(
                    'Subtotal ITBIS página: ${money((pages[context.pageNumber] ?? []).fold(0, (sum, line) => sum + line.taxAmount))}',
                  ),
                  text(
                    'Monto total página: ${money((pages[context.pageNumber] ?? []).fold(0, (sum, line) => sum + line.total))}',
                  ),
                ],
              ],
            ),
          ),
          ecfPrintFooter(fiscal, pageLeftInsetMm: 24 / PdfPageFormat.mm),
          text('Página ${context.pageNumber} de ${context.pagesCount}'),
        ],
      ),
      build: (_) => [
        _DocumentTable(
          items: ticket.items,
          pages: pages,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                for (final label in [
                  'Descripción / unidad',
                  'Cantidad',
                  'Precio',
                  'Desc.',
                  'ITBIS',
                  'Importe',
                ])
                  cell(label),
              ],
            ),
            for (final line in ticket.items)
              pw.TableRow(
                children: [
                  cell(line.name),
                  cell(line.qty.toString(), amount: true),
                  cell(money(line.unitPrice), amount: true),
                  cell(money(line.discount), amount: true),
                  cell(money(line.taxAmount), amount: true),
                  cell(money(line.total), amount: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        text('Subtotal gravado: ${money(ticket.taxableBase)}'),
        text('Subtotal exento: ${money(ticket.exemptAmount)}'),
        text('Descuento aplicado: ${money(ticket.discount)}'),
        text('ITBIS: ${money(ticket.itbis)}'),
        text('Total: ${money(ticket.total)}', bold: true),
      ],
    ),
  );
  return doc.save();
}

class _DocumentTable extends pw.Table {
  _DocumentTable({
    required super.children,
    required this.items,
    required this.pages,
  }) : super(columnWidths: const {0: pw.FlexColumnWidth(3)});
  final List<TicketItemData> items;
  final Map<int, List<TicketItemData>> pages;
  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    final span = saveContext() as pw.TableContext;
    final first = (span.firstLine - 1).clamp(0, items.length);
    final last = (span.lastLine - 1).clamp(first, items.length);
    pages[context.pageNumber] = items.sublist(first, last);
  }
}
