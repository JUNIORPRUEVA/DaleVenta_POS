import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../core/tax/product_tax_preview_calculator.dart';
import '../../../core/uom/uom_formatters.dart';
import '../../../core/utils/pdf_file_actions.dart';
import '../cotizacion_models.dart';

final PdfColor _pageBackground = PdfColors.white;
final PdfColor _borderColor = PdfColor.fromHex('#D9E2EC');
final PdfColor _panelBorder = PdfColor.fromHex('#CBD5E1');
final PdfColor _softFill = PdfColor.fromHex('#F8FAFC');
final PdfColor _softLine = PdfColor.fromHex('#E2E8F0');
final PdfColor _headingBlack = PdfColor.fromHex('#0F172A');
final PdfColor _textPrimary = PdfColor.fromHex('#172033');
final PdfColor _textMuted = PdfColor.fromHex('#64748B');
final PdfColor _accentBlue = PdfColor.fromHex('#1957E6');
final PdfColor _danger = PdfColor.fromHex('#B42318');

Future<Uint8List> buildCotizacionPdf({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) async {
  final viewData = buildCotizacionPdfViewData(
    cotizacion: cotizacion,
    company: company,
  );
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await pdfResolveCompanyLogo(company);

  final doc = pw.Document(title: 'Cotización', author: viewData.company.name);

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
      header: (context) => _pageHeader(
        company: viewData.company,
        quote: viewData.quote,
        customer: viewData.customer,
        logoImage: logoImage,
        dateFmt: dateFmt,
        showFiscalCondition: viewData.totals.fiscalEnabled,
        pageNumber: context.pageNumber,
        pagesCount: context.pagesCount,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        ..._detailSection(viewData, money, qtyFmt),
        pw.SizedBox(height: 14),
        _bottomSection(viewData, money),
      ],
    ),
  );

  return doc.save();
}

