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

final PdfColor _borderColor = PdfColor.fromHex('#E2E8F0');
final PdfColor _panelBorder = PdfColor.fromHex('#D8E1EA');
final PdfColor _softFill = PdfColor.fromHex('#F8FAFC');
final PdfColor _softLine = PdfColor.fromHex('#E6ECF2');
final PdfColor _headingBlack = PdfColor.fromHex('#111827');
final PdfColor _textPrimary = PdfColor.fromHex('#1D2430');
final PdfColor _textMuted = PdfColor.fromHex('#6C7685');
final PdfColor _accentBlue = PdfColor.fromHex('#1957E6');

String invoicePdfPaymentMethodLabel(String method) {
  return switch (method.trim().toLowerCase()) {
    'cash' => 'Efectivo',
    'card' || 'tarjeta' => 'Tarjeta',
    'transfer' || 'transferencia' => 'Transferencia',
    'mixed' || 'mixto' => 'Mixto',
    'credit' || 'credito' => 'Crédito',
    _ => method.trim().isEmpty ? 'Efectivo' : method.trim(),
  };
}

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
  String? warrantyPolicy,
}) async {
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(
    sale.issuerNameSnapshot,
    fallback: _fallback(company?.companyName, fallback: 'FULLTECH'),
  );
  final invoiceCode = invoicePdfCode(sale.id);
  final warranty = _clean(warrantyPolicy);

  final doc = pw.Document(title: 'Factura $invoiceCode', author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        // Márgenes idénticos a la plantilla de COTIZACIÓN (26/24/26/22):
        // mismo ancho de contenido y misma distribución de secciones.
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
      ),
      header: (context) => _invoiceHeader(
        company: company,
        logoImage: logoImage,
        sale: sale,
        invoiceCode: invoiceCode,
        dateFmt: dateFmt,
        pageNumber: context.pageNumber,
        pagesCount: context.pagesCount,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        _invoiceClientSection(sale),
        _invoiceDetailSection(sale, money, qtyFmt),
        pw.SizedBox(height: 14),
        _invoiceBottomSection(sale, money, warrantyPolicy: warranty),
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
  required int pageNumber,
  required int pagesCount,
}) {
  final companyName = _fallback(
    sale.issuerNameSnapshot,
    fallback: _fallback(company?.companyName, fallback: 'FULLTECH'),
  );
  if (pageNumber > 1) {
    return _invoiceContinuationHeader(
      companyName: companyName,
      invoiceCode: invoiceCode,
      pageNumber: pageNumber,
      pagesCount: pagesCount,
    );
  }
  final rnc = _fallback(
    sale.issuerTaxIdSnapshot,
    fallback: _clean(company?.rnc),
  );
  final phone = _fallback(
    sale.issuerPhoneSnapshot,
    fallback: _clean(company?.phone),
  );
  final address = _fallback(
    sale.issuerAddressSnapshot,
    fallback: _clean(company?.address),
  );
  final statusText = sale.isDeleted ? 'Factura devuelta' : null;
  final fiscalLabel = invoicePdfDocumentLabel(sale);

  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 12),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _softLine)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 6,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _logoBox(companyName: companyName, logoImage: logoImage),
              pw.SizedBox(width: 14),
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
                    pw.SizedBox(height: 5),
                    if (rnc.isNotEmpty) _companyLine('RNC: $rnc'),
                    if (phone.isNotEmpty) _companyLine('Tel: $phone'),
                    if (address.isNotEmpty) _companyLine('Dirección: $address'),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 18),
        pw.SizedBox(
          width: 250,
          child: _documentFactsPanel(
            documentLabel: fiscalLabel,
            code: invoiceCode,
            issuedText: dateFmt.format(sale.saleDate ?? DateTime.now()),
            statusText: statusText,
            ncf: sale.ncf,
            ncfExpirationDate: sale.ncfExpirationDate,
            cashierName: sale.userName,
          ),
        ),
      ],
    ),
  );
}

