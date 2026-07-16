import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/utils/money_formatters.dart';
import '../sales_models.dart';

final PdfColor _pageBackground = PdfColors.white;
final PdfColor _borderColor = PdfColor.fromHex('#C9D1DB');
final PdfColor _panelBorder = PdfColor.fromHex('#DEE5EC');
final PdfColor _softFill = PdfColor.fromHex('#F7F9FC');
final PdfColor _softLine = PdfColor.fromHex('#E8EDF2');
final PdfColor _headingBlack = PdfColors.black;
final PdfColor _textPrimary = PdfColor.fromHex('#1D2430');
final PdfColor _textMuted = PdfColor.fromHex('#6C7685');
final PdfColor _accentBlue = PdfColor.fromHex('#4361EE');

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

Future<Uint8List> buildSaleInvoicePdf({
  required SaleModel sale,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final invoiceCode = _buildInvoiceCode(sale.id);

  final doc = pw.Document(title: 'Factura $invoiceCode', author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      header: (context) => _invoiceHeader(
        company: company,
        logoImage: logoImage,
        sale: sale,
        invoiceCode: invoiceCode,
        dateFmt: dateFmt,
        isContinuation: context.pageNumber > 1,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        _invoiceDetailSection(sale, money, qtyFmt),
        pw.SizedBox(height: 12),
        _invoiceBottomSection(sale, money),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _invoiceHeader({
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required SaleModel sale,
  required String invoiceCode,
  required DateFormat dateFmt,
  required bool isContinuation,
}) {
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final rnc = _clean(company?.rnc);
  final phone = _clean(company?.phone);
  final address = _clean(company?.address);
  final customerName = _fallback(
    sale.customerName,
    fallback: 'Consumidor Final',
  );
  final customerPhone = _fallback(
    sale.customerPhone,
    fallback: 'No registrado',
  );
  final sellerName = _fallback(sale.userName, fallback: sale.userId);
  final statusText = sale.isDeleted ? 'Factura devuelta' : null;

  return _panel(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _logoBox(companyName: companyName, logoImage: logoImage),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (rnc.isNotEmpty) _companyLine('RNC: $rnc'),
                        if (phone.isNotEmpty) _companyLine('Tel: $phone'),
                        if (address.isNotEmpty) _companyLine(address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 215,
              child: _documentFactsPanel(
                documentLabel: 'FACTURA',
                code: invoiceCode,
                dateText: dateFmt.format(sale.saleDate ?? DateTime.now()),
                statusText: statusText,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1, color: _softLine),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _personInfoPanel(
                primary: customerName,
                secondary: customerPhone,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _personInfoPanel(
                primary: sellerName,
                secondary: 'Vendedor que le asistió',
              ),
            ),
          ],
        ),
        if (isContinuation) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Continuación de la factura',
            style: pw.TextStyle(
              fontSize: 8,
              color: _textMuted,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _invoiceDetailSection(
  SaleModel sale,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final tableRows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _headingBlack),
      children: [
        _headerCell('Descripcion', align: pw.TextAlign.left),
        _headerCell('Cant.'),
        _headerCell('Unitario', align: pw.TextAlign.right),
        _headerCell('Importe', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (sale.items.isEmpty) {
    tableRows.add(
      pw.TableRow(
        children: [
          _emptyCell('No hay productos registrados en esta factura.'),
          _emptyCell(''),
          _emptyCell(''),
          _emptyCell(''),
        ],
      ),
    );
  } else {
    for (final item in sale.items) {
      tableRows.add(
        pw.TableRow(
          children: [
            _bodyCell(
              item.productNameSnapshot.trim().isEmpty
                  ? 'Producto sin descripción'
                  : item.productNameSnapshot.trim(),
              align: pw.TextAlign.left,
              bold: true,
            ),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(
              money.format(item.priceSoldUnit),
              align: pw.TextAlign.right,
            ),
            _bodyCell(
              money.format(item.subtotalSold),
              align: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }
  }

  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detalle de ventas',
          style: pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderColor, width: 0.9),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Table(
            border: pw.TableBorder(
              verticalInside: pw.BorderSide(color: _borderColor, width: 0.7),
              horizontalInside: pw.BorderSide(color: _borderColor, width: 0.7),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(5.45),
              1: pw.FlexColumnWidth(0.75),
              2: pw.FlexColumnWidth(1.65),
              3: pw.FlexColumnWidth(1.7),
            },
            children: tableRows,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _invoiceBottomSection(SaleModel sale, NumberFormat money) {
  final note = (sale.note ?? '').trim();
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: note.isEmpty
            ? pw.SizedBox()
            : _panel(
                padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Observaciones',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      note,
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      if (note.isNotEmpty) pw.SizedBox(width: 12),
      pw.SizedBox(width: 228, child: _invoiceTotalsPanel(sale, money)),
    ],
  );
}

pw.Widget _invoiceTotalsPanel(SaleModel sale, NumberFormat money) {
  final subtotal = sale.items.fold(0.0, (sum, item) => sum + item.subtotalSold);
  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Totales',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 10),
        _pdfTotalLine('Subtotal', money.format(subtotal)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _softLine),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _softFill,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: _panelBorder, width: 0.8),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Total general',
                  style: pw.TextStyle(
                    fontSize: 10.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Text(
                money.format(sale.totalSold),
                style: pw.TextStyle(
                  fontSize: 11.6,
                  fontWeight: pw.FontWeight.bold,
                  color: _accentBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
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

pw.Widget _pageFooter(int pageNumber, int totalPages) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Text(
          'Documento comercial',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
        pw.Spacer(),
        pw.Text(
          'Página $pageNumber de $totalPages',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
      ],
    ),
  );
}

Future<pw.MemoryImage?> _resolveCompanyLogo(CompanySettings? company) async {
  final rawLogo = _clean(company?.logoBase64);
  if (rawLogo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(rawLogo));
    } catch (_) {}
  }

  try {
    final asset = await rootBundle.load('assets/image/logo.png');
    return pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _buildInvoiceCode(String id) {
  final token = _buildFileToken(id, length: 8, fallback: 'MANUAL');
  return 'FAC-$token';
}

String _buildFileToken(
  String id, {
  required int length,
  required String fallback,
}) {
  final normalized = id.replaceAll('-', '').trim();
  if (normalized.isEmpty) return fallback;
  return normalized.length > length
      ? normalized.substring(0, length).toUpperCase()
      : normalized.toUpperCase();
}

String _fallback(String? value, {required String fallback}) {
  final cleaned = _clean(value);
  return cleaned.isEmpty ? fallback : cleaned;
}

String _clean(String? value) => (value ?? '').trim();

pw.Widget _panel({
  required pw.Widget child,
  pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
  pw.EdgeInsetsGeometry margin = pw.EdgeInsets.zero,
}) {
  return pw.Container(
    margin: margin,
    padding: padding,
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      border: pw.Border.all(color: _panelBorder, width: 0.8),
    ),
    child: child,
  );
}

pw.Widget _logoBox({
  required String companyName,
  required pw.MemoryImage? logoImage,
}) {
  return pw.Container(
    width: 62,
    height: 62,
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      border: pw.Border.all(color: _panelBorder, width: 0.8),
    ),
    child: logoImage != null
        ? pw.Image(logoImage, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              companyName.substring(0, 1).toUpperCase(),
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
          ),
  );
}

pw.Widget _companyLine(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, color: _textMuted)),
  );
}

pw.Widget _documentFactsPanel({
  required String documentLabel,
  required String code,
  required String dateText,
  String? statusText,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      border: pw.Border.all(color: _panelBorder, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          documentLabel,
          style: pw.TextStyle(
            fontSize: 8.4,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          code,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          dateText,
          style: pw.TextStyle(fontSize: 8.7, color: _textPrimary),
        ),
        if (statusText != null && statusText.trim().isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            statusText,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#B42318'),
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _personInfoPanel({required String primary, String? secondary}) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      border: pw.Border.all(color: _panelBorder, width: 0.8),
    ),
    child: pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _panelBorder, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            primary,
            style: pw.TextStyle(
              fontSize: 8.9,
              color: _textPrimary,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (secondary != null && secondary.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              secondary.trim(),
              style: pw.TextStyle(fontSize: 8.1, color: _textMuted),
            ),
          ],
        ],
      ),
    ),
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    alignment: align == pw.TextAlign.left
        ? pw.Alignment.centerLeft
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.center,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.4,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _bodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8,
        color: _textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _emptyCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _textMuted)),
  );
}

pw.Widget _pdfTotalLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.1, color: _textPrimary),
          ),
        ),
        pw.Text(value, style: pw.TextStyle(fontSize: 9.1, color: _textPrimary)),
      ],
    ),
  );
}
