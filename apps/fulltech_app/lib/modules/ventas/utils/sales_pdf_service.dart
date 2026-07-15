import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/money_formatters.dart';
import '../sales_models.dart';

Future<Uint8List> buildSalesSummaryPdf({
  required String employeeName,
  required DateTime from,
  required DateTime to,
  required SalesSummaryModel summary,
  required List<SaleModel> sales,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy');

  final doc = pw.Document(title: 'Resumen de ventas', author: 'FullTech');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'Resumen de ventas',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Empleado: $employeeName'),
        pw.Text('Rango: ${dateFmt.format(from)} - ${dateFmt.format(to)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const [
            'Fecha',
            'Cliente',
            'Vendido',
            'Costo',
            'Utilidad',
            'Comisión',
          ],
          data: sales
              .map(
                (sale) => [
                  dateFmt.format(sale.saleDate ?? DateTime.now()),
                  sale.customerName ?? 'Sin cliente',
                  formatRdCurrencyAccounting(sale.totalSold),
                  formatRdCurrencyAccounting(sale.totalCost),
                  formatRdCurrencyAccounting(sale.totalProfit),
                  formatRdCurrencyAccounting(sale.commissionAmount),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 280,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'Totales de quincena',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                _totalLine('Cantidad', '${summary.totalSales}'),
                _totalLine(
                  'Total vendido',
                  formatRdCurrencyAccounting(summary.totalSold),
                ),
                _totalLine(
                  'Total costo',
                  formatRdCurrencyAccounting(summary.totalCost),
                ),
                _totalLine(
                  'Total puntos',
                  formatRdCurrencyAccounting(summary.totalProfit),
                ),
                pw.Divider(height: 10),
                _totalLine(
                  'Total beneficio (10%)',
                  formatRdCurrencyAccounting(summary.totalCommission),
                  highlight: true,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> downloadSalesSummaryPdf({
  required Uint8List bytes,
  required DateTime from,
  required DateTime to,
}) async {
  final dateFmt = DateFormat('yyyyMMdd');
  final fileName =
      'resumen_ventas_${dateFmt.format(from)}_${dateFmt.format(to)}.pdf';

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

pw.Widget _totalLine(String label, String value, {bool highlight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: 10,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}