CotizacionPdfViewData buildCotizacionPdfViewData({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) {
  final fiscal = cotizacion.hasFiscalSnapshot;
  final subtotal = _roundMoney(
    fiscal
        ? cotizacion.items.fold<double>(
            0,
            (sum, item) => sum + (item.effectiveOriginalUnitPrice * item.qty),
          )
        : cotizacion.subtotalBeforeDiscount,
  );
  final productDiscount = _roundMoney(
    cotizacion.items.fold<double>(0, (sum, item) => sum + item.discountAmount),
  );
  final netRevenue = _roundMoney(
    fiscal
        ? cotizacion.taxableBase + cotizacion.exemptAmount
        : cotizacion.subtotal,
  );
  final totalNetDiscount = _roundMoney(
    fiscal ? subtotal - netRevenue : cotizacion.discountAmount,
  );
  final inferredGeneralDiscount = _roundMoney(
    totalNetDiscount - productDiscount,
  );
  final generalDiscount = _roundMoney(
    inferredGeneralDiscount > 0
        ? inferredGeneralDiscount
        : cotizacion.globalDiscountAmount,
  );
  final shouldCalculateLineFiscal =
      fiscal &&
      cotizacion.items.any(
        (item) =>
            item.taxableBase <= 0 &&
            item.exemptAmount <= 0 &&
            item.taxAmount <= 0,
      );
  final calculatedFiscal = shouldCalculateLineFiscal
      ? ProductTaxPreviewCalculator.calculateCart(
          lines: [
            for (final item in cotizacion.items)
              ProductCartTaxLineInput(
                price: item.unitPrice,
                quantity: item.qty,
                taxTreatment: item.taxTreatment,
                taxRate: item.taxRate > 0 ? item.taxRate : null,
                taxPriceMode: item.taxPriceMode.trim().toUpperCase() == 'NO_TAX'
                    ? cotizacion.fiscalPriceMode
                    : item.taxPriceMode,
              ),
          ],
          companyTaxEnabled: true,
          companyPricesIncludeTax: cotizacion.fiscalPriceMode == 'TAX_INCLUDED',
          companyDefaultTaxRate: cotizacion.itbisRate,
          globalDiscountAmount: generalDiscount,
        )
      : null;
  final rows = cotizacion.items
      .toList(growable: false)
      .asMap()
      .entries
      .map((entry) {
        final index = entry.key;
        final item = entry.value;
        final calculatedLine = calculatedFiscal?.lines[index];
        final gross = _roundMoney(
          calculatedLine?.grossAmount ??
              (fiscal && item.grossAmount > 0
                  ? item.grossAmount
                  : item.effectiveOriginalUnitPrice * item.qty),
        );
        final calculatedPreview = calculatedLine?.preview;
        final productLineDiscount = _roundMoney(item.discountAmount);
        final displayedLineDiscount = _roundMoney(
          productLineDiscount > 0
              ? productLineDiscount
              : item.lineDiscountAmount > 0
              ? item.lineDiscountAmount
              : 0,
        );
        final fallbackLineTotal = _roundMoney(item.unitPrice * item.qty);
        final total = _roundMoney(calculatedPreview?.finalAmount ?? item.total);
        final taxable = fiscal
            ? _roundMoney(calculatedPreview?.baseAmount ?? item.taxableBase)
            : 0.0;
        final exempt = fiscal
            ? _roundMoney(calculatedPreview?.exemptAmount ?? item.exemptAmount)
            : cotizacion.includeItbis
            ? 0.0
            : fallbackLineTotal;
        final base = fiscal
            ? _roundMoney(taxable > 0 ? taxable : exempt)
            : fallbackLineTotal;
        final tax = fiscal
            ? _roundMoney(calculatedPreview?.taxAmount ?? item.taxAmount)
            : 0.0;
        final treatment = _normalizeTaxTreatment(item.taxTreatment);
        final taxLabel = fiscal
            ? item.taxExempt || item.exemptAmount > 0 || treatment == 'EXEMPT'
                  ? 'Exento'
                  : item.taxIncluded
                  ? 'Gravado incl.'
                  : 'Gravado + ITBIS'
            : cotizacion.includeItbis
            ? 'ITBIS ${_percent(cotizacion.itbisRate)}'
            : 'Sin impuesto';

        return CotizacionPdfLineData(
          description: _fallback(
            item.nombre,
            fallback: 'Producto sin descripción',
          ),
          quantity: item.qty,
          unit: item.unitSnapshot,
          unitPrice: _roundMoney(item.effectiveOriginalUnitPrice),
          grossAmount: gross,
          lineDiscountAmount: displayedLineDiscount,
          productDiscountAmount: productLineDiscount,
          taxableBase: taxable,
          exemptAmount: exempt,
          baseAmount: base,
          taxAmount: tax,
          total: total,
          taxLabel: taxLabel,
        );
      })
      .toList(growable: false);

  return CotizacionPdfViewData(
    company: CotizacionPdfCompanyData(
      name: _fallback(company?.companyName, fallback: 'FULLTECH'),
      rnc: _clean(company?.rnc),
      phone: _clean(company?.phone),
      address: _clean(company?.address),
    ),
    customer: CotizacionPdfCustomerData(
      name: _customerDisplayName(cotizacion.customerName),
      taxId: _clean(cotizacion.customerTaxId),
      phone: _clean(cotizacion.customerPhone),
      address: _clean(cotizacion.customerAddress),
      email: _clean(cotizacion.customerEmail),
    ),
    quote: CotizacionPdfQuoteData(
      code: _buildQuoteCode(cotizacion.id),
      issuedAt: cotizacion.createdAt,
      expiresAt: cotizacion.createdAt.add(const Duration(days: 15)),
      fiscalCondition: _fiscalCondition(cotizacion),
    ),
    lines: rows,
    totals: CotizacionPdfTotalsData(
      subtotal: subtotal,
      productDiscount: productDiscount,
      generalDiscount: generalDiscount,
      exemptAmount: _roundMoney(fiscal ? cotizacion.exemptAmount : 0),
      taxableBase: _roundMoney(fiscal ? cotizacion.taxableBase : 0),
      taxAmount: _roundMoney(cotizacion.itbisAmount),
      total: _roundMoney(cotizacion.total),
      fiscalEnabled: fiscal,
    ),
    note: cotizacion.note.trim(),
  );
}

pw.Widget _pageHeader({
  required CotizacionPdfCompanyData company,
  required CotizacionPdfQuoteData quote,
  required CotizacionPdfCustomerData customer,
  required pw.MemoryImage? logoImage,
  required DateFormat dateFmt,
  required bool showFiscalCondition,
  required int pageNumber,
  required int pagesCount,
}) {
  if (pageNumber > 1) {
    return _continuationHeader(
      company: company,
      quote: quote,
      pageNumber: pageNumber,
      pagesCount: pagesCount,
    );
  }

  return _panel(
    margin: const pw.EdgeInsets.only(bottom: 13),
    padding: const pw.EdgeInsets.fromLTRB(0, 2, 0, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _logoBox(companyName: company.name, logoImage: logoImage),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          company.name,
                          style: pw.TextStyle(
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (company.rnc.isNotEmpty)
                          _companyLine('RNC: ${company.rnc}'),
                        if (company.phone.isNotEmpty)
                          _companyLine('Tel: ${company.phone}'),
                        if (company.address.isNotEmpty)
                          _companyLine(company.address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 222,
              child: _quoteFactsPanel(
                quoteCode: quote.code,
                issuedText: dateFmt.format(quote.issuedAt),
                expiresText: dateFmt.format(quote.expiresAt),
                taxText: quote.fiscalCondition,
                showFiscalCondition: showFiscalCondition,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1.1, color: _softLine),
        pw.SizedBox(height: 9),
        _customerPanel(customer),
      ],
    ),
  );
}

pw.Widget _continuationHeader({
  required CotizacionPdfCompanyData company,
  required CotizacionPdfQuoteData quote,
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
                company.name,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Cotización · Continuación',
                style: pw.TextStyle(fontSize: 8, color: _textMuted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              quote.code,
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

pw.Widget _pageFooter(int pageNumber, int totalPages) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Text(
          'FullPOS Cloud',
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

List<pw.Widget> _detailSection(
  CotizacionPdfViewData data,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final hasProductDiscount = data.lines.any(
    (item) => item.productDiscountAmount > 0,
  );
  final showTaxColumn = data.totals.fiscalEnabled;
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _headingBlack),
      children: [
        _headerCell('Descripción', align: pw.TextAlign.left),
        _headerCell('Cant.'),
        _headerCell('Precio unidad', align: pw.TextAlign.right),
        if (hasProductDiscount)
          _headerCell('Descuento', align: pw.TextAlign.right),
        if (showTaxColumn) _headerCell('ITBIS', align: pw.TextAlign.right),
        _headerCell('Total', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (data.lines.isEmpty) {
    rows.add(
      pw.TableRow(
        children: [
          _bodyCell('No hay productos registrados en esta cotización.'),
          _bodyCell(''),
          _bodyCell(''),
          if (hasProductDiscount) _bodyCell(''),
          if (showTaxColumn) _bodyCell(''),
          _bodyCell(''),
        ],
      ),
    );
  } else {
    for (var index = 0; index < data.lines.length; index++) {
      final item = data.lines[index];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isOdd ? PdfColor.fromHex('#FBFDFF') : PdfColors.white,
          ),
          children: [
            _descriptionCell(item.description),
            _bodyCell(
              formatQuantityWithUnit(item.quantity, unit: item.unit),
              align: pw.TextAlign.center,
            ),
            _bodyCell(money.format(item.unitPrice), align: pw.TextAlign.right),
            if (hasProductDiscount)
              _bodyCell(
                item.productDiscountAmount > 0
                    ? '-${money.format(item.productDiscountAmount)}'
                    : '-',
                align: pw.TextAlign.right,
                textColor: item.productDiscountAmount > 0
                    ? _danger
                    : _textMuted,
              ),
            if (showTaxColumn)
              _bodyCell(
                money.format(item.taxAmount),
                align: pw.TextAlign.right,
              ),
            _bodyCell(
              money.format(item.total),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }
  }

  return [
    pw.Text(
      'Detalle de productos',
      style: pw.TextStyle(
        fontSize: 10.8,
        fontWeight: pw.FontWeight.bold,
        color: _textPrimary,
      ),
    ),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: _panelBorder, width: 0.45),
        bottom: pw.BorderSide(color: _panelBorder, width: 0.45),
        left: pw.BorderSide(color: _panelBorder, width: 0.45),
        right: pw.BorderSide(color: _panelBorder, width: 0.45),
        horizontalInside: pw.BorderSide(color: _borderColor, width: 0.45),
      ),
      columnWidths: _detailColumnWidths(hasProductDiscount, showTaxColumn),
      children: rows,
    ),
  ];
}

Map<int, pw.TableColumnWidth> _detailColumnWidths(
  bool hasProductDiscount,
  bool showTaxColumn,
) {
  if (hasProductDiscount && showTaxColumn) {
    return const {
      0: pw.FlexColumnWidth(3.45),
      1: pw.FlexColumnWidth(0.62),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.02),
      4: pw.FlexColumnWidth(0.92),
      5: pw.FlexColumnWidth(1.12),
    };
  }
  if (hasProductDiscount) {
    return const {
      0: pw.FlexColumnWidth(3.45),
      1: pw.FlexColumnWidth(0.62),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.02),
      4: pw.FlexColumnWidth(1.12),
    };
  }
  if (showTaxColumn) {
    return const {
      0: pw.FlexColumnWidth(4.0),
      1: pw.FlexColumnWidth(0.68),
      2: pw.FlexColumnWidth(1.18),
      3: pw.FlexColumnWidth(0.92),
      4: pw.FlexColumnWidth(1.2),
    };
  }
  return const {
    0: pw.FlexColumnWidth(4.1),
    1: pw.FlexColumnWidth(0.7),
    2: pw.FlexColumnWidth(1.2),
    3: pw.FlexColumnWidth(1.2),
  };
}

pw.Widget _bottomSection(CotizacionPdfViewData data, NumberFormat money) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _panel(
          padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
          fillColor: _softFill,
          showBorder: true,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Notas',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              pw.SizedBox(height: 7),
              pw.Text(
                data.note.isEmpty ? 'Gracias por preferirnos.' : data.note,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: data.note.isEmpty ? _textMuted : _textPrimary,
                  fontStyle: data.note.isEmpty
                      ? pw.FontStyle.italic
                      : pw.FontStyle.normal,
                  lineSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 14),
      pw.SizedBox(width: 238, child: _totalsPanel(data.totals, money)),
    ],
  );
}

pw.Widget _totalsPanel(CotizacionPdfTotalsData totals, NumberFormat money) {
  final showTaxRows =
      totals.fiscalEnabled ||
      totals.taxableBase > 0 ||
      totals.exemptAmount > 0 ||
      totals.taxAmount > 0;

  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
    fillColor: _softFill,
    showBorder: true,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Resumen',
          style: pw.TextStyle(
            fontSize: 10.8,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 9),
        _totalLine('Subtotal', money.format(totals.subtotal)),
        if (totals.productDiscount > 0)
          _totalLine(
            'Descuentos por productos',
            '-${money.format(totals.productDiscount)}',
            valueColor: _danger,
          ),
        if (totals.generalDiscount > 0)
          _totalLine(
            'Descuento general',
            '-${money.format(totals.generalDiscount)}',
            valueColor: _danger,
          ),
        if (showTaxRows) ...[
          if (totals.exemptAmount > 0)
            _totalLine('Monto exento', money.format(totals.exemptAmount)),
          if (totals.taxableBase > 0)
            _totalLine('Base imponible', money.format(totals.taxableBase)),
          if (totals.taxAmount > 0)
            _totalLine('ITBIS', money.format(totals.taxAmount)),
        ],
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _softLine),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 10.4,
                    fontWeight: pw.FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Text(
                money.format(totals.total),
                style: pw.TextStyle(
                  fontSize: 12,
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

Future<void> shareCotizacionPdf({
  required Uint8List bytes,
  required CotizacionModel cotizacion,
}) async {
  final filename = buildCotizacionPdfFileName(cotizacion);
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<bool> saveCotizacionPdfToDownloads({
  required Uint8List bytes,
  required CotizacionModel cotizacion,
}) {
  return savePdfBytes(
    bytes: bytes,
    fileName: buildCotizacionPdfFileName(cotizacion),
  );
}

String buildCotizacionPdfFileName(CotizacionModel cotizacion) {
  final customerName = cotizacion.customerName.trim();
  final hasRealCustomerName =
      customerName.isNotEmpty &&
      customerName.toLowerCase() != 'sin cliente' &&
      customerName.toLowerCase() != 'consumidor final';
  final customerToken = hasRealCustomerName ? _fileNameToken(customerName) : '';
  final quoteToken = _buildQuoteCode(cotizacion.id);
  final token = customerToken.isNotEmpty ? customerToken : quoteToken;
  return '$token.pdf';
}

String _fileNameToken(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();
}

String _buildQuoteCode(String id) {
  final token = _buildFileToken(id, length: 8, fallback: 'MANUAL');
  return 'COT-$token';
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

String _customerDisplayName(String? value) {
  final cleaned = _clean(value);
  final normalized = cleaned.toLowerCase();
  if (cleaned.isEmpty ||
      normalized == 'sin cliente' ||
      normalized == 'cliente no especificado') {
    return 'Consumidor final';
  }
  return cleaned;
}

double _roundMoney(double value) => (value * 100).round() / 100;

String _normalizeTaxTreatment(String value) => value.trim().toUpperCase();

String _percent(double rate) => '${(rate * 100).toStringAsFixed(0)}%';

String _fiscalCondition(CotizacionModel cotizacion) {
  if (!cotizacion.hasFiscalSnapshot && !cotizacion.includeItbis) {
    return 'Impuestos desactivados';
  }
  if (cotizacion.fiscalPriceMode == 'TAX_ADDED') {
    return 'ITBIS agregado al precio';
  }
  if (cotizacion.fiscalPriceMode == 'TAX_INCLUDED') {
    return 'Precios con ITBIS incluido';
  }
  if (cotizacion.includeItbis) return 'ITBIS ${_percent(cotizacion.itbisRate)}';
  return 'Sin impuesto';
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
    width: 60,
    height: 60,
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
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8.4, color: _textMuted)),
  );
}

pw.Widget _quoteFactsPanel({
  required String quoteCode,
  required String issuedText,
  required String expiresText,
  required String taxText,
  required bool showFiscalCondition,
}) {
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
          'COTIZACIÓN',
          style: pw.TextStyle(
            fontSize: 8.2,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          quoteCode,
          style: pw.TextStyle(
            fontSize: 12.4,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 6),
        _factLine('Expedición', issuedText),
        _factLine('Vencimiento', expiresText),
        if (showFiscalCondition) _factLine('Condición', taxText),
      ],
    ),
  );
}

