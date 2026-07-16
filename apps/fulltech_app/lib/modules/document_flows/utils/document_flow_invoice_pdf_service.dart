import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/company/company_settings_model.dart';
import '../document_flow_models.dart';

final PdfColor _pageBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _cardBackground = PdfColor.fromHex('#FFFFFF');
final PdfColor _lineColor = PdfColor.fromHex('#E5EAF1');
final PdfColor _brandDark = PdfColor.fromHex('#243145');
final PdfColor _brandGold = PdfColor.fromHex('#B78A3D');
final PdfColor _textPrimary = PdfColor.fromHex('#1F2430');
final PdfColor _textMuted = PdfColor.fromHex('#6B7484');
final PdfColor _tableAlt = PdfColor.fromHex('#FAFBFD');

Future<Uint8List> buildDocumentFlowInvoicePdf({
  required OrderDocumentFlowModel flow,
  required String currency,
  required List<DocumentFlowInvoiceItem> items,
  required double tax,
  required double subtotal,
  required double total,
  required String notes,
  CompanySettings? company,
}) async {
  final money = NumberFormat.currency(
    locale: 'en_US',
    symbol: _currencySymbol(currency),
  );
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final invoiceNumber = _buildInvoiceNumber(flow.order.id);
  final companyName = _fallback(company?.companyName, fallback: 'FULLTECH');
  final logoImage = _decodeLogo(company?.logoBase64);
  final issueDate = _resolveIssueDate(flow, dateFmt);
  final clientName = _fallback(
    flow.invoiceDraft.clientName,
    fallback: flow.order.client.nombre,
  );
  final clientPhone = _fallback(
    flow.invoiceDraft.clientPhone,
    fallback: flow.order.client.telefono,
  );
  final clientAddress = _clean(flow.order.client.direccion);
  final orderCode = _shortCode(flow.order.id);
  final quotationCode = _shortCodeOrEmpty(flow.order.quotationId ?? '');
  final serviceType = _clean(flow.order.serviceType);
  final category = _clean(flow.order.category);
  final orderStatus = _clean(flow.order.status);

  final doc = pw.Document(title: 'Factura', author: companyName);

  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 16),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      build: (context) => pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.topCenter,
        child: pw.SizedBox(
          width: 555,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _cardBackground,
              border: pw.Border.all(color: _lineColor),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _headerRow(
                  companyName: companyName,
                  logoImage: logoImage,
                  rnc: _clean(company?.rnc),
                  phone: _clean(company?.phone),
                  address: _clean(company?.address),
                  invoiceNumber: invoiceNumber,
                  issueDate: issueDate,
                  currency: currency,
                  orderStatus: orderStatus,
                ),
                pw.SizedBox(height: 10),
                pw.Container(height: 1, color: _lineColor),
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _factsBlock(
                        rows: [
                          _FactRow('Cliente', clientName),
                          _FactRow('Telefono', clientPhone),
                          _FactRow('Direccion', clientAddress),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: _factsBlock(
                        rows: [
                          _FactRow('Orden', orderCode),
                          _FactRow('Cotizacion', quotationCode),
                          _FactRow('Servicio', serviceType),
                          _FactRow('Categoria', category),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                _itemsTable(items, money, qtyFmt),
                pw.SizedBox(height: 10),
                _footerSection(
                  notes: notes,
                  money: money,
                  subtotal: subtotal,
                  tax: tax,
                  total: total,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  return doc.save();
}

pw.Widget _headerRow({
  required String companyName,
  required pw.MemoryImage? logoImage,
  required String rnc,
  required String phone,
  required String address,
  required String invoiceNumber,
  required String issueDate,
  required String currency,
  required String orderStatus,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Expanded(
        flex: 6,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 44,
              height: 44,
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(
                color: _cardBackground,
                border: pw.Border.all(color: _lineColor),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: logoImage != null
                  ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                  : pw.Center(
                      child: pw.Text(
                        companyName.substring(0, 1).toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _brandDark,
                        ),
                      ),
                    ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _brandDark,
                    ),
                  ),
                  if (rnc.isNotEmpty)
                    pw.Text(
                      'RNC: $rnc',
                      style: pw.TextStyle(fontSize: 8, color: _textMuted),
                    ),
                  if (phone.isNotEmpty)
                    pw.Text(
                      'Tel: $phone',
                      style: pw.TextStyle(fontSize: 8, color: _textMuted),
                    ),
                  if (address.isNotEmpty)
                    pw.Text(
                      address,
                      style: pw.TextStyle(fontSize: 7.8, color: _textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        flex: 5,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _cardBackground,
            border: pw.Border.all(color: _lineColor),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'FACTURA',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandGold,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                invoiceNumber,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandDark,
                ),
              ),
              pw.SizedBox(height: 5),
              _inlineFactRow('Fecha', issueDate),
              _inlineFactRow('Moneda', currency),
              _inlineFactRow('Estado', orderStatus),
            ],
          ),
        ),
      ),
    ],
  );
}