/// Cabecera compacta para páginas 2+ (misma estructura que la cotización):
/// evita repetir el encabezado completo y deja espacio para la tabla/totales.
pw.Widget _invoiceContinuationHeader({
  required String companyName,
  required String invoiceCode,
  required int pageNumber,
  required int pagesCount,
}) {
  final pageText = pagesCount > 0
      ? 'Página $pageNumber de $pagesCount'
      : 'Página $pageNumber';
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _softLine, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Factura · Continuación',
                style: pw.TextStyle(fontSize: 8, color: _textMuted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              invoiceCode,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              pageText,
              style: pw.TextStyle(fontSize: 8, color: _textMuted),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _invoiceClientSection(SaleModel sale) {
  final name = _fallback(
    sale.fiscalCustomerName ?? sale.customerName,
    fallback: 'Consumidor final',
  );
  final doc = _clean(sale.fiscalCustomerTaxId);
  final phone = _clean(sale.customerPhoneSnapshot ?? sale.customerPhone);
  final address = _clean(sale.customerAddressSnapshot);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(0, 12, 0, 4),
    child: _personInfoPanel(
      title: 'DATOS DEL CLIENTE',
      primary: name,
      secondary: phone.isEmpty ? null : phone,
      document: doc.isEmpty ? null : doc,
      address: address.isEmpty ? null : address,
    ),
  );
}

pw.Widget _invoiceDetailSection(
  SaleModel sale,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final fiscal = sale.fiscalTaxEnabled;
  // Proporciones afinadas: Total más ancho (12%) para que RD$1,250,000.00
  // quepa SIEMPRE en una línea; ITBIS 11% para montos reales (18%).
  // Desc/Cant/Precio/Descuento/Base/ITBIS/Total = 34/6/12/13/12/11/12.
  final columnWidths = fiscal
      ? const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(34),
          1: pw.FlexColumnWidth(6),
          2: pw.FlexColumnWidth(12),
          3: pw.FlexColumnWidth(13),
          4: pw.FlexColumnWidth(12),
          5: pw.FlexColumnWidth(11),
          6: pw.FlexColumnWidth(12),
        }
      : const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(40),
          1: pw.FlexColumnWidth(8),
          2: pw.FlexColumnWidth(18),
          3: pw.FlexColumnWidth(16),
          4: pw.FlexColumnWidth(18),
        };

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _headingBlack),
      children: [
        _headerCell('Descripción', align: pw.TextAlign.left),
        _headerCell('Cant.'),
        _headerCell('Precio', align: pw.TextAlign.right),
        _headerCell('Descuento', align: pw.TextAlign.right),
        if (fiscal) _headerCell('Base', align: pw.TextAlign.right),
        if (fiscal) _headerCell('ITBIS', align: pw.TextAlign.right),
        _headerCell('Total', align: pw.TextAlign.right),
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
          if (fiscal) _emptyCell(''),
          if (fiscal) _emptyCell(''),
          _emptyCell(''),
        ],
      ),
    );
  } else {
    for (final item in sale.items) {
      final isExempt = item.taxExempt || item.exemptAmount > 0;
      final description = item.productNameSnapshot.trim().isEmpty
          ? 'Producto sin descripción'
          : item.productNameSnapshot.trim();
      final discount = item.lineDiscountAmount > 0
          ? '-${money.format(item.lineDiscountAmount)}'
          : '';
      final baseValue = item.taxableBase > 0 ? item.taxableBase : item.exemptAmount;
      tableRows.add(
        pw.TableRow(
          children: [
            _bodyCell(
              isExempt && fiscal ? '$description  [EXENTO]' : description,
              align: pw.TextAlign.left,
              bold: true,
            ),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _moneyCell(money.format(item.priceSoldUnit)),
            _moneyCell(
              discount,
              textColor: item.lineDiscountAmount > 0
                  ? PdfColor.fromHex('#B42318')
                  : null,
            ),
            if (fiscal) _moneyCell(money.format(baseValue)),
            if (fiscal) _moneyCell(money.format(item.taxAmount)),
            _moneyCell(money.format(item.subtotalSold)),
          ],
        ),
      );
    }
  }

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(0, 10, 0, 4),
    child: pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _panelBorder, width: 0.45),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _borderColor, width: 0.55),
        ),
        columnWidths: columnWidths,
        children: tableRows,
      ),
    ),
  );
}