pw.Widget _customerPanel(CotizacionPdfCustomerData customer) {
  final cleanName = customer.name.trim();
  final isFinalConsumer =
      cleanName.isEmpty ||
      cleanName.toLowerCase() == 'sin cliente' ||
      cleanName.toLowerCase() == 'cliente no especificado' ||
      cleanName.toLowerCase() == 'consumidor final';
  final rows = <pw.Widget>[
    if (isFinalConsumer)
      _plainCustomerName('Consumidor final')
    else ...[
      _personLine('Nombre', cleanName, strong: true),
      if (customer.taxId.isNotEmpty) _personLine('RNC/Cédula', customer.taxId),
      if (customer.phone.isNotEmpty) _personLine('Teléfono', customer.phone),
      if (customer.address.isNotEmpty)
        _personLine('Dirección', customer.address),
      if (customer.email.isNotEmpty) _personLine('Correo', customer.email),
    ],
  ];

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DATOS DEL CLIENTE',
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(spacing: 18, runSpacing: 5, children: rows),
      ],
    ),
  );
}

pw.Widget _plainCustomerName(String value) {
  return pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: 9,
      color: _textPrimary,
      fontWeight: pw.FontWeight.bold,
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
          width: 62,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 7.5, color: _textMuted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8.1, color: _textPrimary),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _personLine(String label, String value, {bool strong = false}) {
  return pw.SizedBox(
    width: 235,
    child: pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: 8.2, color: _textMuted),
        children: [
          pw.TextSpan(text: '$label: '),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              color: strong ? _textPrimary : _textMuted,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _descriptionCell(String description) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    alignment: pw.Alignment.centerLeft,
    child: pw.Text(
      description,
      style: pw.TextStyle(
        fontSize: 8,
        color: _textPrimary,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
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
        fontSize: 7.2,
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
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 7.6,
        color: textColor ?? _textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _totalLine(String label, String value, {PdfColor? valueColor}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8.8, color: _textPrimary),
          ),
        ),
        pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 8.8,
            color: valueColor ?? _textPrimary,
            fontWeight: valueColor != null
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class CotizacionPdfViewData {
  const CotizacionPdfViewData({
    required this.company,
    required this.customer,
    required this.quote,
    required this.lines,
    required this.totals,
    this.note = '',
  });

  final CotizacionPdfCompanyData company;
  final CotizacionPdfCustomerData customer;
  final CotizacionPdfQuoteData quote;
  final List<CotizacionPdfLineData> lines;
  final CotizacionPdfTotalsData totals;
  final String note;
}

class CotizacionPdfCompanyData {
  const CotizacionPdfCompanyData({
    required this.name,
    required this.rnc,
    required this.phone,
    required this.address,
  });

  final String name;
  final String rnc;
  final String phone;
  final String address;
}

class CotizacionPdfCustomerData {
  const CotizacionPdfCustomerData({
    required this.name,
    required this.taxId,
    required this.phone,
    required this.address,
    required this.email,
  });

  final String name;
  final String taxId;
  final String phone;
  final String address;
  final String email;
}

class CotizacionPdfQuoteData {
  const CotizacionPdfQuoteData({
    required this.code,
    required this.issuedAt,
    required this.expiresAt,
    required this.fiscalCondition,
  });

  final String code;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String fiscalCondition;
}

class CotizacionPdfLineData {
  const CotizacionPdfLineData({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.grossAmount,
    required this.lineDiscountAmount,
    required this.productDiscountAmount,
    required this.taxableBase,
    required this.exemptAmount,
    required this.baseAmount,
    required this.taxAmount,
    required this.total,
    required this.taxLabel,
  });

  final String description;
  final double quantity;
  final UnitOfMeasureModel unit;
  final double unitPrice;
  final double grossAmount;
  final double lineDiscountAmount;
  final double productDiscountAmount;
  final double taxableBase;
  final double exemptAmount;
  final double baseAmount;
  final double taxAmount;
  final double total;
  final String taxLabel;
}

class CotizacionPdfTotalsData {
  const CotizacionPdfTotalsData({
    required this.subtotal,
    required this.productDiscount,
    required this.generalDiscount,
    required this.exemptAmount,
    required this.taxableBase,
    required this.taxAmount,
    required this.total,
    required this.fiscalEnabled,
  });

  final double subtotal;
  final double productDiscount;
  final double generalDiscount;
  final double exemptAmount;
  final double taxableBase;
  final double taxAmount;
  final double total;
  final bool fiscalEnabled;
}
