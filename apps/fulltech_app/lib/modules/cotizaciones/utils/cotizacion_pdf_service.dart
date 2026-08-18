import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/pdf_file_actions.dart';
import '../../../core/company/company_settings_model.dart';
import '../cotizacion_models.dart';

final PdfColor _pageBackground = PdfColors.white;
final PdfColor _borderColor = PdfColor.fromHex('#E2E8F0');
final PdfColor _panelBorder = PdfColor.fromHex('#D8E1EA');
final PdfColor _softFill = PdfColor.fromHex('#F8FAFC');
final PdfColor _softLine = PdfColor.fromHex('#E6ECF2');
final PdfColor _headingBlack = PdfColor.fromHex('#111827');
final PdfColor _textPrimary = PdfColor.fromHex('#1D2430');
final PdfColor _textMuted = PdfColor.fromHex('#6C7685');
final PdfColor _accentBlue = PdfColor.fromHex('#1957E6');

Future<Uint8List> buildCotizacionPdf({
  required CotizacionModel cotizacion,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');

  final doc = pw.Document(title: 'Cotización', author: companyName);

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
        company: company,
        logoImage: logoImage,
        cotizacion: cotizacion,
        dateFmt: dateFmt,
        documentLabel: 'COTIZACIÓN',
        isContinuation: context.pageNumber > 1,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        _detailSection(cotizacion, money, qtyFmt),
        pw.SizedBox(height: _bottomAnchorGap(cotizacion.items.length)),
        _bottomSection(cotizacion, money),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _pageHeader({
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required CotizacionModel cotizacion,
  required DateFormat dateFmt,
  required String documentLabel,
  required bool isContinuation,
}) {
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final quoteCode = _buildQuoteCode(cotizacion.id);
  final rnc = _clean(company?.rnc);
  final phone = _clean(company?.phone);
  final address = _clean(company?.address);
  final customerName = _fallback(
    cotizacion.customerName,
    fallback: 'Cliente no especificado',
  );
  final customerPhone = _fallback(
    cotizacion.customerPhone,
    fallback: 'No registrado',
  );
  final issuedAt = cotizacion.createdAt;
  final expiresAt = issuedAt.add(const Duration(days: 15));
  final taxText = cotizacion.hasFiscalSnapshot && cotizacion.taxAmount > 0
      ? cotizacion.fiscalPriceMode == 'TAX_ADDED'
            ? 'ITBIS se agrega al precio'
            : 'Precios con ITBIS incluido'
      : cotizacion.includeItbis
      ? '${(cotizacion.itbisRate * 100).toStringAsFixed(0)}% ITBIS'
      : null;

  return _panel(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.fromLTRB(0, 4, 0, 10),
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
              child: _quoteFactsPanel(
                documentLabel: documentLabel,
                quoteCode: quoteCode,
                issuedText: dateFmt.format(issuedAt),
                expiresText: dateFmt.format(expiresAt),
                validityText: 'Válida por 15 días',
                taxText: taxText,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(height: 1.2, color: _softLine),
        pw.SizedBox(height: 10),
        pw.SizedBox(
          width: 325,
          child: _personInfoPanel(
            title: 'DATOS DEL CLIENTE',
            primary: customerName,
            secondary: customerPhone,
          ),
        ),
        if (isContinuation) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Continuación de la cotización',
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

pw.Widget _detailSection(
  CotizacionModel cotizacion,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  if (cotizacion.hasFiscalSnapshot) {
    return _fiscalQuoteDetailSection(cotizacion, money, qtyFmt);
  }

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

  if (cotizacion.items.isEmpty) {
    tableRows.add(
      pw.TableRow(
        children: [
          _emptyCell('No hay productos registrados en esta cotización.'),
          _emptyCell(''),
          _emptyCell(''),
          _emptyCell(''),
        ],
      ),
    );
  } else {
    for (final item in cotizacion.items) {
      tableRows.add(
        pw.TableRow(
          children: [
            _bodyCell(
              item.nombre.trim().isEmpty
                  ? 'Producto sin descripción'
                  : item.nombre.trim(),
              align: pw.TextAlign.left,
              bold: true,
            ),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(money.format(item.unitPrice), align: pw.TextAlign.right),
            _bodyCell(money.format(item.total), align: pw.TextAlign.right),
          ],
        ),
      );
    }
  }

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(0, 10, 0, 10),
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
            border: pw.Border.all(color: _panelBorder, width: 0.45),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _borderColor, width: 0.55),
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

pw.Widget _fiscalQuoteDetailSection(
  CotizacionModel cotizacion,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final modeLabel = cotizacion.fiscalPriceMode == 'TAX_ADDED'
      ? 'ITBIS se agrega al precio. Importes de línea guardados.'
      : 'Precios con ITBIS incluido. Importes de línea guardados.';
  final tableRows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _headingBlack),
      children: [
        _headerCell('Descripcion', align: pw.TextAlign.left),
        _headerCell('Cant.'),
        _headerCell('Base', align: pw.TextAlign.right),
        _headerCell('ITBIS', align: pw.TextAlign.right),
        _headerCell('Total', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (cotizacion.items.isEmpty) {
    tableRows.add(
      pw.TableRow(
        children: [
          _emptyCell('No hay productos registrados en esta cotización.'),
          _emptyCell(''),
          _emptyCell(''),
          _emptyCell(''),
          _emptyCell(''),
        ],
      ),
    );
  } else {
    for (final item in cotizacion.items) {
      final isExempt = item.taxExempt || item.exemptAmount > 0;
      final description = item.nombre.trim().isEmpty
          ? 'Producto sin descripción'
          : item.nombre.trim();
      tableRows.add(
        pw.TableRow(
          children: [
            _bodyCell(
              isExempt ? '$description\nExento' : description,
              align: pw.TextAlign.left,
              bold: true,
            ),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(
              money.format(
                item.taxableBase > 0 ? item.taxableBase : item.exemptAmount,
              ),
              align: pw.TextAlign.right,
            ),
            _bodyCell(money.format(item.taxAmount), align: pw.TextAlign.right),
            _bodyCell(money.format(item.total), align: pw.TextAlign.right),
          ],
        ),
      );
      if (item.lineDiscountAmount > 0) {
        tableRows.add(
          pw.TableRow(
            children: [
              _bodyCell(
                'Descuento aplicado',
                align: pw.TextAlign.left,
                textColor: PdfColor.fromHex('#B42318'),
              ),
              _bodyCell(''),
              _bodyCell(''),
              _bodyCell(''),
              _bodyCell(
                '-${money.format(item.lineDiscountAmount)}',
                align: pw.TextAlign.right,
                textColor: PdfColor.fromHex('#B42318'),
              ),
            ],
          ),
        );
      }
    }
  }

  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(0, 10, 0, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              'Detalle fiscal de cotización',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              modeLabel,
              style: pw.TextStyle(fontSize: 7.6, color: _textMuted),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _panelBorder, width: 0.45),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _borderColor, width: 0.55),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(5.15),
              1: pw.FlexColumnWidth(0.72),
              2: pw.FlexColumnWidth(1.42),
              3: pw.FlexColumnWidth(1.35),
              4: pw.FlexColumnWidth(1.55),
            },
            children: tableRows,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _bottomSection(CotizacionModel cotizacion, NumberFormat money) {
  final note = cotizacion.note.trim();
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _panel(
          padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
          fillColor: _softFill,
          showBorder: true,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (note.isNotEmpty) ...[
                pw.Text(
                  'Notas',
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
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 9),
                  child: pw.Container(height: 1, color: _softLine),
                ),
              ],
              pw.Text(
                'Gracias por preferirnos.',
                style: pw.TextStyle(
                  fontSize: 9.3,
                  color: _textMuted,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 14),
      pw.SizedBox(width: 228, child: _totalsPanel(cotizacion, money)),
    ],
  );
}

pw.Widget _totalsPanel(CotizacionModel cotizacion, NumberFormat money) {
  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
    fillColor: _softFill,
    showBorder: true,
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
        if (cotizacion.hasFiscalSnapshot) ...[
          if (cotizacion.discountAmount > 0)
            _totalLine(
              'Descuento',
              '-${money.format(cotizacion.discountAmount)}',
              valueColor: PdfColor.fromHex('#B42318'),
            ),
          if (cotizacion.taxableBase > 0)
            _totalLine('Base imponible', money.format(cotizacion.taxableBase)),
          if (cotizacion.exemptAmount > 0)
            _totalLine('Exento', money.format(cotizacion.exemptAmount)),
          if (cotizacion.itbisAmount > 0)
            _totalLine('ITBIS', money.format(cotizacion.itbisAmount)),
        ] else ...[
          _totalLine(
            'Subtotal',
            money.format(cotizacion.subtotalBeforeDiscount),
          ),
          if (cotizacion.hasDiscount)
            _totalLine(
              'Descuento aplicado',
              '-${money.format(cotizacion.discountAmount)}',
              valueColor: PdfColor.fromHex('#B42318'),
            ),
          if (cotizacion.hasDiscount)
            _totalLine(
              'Subtotal con descuento',
              money.format(cotizacion.subtotal),
            ),
          if (cotizacion.itbisAmount > 0)
            _totalLine('ITBIS', money.format(cotizacion.itbisAmount)),
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
                  'TOTAL COTIZADO',
                  style: pw.TextStyle(
                    fontSize: 10.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Text(
                money.format(cotizacion.total),
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

double _bottomAnchorGap(int itemCount) {
  final gap = 176 - (itemCount * 14);
  if (gap < 18) return 18;
  if (gap > 132) return 132;
  return gap.toDouble();
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

pw.Widget _quoteFactsPanel({
  required String documentLabel,
  required String quoteCode,
  required String issuedText,
  required String expiresText,
  required String validityText,
  String? taxText,
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
          documentLabel,
          style: pw.TextStyle(
            fontSize: 8.4,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          quoteCode,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 6),
        _factLine('Expedición', issuedText),
        _factLine('Vencimiento', expiresText),
        _factLine('Tiempo', validityText),
        if (taxText != null && taxText.trim().isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Text(taxText, style: pw.TextStyle(fontSize: 8, color: _textMuted)),
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
  String title = 'DATOS',
}) {
  final phone = (secondary ?? '').trim();
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
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _personLine('Teléfono', phone),
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
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
        fontSize: 7.6,
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
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8.1,
        color: textColor ?? _textPrimary,
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

pw.Widget _totalLine(String label, String value, {PdfColor? valueColor}) {
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
