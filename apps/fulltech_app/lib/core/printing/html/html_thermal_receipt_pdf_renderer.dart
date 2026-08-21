import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import '../esc_pos/thermal_receipt_view_model.dart';

class HtmlThermalReceiptPdfRenderer {
  const HtmlThermalReceiptPdfRenderer({
    this.paperWidthMm = 80,
    this.warrantyPolicy = '',
  });

  final double paperWidthMm;
  final String warrantyPolicy;

  Future<Uint8List> render(ThermalReceiptViewModel receipt) async {
    final doc = pw.Document(
      author: 'FullPOS Cloud',
      title: receipt.ticketNumber,
    );
    final pageWidth = paperWidthMm * PdfPageFormat.mm;
    final pageHeight = _estimatedHeight(receipt);
    final contentPadding = pw.EdgeInsets.only(
      left: 0.5 * PdfPageFormat.mm,
      right: 8.0 * PdfPageFormat.mm,
      top: 2.2 * PdfPageFormat.mm,
      bottom: 3 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          padding: contentPadding,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              _header(receipt),
              _rule(dashed: true),
              _invoiceMeta(receipt),
              _rule(dashed: true),
              _fiscal(receipt),
              _client(receipt),
              _items(receipt),
              _totals(receipt),
              _payment(receipt),
              _notes(receipt),
              _warrantyPolicy(),
              _footer(),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _header(ThermalReceiptViewModel receipt) {
    final company = receipt.company;
    final logoBytes = company.logoBytes;
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.8 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 16 * PdfPageFormat.mm,
            height: 16 * PdfPageFormat.mm,
            child: logoBytes == null || logoBytes.isEmpty
                ? pw.Container(
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.45),
                    ),
                    child: pw.Text('LOGO', style: _style(8, bold: true)),
                  )
                : pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _clean(company.name),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: _style(13, bold: true),
                ),
                pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
                ...[
                      company.address,
                      if (company.phone.trim().isNotEmpty)
                        'Tel: ${company.phone}',
                      if (company.rnc.trim().isNotEmpty) 'RNC: ${company.rnc}',
                    ]
                    .where((line) => _clean(line).isNotEmpty)
                    .map(
                      (line) => pw.Text(
                        _clean(line),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: _style(9),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _invoiceMeta(ThermalReceiptViewModel receipt) {
    final cashier = _clean(receipt.cashierName ?? '');
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.5 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(receipt.documentTitle, style: _style(10, bold: true)),
                pw.Text('No.: ${receipt.ticketNumber}', style: _style(9)),
                if (cashier.isNotEmpty)
                  pw.Text('Cajero: $cashier', style: _style(9), maxLines: 1),
              ],
            ),
          ),
          pw.SizedBox(width: 3 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('FECHA', style: _style(10, bold: true)),
                pw.Text(_date.format(receipt.dateTime), style: _style(9)),
                pw.Text(
                  'Hora: ${_time.format(receipt.dateTime)}',
                  style: _style(9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _client(ThermalReceiptViewModel receipt) {
    final client = receipt.client;
    final name = _clean(client?.name ?? 'Consumidor Final');
    final phone = _clean(client?.phone ?? '');
    final document = _clean(client?.document ?? '');
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.5 * PdfPageFormat.mm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _inlineText('CLIENTE:', name.isEmpty ? 'CONSUMIDOR FINAL' : name),
          if (phone.isNotEmpty) _inlineText('TEL:', phone),
          if (document.isNotEmpty) _inlineText('RNC/CEDULA:', document),
        ],
      ),
    );
  }

