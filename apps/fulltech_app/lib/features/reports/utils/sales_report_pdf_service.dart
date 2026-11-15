import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/pdf_file_actions.dart';
import '../../../core/time/business_time.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../modules/ventas/sales_models.dart';

class SalesReportPdfKpis {
  const SalesReportPdfKpis({
    required this.totalSales,
    required this.grossProfit,
    required this.netProfit,
    required this.totalExpenses,
    required this.totalCost,
    required this.salesCount,
    required this.avgTicket,
    required this.grossMargin,
    required this.margin,
  });

  final double totalSales;

  /// Utilidad bruta del periodo (ventas netas - costo neto).
  final double grossProfit;
  final double netProfit;
  final double totalExpenses;
  final double totalCost;
  final int salesCount;
  final double avgTicket;
  final double grossMargin;

  /// Margen neto (utilidad neta / ventas netas).
  final double margin;
}

class SalesReportPdfCategoryRow {
  const SalesReportPdfCategoryRow({
    required this.category,
    required this.totalSales,
    required this.totalCost,
    required this.totalProfit,
    required this.totalQty,
    required this.totalQtyLabel,
    required this.salesCount,
  });

  final String category;
  final double totalSales;
  final double totalCost;
  final double totalProfit;
  final double totalQty;
  final String totalQtyLabel;
  final int salesCount;
}

Future<Uint8List> buildProfessionalSalesReportPdf({
  required DateTime from,
  required DateTime to,
  required String categoryLabel,
  required SalesReportPdfKpis kpis,
  required List<SalesReportPdfCategoryRow> categories,
  required List<SaleModel> sales,
  CompanySettings? company,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy', 'es_DO');
  final nowFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final generatedAt = businessNow();
  final companyName = pdfFallback(
    company?.companyName,
    fallback: 'FullPOS Cloud',
  );
  final logo = await pdfResolveCompanyLogo(company);
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/manrope/Manrope-Bold.ttf'),
  );
  final doc = pw.Document(
    title: 'Reporte de ventas y rentabilidad',
    author: companyName,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
      maxPages: 500,
      header: (context) => _header(
        company: company,
        companyName: companyName,
        logo: logo,
        firstPage: context.pageNumber == 1,
        generatedLabel: nowFmt.format(generatedAt),
        from: from,
        to: to,
        categoryLabel: categoryLabel,
        dateFmt: dateFmt,
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfKitColors.softLine, width: .5),
          ),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              'FullPOS Cloud | Reporte de gestión',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey500),
            ),
            pw.Spacer(),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey500),
            ),
          ],
        ),
      ),
      build: (_) => [
        _sectionTitle('Resumen del período'),
        _kpiGrid(kpis),
        pw.SizedBox(height: 12),
        _profitBreakdown(kpis),
        pw.SizedBox(height: 16),
        if (categories.isNotEmpty) ...[
          _sectionTitle('Categorías con mayor utilidad'),
          _categoryRanking(categories),
          pw.NewPage(),
        ],
        _sectionTitle('Rentabilidad por categoría'),
        _categoryTable(categories),
        pw.SizedBox(height: 16),
        _sectionTitle('Detalle de ventas'),
        pw.Text(
          'Resumen del período: ${kpis.salesCount} facturas. Detalle disponible: ${sales.length} registros. '
          'Los indicadores resumen el período completo; la tabla presenta el detalle disponible.',
          style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
        ),
        pw.SizedBox(height: 8),
        _salesTable(sales, dateFmt),
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
  required CompanySettings? company,
  required String companyName,
  required pw.MemoryImage? logo,
  required bool firstPage,
  required String generatedLabel,
  required DateTime from,
  required DateTime to,
  required String categoryLabel,
  required DateFormat dateFmt,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 18),
    padding: const pw.EdgeInsets.only(bottom: 12),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfKitColors.accentBlue, width: 2),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (firstPage) ...[
              pdfLogoBox(companyName: companyName, logoImage: logo),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: firstPage ? 17 : 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfKitColors.headingBlack,
                    ),
                  ),
                  if (firstPage)
                    for (final line in [
                      if (pdfClean(company?.rnc).isNotEmpty)
                        'RNC: ${company!.rnc.trim()}',
                      pdfClean(company?.address),
                      [
                        pdfClean(company?.phone),
                        pdfClean(company?.websiteUrl),
                      ].where((v) => v.isNotEmpty).join(' | '),
                    ].where((v) => v.isNotEmpty))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          line,
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: PdfKitColors.textMuted,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'VENTAS Y RENTABILIDAD',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfKitColors.accentBlue,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Emitido: $generatedLabel',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfKitColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: firstPage ? 16 : 10),
        if (firstPage) ...[
          pw.Text(
            'Reporte de ventas y rentabilidad',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfKitColors.headingBlack,
            ),
          ),
          pw.SizedBox(height: 8),
        ],
        pw.Text(
          'Período: ${dateFmt.format(from)} - ${dateFmt.format(to)}',
          style: pw.TextStyle(fontSize: 9, color: PdfKitColors.textPrimary),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Categoría: $categoryLabel',
          style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
        ),
      ],
    ),
  );
}