pw.Widget _invoiceBottomSection(
  SaleModel sale,
  NumberFormat money, {
  String? warrantyPolicy,
}) {
  final note = invoicePdfNoteText(sale.note);
  final warranty = _clean(warrantyPolicy);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _panel(
              padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
              fillColor: _softFill,
              showBorder: true,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FORMA DE PAGO',
                    style: pw.TextStyle(
                      fontSize: 7.8,
                      fontWeight: pw.FontWeight.bold,
                      color: _textMuted,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    invoicePdfPaymentMethodLabel(sale.paymentMethod),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (warranty.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _panel(
                padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
                fillColor: _softFill,
                showBorder: true,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TÉRMINOS DE GARANTÍA',
                      style: pw.TextStyle(
                        fontSize: 7.8,
                        fontWeight: pw.FontWeight.bold,
                        color: _textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      warranty,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (note.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _panel(
                padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
                fillColor: _softFill,
                showBorder: true,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NOTAS',
                      style: pw.TextStyle(
                        fontSize: 7.8,
                        fontWeight: pw.FontWeight.bold,
                        color: _textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      note,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 14),
      pw.SizedBox(width: 270, child: _invoiceTotalsPanel(sale, money)),
    ],
  );
}

pw.Widget _invoiceTotalsPanel(SaleModel sale, NumberFormat money) {
  final fiscal = sale.fiscalTaxEnabled;
  final productDiscount = sale.items.fold<double>(
    0,
    (sum, item) => sum + item.lineDiscountAmount,
  );
  final generalDiscount =
      (sale.discountAmount - productDiscount).clamp(0, double.infinity).toDouble();
  final subtotal = fiscal
      ? sale.taxableBase + sale.exemptAmount
      : sale.items.fold(0.0, (sum, item) => sum + item.subtotalSold);
  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
    fillColor: _softFill,
    showBorder: true,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'TOTALES',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
          ),
        ),
        pw.SizedBox(height: 8),
        if (!fiscal || subtotal > 0)
          _pdfTotalLine('Subtotal', money.format(subtotal)),
        if (productDiscount > 0)
          _pdfTotalLine(
            'Descuentos por productos',
            '-${money.format(productDiscount)}',
            amountColor: PdfColor.fromHex('#B42318'),
          ),
        if (generalDiscount > 0)
          _pdfTotalLine(
            'Descuento general',
            '-${money.format(generalDiscount)}',
            amountColor: PdfColor.fromHex('#B42318'),
          ),
        if (fiscal && sale.exemptAmount > 0)
          _pdfTotalLine('Monto exento', money.format(sale.exemptAmount)),
        if (fiscal && sale.taxableBase > 0)
          _pdfTotalLine('Base imponible', money.format(sale.taxableBase)),
        if (fiscal && sale.taxAmount > 0)
          _pdfTotalLine('ITBIS', money.format(sale.taxAmount)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _softLine),
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'TOTAL GENERAL',
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
        pw.SizedBox(height: 5),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Cant. ítems: ${sale.items.length}',
            style: pw.TextStyle(fontSize: 7.5, color: _textMuted),
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

String invoicePdfCode(String id) {
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

/// Nota de la factura sin líneas de pago duplicadas: el checkout añade
/// `Pago: <método>` a la nota, pero el método ya se muestra en el bloque
/// "FORMA DE PAGO".
String invoicePdfNoteText(String? note) {
  final raw = _clean(note);
  if (raw.isEmpty) return '';
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => !line.toLowerCase().startsWith('pago:'))
      .toList();
  return lines.join('\n').trim();
}

String invoicePdfDocumentLabel(SaleModel sale) {
  final voucherType = _clean(sale.fiscalVoucherType).toUpperCase();
  if (voucherType == 'B02') {
    return 'FACTURA / CONSUMIDOR FINAL';
  }
  if (voucherType == 'B01' || _clean(sale.ncf).isNotEmpty) {
    return 'FACTURA / CRÉDITO FISCAL';
  }
  return 'FACTURA';
}

pw.Widget _panel({
  required pw.Widget child,
  pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
  pw.EdgeInsetsGeometry margin = pw.EdgeInsets.zero,
  PdfColor fillColor = PdfColors.white,
  bool showBorder = false,
}) {
  return pw.Container(
    margin: margin,
    padding: padding,
    decoration: pw.BoxDecoration(
      color: fillColor,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: showBorder
          ? pw.Border.all(color: _panelBorder, width: 0.45)
          : null,
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
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
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
  required String issuedText,
  String? statusText,
  String? subtitle,
  String? ncf,
  DateTime? ncfExpirationDate,
  String? cashierName,
}) {
  final cleanSubtitle = _clean(subtitle);
  final cleanNcf = _clean(ncf);
  final cleanCashier = _clean(cashierName);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
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
        if (cleanSubtitle.isNotEmpty) ...[
          pw.Text(
            cleanSubtitle,
            style: pw.TextStyle(
              fontSize: 8.4,
              fontWeight: pw.FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        if (cleanNcf.isNotEmpty) _factLine('NCF', cleanNcf),
        if (ncfExpirationDate != null)
          _factLine(
            'Vencimiento',
            DateFormat('dd/MM/yyyy').format(ncfExpirationDate),
          ),
        if (cleanCashier.isNotEmpty) _factLine('Cajero', cleanCashier),
        _factLine('Expedición', issuedText),
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

pw.Widget _factLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 58,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 7.6, color: _textMuted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8.2, color: _textPrimary),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _personInfoPanel({
  required String primary,
  String? secondary,
  String? document,
  String? address,
  String title = 'DATOS',
}) {
  final phone = (secondary ?? '').trim();
  final doc = (document ?? '').trim();
  final addr = (address ?? '').trim();
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(14, 11, 14, 11),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 7),
        _personLine('Nombre', primary, strong: true),
        if (doc.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _personLine('RNC/Cédula', doc),
        ],
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _personLine('Teléfono', phone),
        ],
        if (addr.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _personLine('Dirección', addr),
        ],
      ],
    ),
  );
}

pw.Widget _personLine(String label, String value, {bool strong = false}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 58,
        child: pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8.1, color: _textMuted),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8.8,
            color: strong ? _textPrimary : _textMuted,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
  PdfColor? textColor,
  bool noWrap = false,
  double horizontalPadding = 6,
  double fontSize = 7.6,
}) {
  return pw.Container(
    padding: pw.EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: 6,
    ),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      // Nunca partir un importe: una sola línea.
      maxLines: noWrap ? 1 : null,
      softWrap: noWrap ? false : null,
      style: pw.TextStyle(
        fontSize: fontSize,
        color: textColor ?? _textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// Celda monetaria del detalle: fuente ligeramente menor (7.0), padding
/// reducido y SIEMPRE en una sola línea (sin wrap ni salto de línea).
pw.Widget _moneyCell(String text, {PdfColor? textColor}) {
  return _bodyCell(
    text,
    align: pw.TextAlign.right,
    textColor: textColor,
    noWrap: true,
    horizontalPadding: 4,
    fontSize: 7.0,
  );
}

pw.Widget _emptyCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _textMuted)),
  );
}

pw.Widget _pdfTotalLine(
  String label,
  String value, {
  PdfColor? amountColor,
}) {
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
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9.1,
            color: amountColor ?? _textPrimary,
          ),
        ),
      ],
    ),
  );
}
