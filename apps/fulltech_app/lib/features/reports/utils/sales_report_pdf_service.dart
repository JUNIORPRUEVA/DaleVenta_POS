import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/pdf_file_actions.dart';
import '../../../modules/ventas/sales_models.dart';

class SalesReportPdfKpis {
  const SalesReportPdfKpis({
    required this.totalSales,
    required this.totalProfit,
    required this.netProfit,
    required this.totalCost,
    required this.salesCount,
    required this.avgTicket,
    required this.margin,
  });

  final double totalSales;
  final double totalProfit;
  final double netProfit;
  final double totalCost;
  final int salesCount;
  final double avgTicket;
  final double margin;
}

class SalesReportPdfCategoryRow {
  const SalesReportPdfCategoryRow({
    required this.category,
    required this.totalSales,
    required this.totalCost,
    required this.totalProfit,
    required this.totalQty,
    required this.salesCount,
  });

  final String category;
  final double totalSales;
  final double totalCost;
  final double totalProfit;
  final double totalQty;
  final int salesCount;
}

Future<Uint8List> buildProfessionalSalesReportPdf({
  required DateTime from,
  required DateTime to,
  required String categoryLabel,
  required SalesReportPdfKpis kpis,
  required List<SalesReportPdfCategoryRow> categories,
  required List<SaleModel> sales,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy', 'es_DO');
  final nowFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final doc = pw.Document(
    title: 'Reporte profesional de ventas',
    author: 'FullPOS Cloud',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
      header: (_) => _header(
        from: from,
        to: to,
        categoryLabel: categoryLabel,
        dateFmt: dateFmt,
        nowFmt: nowFmt,
      ),
      footer: (context) => pw.Row(
        children: [
          pw.Text(
            'FullPOS Cloud',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey500),
          ),
          pw.Spacer(),
          pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey500),
          ),
        ],
      ),
      build: (_) => [
        _kpiGrid(kpis),
        pw.SizedBox(height: 16),
        _sectionTitle('Ganancia por categoria'),
        _categoryTable(categories, qtyFmt),
        pw.SizedBox(height: 16),
        _sectionTitle('Ventas incluidas'),
        _salesTable(sales.take(30).toList(growable: false), dateFmt),
        if (sales.length > 30) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Se muestran las primeras 30 ventas recientes de ${sales.length} registros filtrados.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey600),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

Future<bool> downloadProfessionalSalesReportPdf({
  required Uint8List bytes,
  required DateTime from,
  required DateTime to,
  required String categoryLabel,
}) {
  final dateFmt = DateFormat('yyyyMMdd');
  final categoryToken = categoryLabel
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .toLowerCase();
  final suffix = categoryToken.isEmpty ? 'todas' : categoryToken;
  return savePdfBytes(
    bytes: bytes,
    fileName:
        'reporte_ventas_${dateFmt.format(from)}_${dateFmt.format(to)}_$suffix.pdf',
  );
}

pw.Widget _header({
  required DateTime from,
  required DateTime to,
  required String categoryLabel,
  required DateFormat dateFmt,
  required DateFormat nowFmt,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#0F172A'),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Reporte profesional de ventas',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Periodo: ${dateFmt.format(from)} - ${dateFmt.format(to)}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey100),
              ),
              pw.Text(
                'Categoria: $categoryLabel',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey100),
              ),
            ],
          ),
        ),
        pw.Text(
          nowFmt.format(DateTime.now()),
          style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey200),
        ),
      ],
    ),
  );
}

pw.Widget _kpiGrid(SalesReportPdfKpis kpis) {
  final rows = [
    [
      _metric('Ventas netas', formatRdCurrencyAccounting(kpis.totalSales)),
      _metric('Utilidad neta', formatRdCurrencyAccounting(kpis.netProfit)),
      _metric('Margen', '${kpis.margin.toStringAsFixed(1)}%'),
    ],
    [
      _metric('Costo', formatRdCurrencyAccounting(kpis.totalCost)),
      _metric('Facturas', '${kpis.salesCount}'),
      _metric('Ticket promedio', formatRdCurrencyAccounting(kpis.avgTicket)),
    ],
  ];

  return pw.Table(
    children: rows
        .map(
          (row) => pw.TableRow(
            children: row
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: cell,
                  ),
                )
                .toList(),
          ),
        )
        .toList(),
  );
}

pw.Widget _metric(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F8FAFC'),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#111827'),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#111827'),
      ),
    ),
  );
}

pw.Widget _categoryTable(
  List<SalesReportPdfCategoryRow> categories,
  NumberFormat qtyFmt,
) {
  if (categories.isEmpty) {
    return _emptyBox('No hay ventas por categoria en este rango.');
  }
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.45),
    headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF1FF')),
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellAlignment: pw.Alignment.centerLeft,
    headers: const [
      'Categoria',
      'Ventas',
      'Costo',
      'Ganancia',
      'Unidades',
      'Facturas',
    ],
    data: categories
        .map(
          (row) => [
            row.category,
            formatRdCurrencyAccounting(row.totalSales),
            formatRdCurrencyAccounting(row.totalCost),
            formatRdCurrencyAccounting(row.totalProfit),
            qtyFmt.format(row.totalQty),
            '${row.salesCount}',
          ],
        )
        .toList(),
  );
}

pw.Widget _salesTable(List<SaleModel> sales, DateFormat dateFmt) {
  if (sales.isEmpty) {
    return _emptyBox('No hay ventas en el rango seleccionado.');
  }
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.45),
    headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F1F5F9')),
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 7.6),
    cellAlignment: pw.Alignment.centerLeft,
    headers: const ['Fecha', 'Cliente', 'Venta', 'Costo', 'Utilidad'],
    data: sales
        .map(
          (sale) => [
            sale.saleDate == null ? '-' : dateFmt.format(sale.saleDate!),
            sale.customerName ?? 'Consumidor final',
            formatRdCurrencyAccounting(sale.totalSold),
            formatRdCurrencyAccounting(sale.totalCost),
            formatRdCurrencyAccounting(sale.totalProfit),
          ],
        )
        .toList(),
  );
}

pw.Widget _emptyBox(String text) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F8FAFC'),
      border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey600),
    ),
  );
}