pw.Widget _categoryRanking(List<SalesReportPdfCategoryRow> categories) {
  final ranked = [...categories]
    ..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
  final top = ranked.take(5).toList();
  final maximum = top.fold<double>(
    0,
    (value, row) => math.max(value, row.totalProfit.abs()),
  );
  return pw.Column(
    children: [
      for (final row in top)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  row.category,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 3,
                child: pw.LayoutBuilder(
                  builder: (context, constraints) => pw.Container(
                    alignment: pw.Alignment.centerLeft,
                    height: 7,
                    color: PdfKitColors.softFill,
                    child: pw.Container(
                      width:
                          (constraints!.maxWidth *
                          (maximum == 0 ? 0 : row.totalProfit.abs() / maximum)),
                      color: row.totalProfit < 0
                          ? PdfKitColors.danger
                          : PdfKitColors.accentBlue,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.SizedBox(
                width: 100,
                child: pw.Text(
                  formatRdCurrencyAccounting(row.totalProfit),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: row.totalProfit < 0
                        ? PdfKitColors.danger
                        : PdfKitColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _kpiGrid(SalesReportPdfKpis kpis) {
  // Mismas metricas que la pantalla: Ventas, Utilidad bruta, Gastos, Utilidad
  // neta + margenes/tickets. No hay una segunda formula para el PDF.
  final rows = [
    [
      _metric('Ventas', formatRdCurrencyAccounting(kpis.totalSales)),
      _metric('Utilidad bruta', formatRdCurrencyAccounting(kpis.grossProfit)),
      _metric('Gastos', formatRdCurrencyAccounting(kpis.totalExpenses)),
    ],
    [
      _metric('Utilidad neta', formatRdCurrencyAccounting(kpis.netProfit)),
      _metric('Margen bruto', '${kpis.grossMargin.toStringAsFixed(1)}%'),
      _metric('Margen neto', '${kpis.margin.toStringAsFixed(1)}%'),
    ],
    [
      _metric('Facturas', '${kpis.salesCount}'),
      _metric('Ticket promedio', formatRdCurrencyAccounting(kpis.avgTicket)),
      _metric('Costo neto', formatRdCurrencyAccounting(kpis.totalCost)),
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

pw.Widget _profitBreakdown(SalesReportPdfKpis kpis) {
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
          'De la utilidad bruta a la utilidad neta',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#111827'),
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          children: [
            _breakdownMetric(
              'Bruta',
              formatRdCurrencyAccounting(kpis.grossProfit),
            ),
            pw.SizedBox(width: 10),
            _breakdownMetric(
              'Gastos',
              formatRdCurrencyAccounting(-kpis.totalExpenses),
            ),
            pw.SizedBox(width: 10),
            _breakdownMetric(
              'Neta',
              formatRdCurrencyAccounting(kpis.netProfit),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _breakdownMetric(String label, String value) {
  return pw.Expanded(
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey600),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

pw.Widget _metric(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F8FAFC'),
      border: pw.Border(
        left: pw.BorderSide(color: PdfKitColors.accentBlue, width: 2),
      ),
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
            color: value.startsWith('-')
                ? PdfKitColors.danger
                : PdfKitColors.accentBlue,
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

pw.Widget _categoryTable(List<SalesReportPdfCategoryRow> categories) {
  if (categories.isEmpty) {
    return _emptyBox('No hay ventas por categoría en este rango.');
  }
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfKitColors.softLine, width: .4),
    ),
    headerDecoration: pw.BoxDecoration(color: PdfKitColors.accentBlue),
    oddRowDecoration: pw.BoxDecoration(color: PdfKitColors.softFill),
    headerStyle: pw.TextStyle(
      fontSize: 7,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    cellStyle: const pw.TextStyle(fontSize: 7),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.3),
      1: pw.FlexColumnWidth(1.5),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(1.5),
      4: pw.FlexColumnWidth(1.15),
      5: pw.FlexColumnWidth(.65),
    },
    cellAlignments: {for (var i = 1; i < 6; i++) i: pw.Alignment.centerRight},
    cellAlignment: pw.Alignment.centerLeft,
    headers: const [
      'Categoría',
      'Ventas',
      'Costo',
      'Utilidad bruta',
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
            row.totalQtyLabel,
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
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfKitColors.softLine, width: .4),
    ),
    headerDecoration: pw.BoxDecoration(color: PdfKitColors.accentBlue),
    oddRowDecoration: pw.BoxDecoration(color: PdfKitColors.softFill),
    headerStyle: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    cellStyle: const pw.TextStyle(fontSize: 7.5),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.05),
      1: pw.FlexColumnWidth(2.6),
      2: pw.FlexColumnWidth(1.55),
      3: pw.FlexColumnWidth(1.55),
      4: pw.FlexColumnWidth(1.55),
    },
    cellAlignments: {for (var i = 2; i < 5; i++) i: pw.Alignment.centerRight},
    cellAlignment: pw.Alignment.centerLeft,
    headers: const ['Fecha', 'Cliente', 'Venta', 'Costo', 'Utilidad'],
    data: sales.map(
      // Fila coherente con la semantica state-aware: el monto vigente y el
      // costo/utilidad remanentes se derivan del MISMO ratio, de modo que
      // una venta devuelta en su totalidad muestra 0/0/0 y una parcial
      // muestra su parte vigente (misma regla que el backend).
      (sale) {
        final ratio = sale.totalSold == 0
            ? 1.0
            : (sale.netActiveAmount / sale.totalSold).clamp(0.0, 1.0);
        return [
          sale.saleDate == null ? '-' : dateFmt.format(sale.saleDate!),
          sale.customerName ?? 'Consumidor final',
          formatRdCurrencyAccounting(sale.netActiveAmount),
          formatRdCurrencyAccounting(sale.totalCost * ratio),
          formatRdCurrencyAccounting(sale.totalProfit * ratio),
        ];
      },
    ).toList(),
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