  pw.Widget _fiscal(ThermalReceiptViewModel receipt) {
    final ncf = _clean(receipt.ncf ?? '');
    final type = _clean(receipt.fiscalVoucherType ?? '');
    if (ncf.isEmpty && type.isEmpty) return pw.SizedBox();
    final voucherLabel = _fiscalVoucherLabel(type);
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.5 * PdfPageFormat.mm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _inlineText(
            'COMPROBANTE:',
            voucherLabel.isEmpty ? 'FISCAL' : voucherLabel,
          ),
          if (ncf.isNotEmpty) _inlineText('NCF:', ncf),
        ],
      ),
    );
  }

  String _fiscalVoucherLabel(String type) {
    switch (type.trim().toUpperCase()) {
      case 'B01':
        return 'B01 - CREDITO FISCAL';
      case 'B02':
        return 'B02 - CONSUMIDOR FINAL';
      default:
        return _clean(type);
    }
  }

  pw.Widget _items(ThermalReceiptViewModel receipt) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(13),
        1: pw.FlexColumnWidth(47),
        2: pw.FlexColumnWidth(18),
        3: pw.FlexColumnWidth(22),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.55),
              bottom: pw.BorderSide(width: 0.55),
            ),
          ),
          children: [
            _tableHeader('CANT', align: pw.TextAlign.center),
            _tableHeader('ITEM'),
            _tableHeader('PRECIO', align: pw.TextAlign.right),
            _tableHeader('TOTAL', align: pw.TextAlign.right),
          ],
        ),
        for (final item in receipt.items)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.25)),
            ),
            children: [
              _tableCell(item.qtyText, align: pw.TextAlign.center),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: 1.4,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _clean(item.name).toUpperCase(),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: _style(7.8),
                    ),
                    if (item.discount > 0)
                      pw.Text(
                        'Desc. -${_money(item.discount)}',
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: _style(7.5),
                      ),
                  ],
                ),
              ),
              _tableCell(
                _amount(item.unitPrice),
                align: pw.TextAlign.right,
                fontSize: 7.8,
              ),
              _tableCell(
                _amount(item.total),
                align: pw.TextAlign.right,
                fontSize: 7.8,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _totals(ThermalReceiptViewModel receipt) {
    final rows = <pw.Widget>[
      _totalRow('SUBTOTAL', _money(receipt.subtotal)),
      if (receipt.productDiscount > 0)
        _totalRow('DESC. PRODUCTOS', '-${_money(receipt.productDiscount)}'),
      if (receipt.generalDiscount > 0)
        _totalRow('DESC. GENERAL', '-${_money(receipt.generalDiscount)}'),
      if (receipt.exemptAmount > 0)
        _totalRow('MONTO EXENTO', _money(receipt.exemptAmount)),
      if (receipt.taxableBase > 0)
        _totalRow('MONTO GRAVADO', _money(receipt.taxableBase)),
      if (receipt.taxAmount > 0) _totalRow('ITBIS', _money(receipt.taxAmount)),
      _totalRow('TOTAL', _money(receipt.total), grand: true),
    ];
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 50 * PdfPageFormat.mm,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(top: 1.8 * PdfPageFormat.mm),
          child: pw.Column(children: rows),
        ),
      ),
    );
  }

  pw.Widget _payment(ThermalReceiptViewModel receipt) {
    final payment = _clean(receipt.paymentMethod ?? '');
    if (payment.isEmpty) return pw.SizedBox();
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 50 * PdfPageFormat.mm,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(top: 1.2 * PdfPageFormat.mm),
          child: _totalRow(
            'PAGO: ${payment.toUpperCase()}',
            _money(receipt.total),
            bold: true,
          ),
        ),
      ),
    );
  }

  pw.Widget _notes(ThermalReceiptViewModel receipt) {
    final note = _clean(receipt.note ?? '');
    if (note.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _rule(dashed: true),
        pw.Text('NOTA', style: _style(8, bold: true)),
        pw.Text(
          note,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: _style(8),
        ),
      ],
    );
  }

  pw.Widget _warrantyPolicy() {
    final policy = _clean(warrantyPolicy);
    if (policy.isEmpty) return pw.SizedBox();
    final lines = _warrantyWrapLines(policy);
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: 2 * PdfPageFormat.mm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('POLITICA DE GARANTIA', style: _style(8, bold: true)),
          pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
          for (final line in lines) pw.Text(line, style: _style(7.5)),
        ],
      ),
    );
  }

  /// Full-wrap of the warranty policy text (never truncated with '...').
  /// Uses a conservative character width per paper size so every line fits
  /// the physical ticket.
  List<String> _warrantyWrapLines(String policy) {
    final width = paperWidthMm == 58 ? 30 : 48;
    return ReceiptTextUtils.wrap(policy, width);
  }

  pw.Widget _footer() {
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: 2.2 * PdfPageFormat.mm),
      child: pw.Column(
        children: [
          pw.Text('¡GRACIAS POR SU PREFERENCIA!', style: _style(9, bold: true)),
          pw.SizedBox(height: 0.4 * PdfPageFormat.mm),
          pw.Text('FullPOS Cloud', style: _style(8)),
        ],
      ),
    );
  }

  pw.Widget _rule({bool dashed = false}) {
    return pw.Container(
      margin: pw.EdgeInsets.symmetric(vertical: 1.5 * PdfPageFormat.mm),
      height: 0.45,
      color: dashed ? PdfColors.grey500 : PdfColors.black,
    );
  }

  pw.Widget _tableHeader(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.4),
      child: pw.Text(text, textAlign: align, style: _style(7.0, bold: true)),
    );
  }

  pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    double fontSize = 8,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.4),
      child: pw.Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: _style(fontSize),
      ),
    );
  }

  pw.Widget _totalRow(
    String label,
    String amount, {
    bool grand = false,
    bool bold = false,
  }) {
    final strong = grand || bold;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: grand ? 2.5 : 1),
      decoration: grand
          ? const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 0.65),
                bottom: pw.BorderSide(width: 1.4),
              ),
            )
          : null,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: _style(grand ? 11 : 8.5, bold: strong),
            ),
          ),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          pw.Text(
            amount,
            textAlign: pw.TextAlign.right,
            style: _style(grand ? 11 : 8.5, bold: strong),
          ),
        ],
      ),
    );
  }

  pw.Widget _inlineText(String label, String value) {
    return pw.RichText(
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      text: pw.TextSpan(
        style: _style(9),
        children: [
          pw.TextSpan(text: '$label ', style: _style(9, bold: true)),
          pw.TextSpan(text: value),
        ],
      ),
    );
  }

  pw.TextStyle _style(double size, {bool bold = false}) {
    return pw.TextStyle(
      font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
      fontSize: size,
      height: 1.1,
    );
  }

  double _estimatedHeight(ThermalReceiptViewModel receipt) {
    final lineDiscounts = receipt.items
        .where((item) => item.discount > 0)
        .length;
    final noteLines = _clean(receipt.note ?? '').isEmpty ? 0 : 3;
    final fiscalLines = [
      receipt.productDiscount,
      receipt.generalDiscount,
      receipt.exemptAmount,
      receipt.taxableBase,
      receipt.taxAmount,
    ].where((value) => value > 0).length;
    final ncfLines =
        (_clean(receipt.ncf ?? '').isEmpty &&
            _clean(receipt.fiscalVoucherType ?? '').isEmpty)
        ? 0
        : 2;
    final warrantyLines = _clean(warrantyPolicy).isEmpty
        ? 0
        : _warrantyWrapLines(_clean(warrantyPolicy)).length;
    final mm =
        72 +
        (receipt.items.length * 4.8) +
        (lineDiscounts * 2.8) +
        (fiscalLines * 3.5) +
        (ncfLines * 3.5) +
        (noteLines * 4.0) +
        (warrantyLines == 0 ? 0 : 12 + (warrantyLines * 3.6));
    return mm.clamp(100, 2000) * PdfPageFormat.mm;
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _money(double value) => ReceiptTextUtils.money(value);

  String _amount(double value) => _amountFormat.format(value);

  static final _amountFormat = NumberFormat('#,##0.00', 'en_US');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _time = DateFormat('h:mm a');
}