pw.Widget _factsBlock({required List<_FactRow> rows}) {
  final visibleRows = rows
      .where((row) => row.value.trim().isNotEmpty)
      .toList(growable: false);
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      border: pw.Border.all(color: _lineColor),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleRows.length; index++) ...[
          if (index > 0) pw.SizedBox(height: 4),
          _inlineFactRow(visibleRows[index].label, visibleRows[index].value),
        ],
      ],
    ),
  );
}

pw.Widget _itemsTable(
  List<DocumentFlowInvoiceItem> items,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _brandDark),
      children: [
        _headerCell('Descripcion'),
        _headerCell('Cant.', align: pw.TextAlign.center),
        _headerCell('Unitario', align: pw.TextAlign.right),
        _headerCell('Importe', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (items.isEmpty) {
    rows.add(
      pw.TableRow(
        children: [
          _bodyCell('No hay conceptos registrados en esta factura.'),
          _bodyCell('-', align: pw.TextAlign.center),
          _bodyCell('-', align: pw.TextAlign.right),
          _bodyCell(money.format(0), align: pw.TextAlign.right),
        ],
      ),
    );
  } else {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isEven ? PdfColors.white : _tableAlt,
          ),
          children: [
            _bodyCell(item.description.trim()),
            _bodyCell(qtyFmt.format(item.qty), align: pw.TextAlign.center),
            _bodyCell(money.format(item.unitPrice), align: pw.TextAlign.right),
            _bodyCell(
              money.format(item.lineTotal),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }
  }

  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: _cardBackground,
      border: pw.Border.all(color: _lineColor),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _lineColor, width: 0.3),
        top: pw.BorderSide(color: _lineColor, width: 0.3),
        bottom: pw.BorderSide(color: _lineColor, width: 0.3),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(5.3),
        1: const pw.FlexColumnWidth(0.8),
        2: const pw.FlexColumnWidth(1.55),
        3: const pw.FlexColumnWidth(1.6),
      },
      children: rows,
    ),
  );
}

pw.Widget _footerSection({
  required String notes,
  required NumberFormat money,
  required double subtotal,
  required double tax,
  required double total,
}) {
  final cleanNotes = notes.trim();
  final hasTax = tax.abs() > 0.0001;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: cleanNotes.isEmpty
            ? pw.SizedBox()
            : pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _cardBackground,
                  border: pw.Border.all(color: _lineColor),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Observaciones',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      cleanNotes,
                      style: pw.TextStyle(
                        fontSize: 8.2,
                        color: _textPrimary,
                        lineSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      if (cleanNotes.isNotEmpty) pw.SizedBox(width: 10),
      pw.SizedBox(
        width: 210,
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _cardBackground,
            border: pw.Border.all(color: _lineColor),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _totalLine('Subtotal', money.format(subtotal)),
              if (hasTax) _totalLine('Impuesto', money.format(tax)),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Container(height: 1, color: _lineColor),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: _brandDark,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: _totalLine(
                  'Total',
                  money.format(total),
                  highlight: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

pw.Widget _inlineFactRow(String label, String value) {
  final cleanValue = value.trim();
  if (cleanValue.isEmpty) {
    return pw.SizedBox();
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 54,
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
          ),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          cleanValue,
          style: pw.TextStyle(fontSize: 8, color: _textPrimary),
        ),
      ),
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
    ),
  );
}

pw.Widget _bodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 7.9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _textPrimary,
      ),
    ),
  );
}

pw.Widget _totalLine(String label, String value, {bool highlight = false}) {
  return pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: highlight ? 9.2 : 8.2,
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: highlight ? PdfColors.white : _textPrimary,
          ),
        ),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: highlight ? 9.6 : 8.4,
          fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: highlight ? PdfColors.white : _textPrimary,
        ),
      ),
    ],
  );
}

String _resolveIssueDate(OrderDocumentFlowModel flow, DateFormat dateFmt) {
  final orderDate =
      flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt;
  if (orderDate == null) {
    return '';
  }
  return dateFmt.format(orderDate.toLocal());
}

String _currencySymbol(String currency) {
  switch (currency.trim().toUpperCase()) {
    case 'DOP':
    case 'RD\$':
      return 'RD\$';
    case 'USD':
      return 'US\$';
    case 'EUR':
      return '€';
    default:
      return '${currency.trim()} ';
  }
}

String _buildInvoiceNumber(String orderId) {
  final token = orderId.replaceAll('-', '').trim();
  final shortToken = token.length > 8 ? token.substring(0, 8) : token;
  return 'FACT-${shortToken.toUpperCase()}';
}

String _shortCode(String raw) {
  final normalized = raw.trim().replaceAll('-', '');
  if (normalized.isEmpty) return '';
  if (normalized.length <= 8) return normalized.toUpperCase();
  return normalized.substring(0, 8).toUpperCase();
}

String _shortCodeOrEmpty(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return '';
  return _shortCode(normalized);
}

String _fallback(String? value, {required String fallback}) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? fallback : normalized;
}

String _clean(String? value) => (value ?? '').trim();

class _FactRow {
  final String label;
  final String value;

  const _FactRow(this.label, this.value);
}

pw.MemoryImage? _decodeLogo(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty) return null;
  final clean = normalized.contains(',')
      ? normalized.split(',').last
      : normalized;
  try {
    return pw.MemoryImage(base64Decode(clean));
  } catch (_) {
    return null;
  }
}
