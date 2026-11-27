import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import '../ecf_print_footer.dart';
import '../esc_pos/thermal_receipt_view_model.dart';

class HtmlThermalReceiptPdfRenderer {
  const HtmlThermalReceiptPdfRenderer({
    this.paperWidthMm = 80,
    this.warrantyPolicy = '',
  });

  final double paperWidthMm;
  final String warrantyPolicy;
  bool get _wideRoll => paperWidthMm == 80;
  static Future<pw.ThemeData>? _fontTheme;

  static Future<pw.ThemeData> _loadFontTheme() async {
    final regular = await rootBundle.load(
      'assets/fonts/RobotoCondensed-Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/fonts/RobotoCondensed-Medium.ttf',
    );
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }

  Future<Uint8List> render(ThermalReceiptViewModel receipt) async {
    final doc = pw.Document(
      theme: _wideRoll ? await (_fontTheme ??= _loadFontTheme()) : null,
      author: 'FullPOS Cloud',
      title: receipt.ticketNumber,
    );
    final pageWidth = paperWidthMm * PdfPageFormat.mm;
    final contentPadding = pw.EdgeInsets.only(
      // 80 mm roll, 72 mm / 576-dot printable area at 203 dpi. The driver
      // reports zero physical offset and clips everything after that area.
      left: (_wideRoll ? 0.25 : 0.5) * PdfPageFormat.mm,
      right: (_wideRoll ? 8.25 : 8.0) * PdfPageFormat.mm,
      top: 2.2 * PdfPageFormat.mm,
      bottom: 3 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        // The PDF engine measures the full column, including wrapped products,
        // confirmed collections and fiscal footer. An estimated roll height
        // silently clipped the payment section on the actual Windows print path.
        pageFormat: PdfPageFormat(pageWidth, double.infinity),
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
              ecfPrintFooter(
                receipt.ecf,
                pageLeftInsetMm: _wideRoll ? 0.25 : 0.5,
                textStyle: _wideRoll ? _style(9) : null,
              ),
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
    if (receipt.ecf != null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(company.name, style: _style(11, bold: true)),
          pw.Text('RNC: ${company.rnc}', style: _style(8)),
          pw.Text(company.address, style: _style(8)),
          if (company.phone.isNotEmpty)
            pw.Text('Tel: ${company.phone}', style: _style(8)),
        ],
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.8 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (!_wideRoll || (logoBytes != null && logoBytes.isNotEmpty)) ...[
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
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _clean(company.name),
                  style: _style(_wideRoll ? 11.5 : 13, bold: true),
                ),
                pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
                ...[
                      company.address,
                      if (company.phone.trim().isNotEmpty)
                        'Tel: ${company.phone}',
                      if (company.rnc.trim().isNotEmpty) 'RNC: ${company.rnc}',
                    ]
                    .where((line) => _clean(line).isNotEmpty)
                    .map((line) => pw.Text(_clean(line), style: _style(9))),
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
                  pw.Text(
                    'Cajero: $cashier',
                    style: _style(paperWidthMm == 58 ? 7 : 9),
                  ),
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
    if (receipt.ecf != null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in receipt.ecf!.identityLines)
            pw.Text(line, style: _style(8)),
        ],
      );
    }
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
          if (receipt.ncfExpirationDate != null)
            _inlineText(
              'VENCE:',
              DateFormat('dd/MM/yyyy').format(receipt.ncfExpirationDate!),
            ),
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
    if (receipt.ecf != null && paperWidthMm == 58) {
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _rule(),
          pw.Text('DETALLE', style: _style(8, bold: true)),
          for (final item in receipt.items) ...[
            pw.SizedBox(height: 3),
            pw.Text(item.name, style: _style(8)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${item.qtyText} x ${_money(item.unitPrice)}',
                  style: _style(7.5),
                ),
                pw.Text(_money(item.total), style: _style(8, bold: true)),
              ],
            ),
            pw.Text('ITBIS: ${_money(item.taxAmount)}', style: _style(7)),
            if (item.discount > 0)
              pw.Text('Descuento: ${_money(item.discount)}', style: _style(7)),
          ],
          _rule(),
        ],
      );
    }
    return pw.Table(
      columnWidths: _wideRoll
          ? {
              0: const pw.FixedColumnWidth(8 * PdfPageFormat.mm),
              1: const pw.FixedColumnWidth(37.5 * PdfPageFormat.mm),
              2: const pw.FixedColumnWidth(13 * PdfPageFormat.mm),
              3: const pw.FixedColumnWidth(13 * PdfPageFormat.mm),
            }
          : const {
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
                padding: pw.EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: _wideRoll ? 0.5 : 1.4,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (_wideRoll)
                      _singleLine(_clean(item.name), size: 8.6, bold: true)
                    else
                      pw.Text(
                        _clean(item.name).toUpperCase(),
                        style: _style(7.8),
                      ),
                    if (item.discount > 0)
                      pw.Text(
                        'Desc. -${_money(item.discount)}',
                        style: _style(7.5),
                      ),
                    if (receipt.ecf != null)
                      pw.Text(
                        'ITBIS: ${_money(item.taxAmount)}',
                        style: _style(7),
                      ),
                  ],
                ),
              ),
              _tableCell(
                _amount(item.unitPrice),
                align: pw.TextAlign.right,
                fontSize: paperWidthMm == 58 ? 6.2 : 7.8,
              ),
              _tableCell(
                _amount(item.total),
                align: pw.TextAlign.right,
                fontSize: paperWidthMm == 58 ? 6.2 : 7.8,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _totals(ThermalReceiptViewModel receipt) {
    final showSubtotal =
        !_wideRoll ||
        receipt.ecf != null ||
        receipt.productDiscount > 0 ||
        receipt.generalDiscount > 0 ||
        (receipt.subtotal - receipt.total).abs() > 0.005 ||
        (receipt.showTaxBreakdown &&
            (receipt.exemptAmount > 0 ||
                receipt.taxableBase > 0 ||
                receipt.taxAmount > 0));
    final rows = <pw.Widget>[
      if (showSubtotal) _totalRow('SUBTOTAL', _money(receipt.subtotal)),
      if (receipt.productDiscount > 0)
        _totalRow('DESC. PRODUCTOS', '-${_money(receipt.productDiscount)}'),
      if (receipt.generalDiscount > 0)
        _totalRow('DESC. GENERAL', '-${_money(receipt.generalDiscount)}'),
      if (receipt.showTaxBreakdown && receipt.exemptAmount > 0)
        _totalRow('MONTO EXENTO', _money(receipt.exemptAmount)),
      if (receipt.taxableBase > 0)
        _totalRow('MONTO GRAVADO', _money(receipt.taxableBase)),
      if (receipt.taxAmount > 0) _totalRow('ITBIS', _money(receipt.taxAmount)),
      _totalRow('TOTAL', _money(receipt.total), grand: true),
    ];
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: (_wideRoll ? 53 : 50) * PdfPageFormat.mm,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(
            top: (_wideRoll ? 3 : 1.8) * PdfPageFormat.mm,
          ),
          child: pw.Column(children: rows),
        ),
      ),
    );
  }

  pw.Widget _payment(ThermalReceiptViewModel receipt) {
    if (_wideRoll) return _compactPayment(receipt);
    final payment = _clean(receipt.paymentMethod ?? '');
    if (payment.isEmpty && receipt.credit == null) return pw.SizedBox();
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: (_wideRoll ? 53 : 50) * PdfPageFormat.mm,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(
            top: (_wideRoll ? 0.6 : 1.2) * PdfPageFormat.mm,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (receipt.credit case final credit?)
                for (final row in credit.rows)
                  _totalRow(
                    _wideRoll
                        ? switch (row.label) {
                            'COMPRA A CREDITO' => 'TOTAL COMPRA',
                            'SALDO PENDIENTE' => 'PENDIENTE',
                            _ => row.label,
                          }
                        : row.label,
                    _money(row.amount),
                    bold: true,
                  )
              else
                _totalRow(
                  'PAGO: ${payment.toUpperCase()}',
                  _money(receipt.total),
                  bold: true,
                ),
              if ((receipt.cashReceived ?? 0) > 0) ...[
                _totalRow(
                  _wideRoll ? 'EFECTIVO' : 'EFECTIVO RECIBIDO',
                  _money(receipt.cashReceived ?? 0),
                ),
                _totalRow('DEVUELTA', _money(receipt.changeAmount ?? 0)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _compactPayment(ThermalReceiptViewModel receipt) {
    final payment = _clean(receipt.paymentMethod ?? '');
    final detail = payment
        .replaceFirst(
          RegExp(r'^cr[eé]dito\s*(?:\+\s*)?', caseSensitive: false),
          '',
        )
        .trim();
    final allocations = detail
        .split(RegExp(r'\s+\+\s+'))
        .map(
          (part) => RegExp(
            r'^(Efectivo|Transferencia)\s+(RD\$\s*[\d,.]+)$',
            caseSensitive: false,
          ).firstMatch(part),
        )
        .toList();
    final rows = <pw.Widget>[
      if (receipt.credit case final credit?) ...[
        if ((credit.amount - receipt.total).abs() > 0.005)
          _totalRow('TOTAL COMPRA', _money(credit.amount)),
        _totalRow('ABONADO', _money(credit.paid), bold: true),
        _totalRow('PENDIENTE', _money(credit.balance), bold: true),
      ],
      // Method names appear once in NOTA; keep mixed allocations here.
      if (allocations.length > 1 && allocations.every((part) => part != null))
        for (final part in allocations)
          _totalRow(part!.group(1)!.toUpperCase(), part.group(2)!),
      _totalRow('DEVUELTA', _money(receipt.changeAmount ?? 0)),
    ];
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 53 * PdfPageFormat.mm,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(top: 0.6 * PdfPageFormat.mm),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }

  pw.Widget _notes(ThermalReceiptViewModel receipt) {
    final raw =
        (_wideRoll ? receipt.originalNote : receipt.note) ?? receipt.note ?? '';
    final customerNote = _wideRoll
        ? raw
              .split('\n')
              .where(
                (line) => !RegExp(
                  r'^Pago:\s*(?:Efectivo|Cr[eé]dito|Transferencia|Mixto|Tarjeta)\.?$',
                  caseSensitive: false,
                ).hasMatch(line.trim()),
              )
              .map(_clean)
              .where((line) => line.isNotEmpty)
              .join('\n')
        : _clean(raw);
    final method = _clean(
      receipt.paymentMethod ?? '',
    ).replaceAll(RegExp(r'\s+RD\$\s*[\d,.]+', caseSensitive: false), '');
    final paymentLabel = receipt.credit != null
        ? 'Crédito'
        : switch (method.toLowerCase()) {
            'cash' || 'efectivo' => 'Efectivo',
            'transfer' || 'transferencia' => 'Transferencia',
            'card' || 'tarjeta' => 'Tarjeta',
            'credit' || 'credito' || 'crédito' => 'Crédito',
            'mixed' || 'mixto' => 'Mixto',
            _ => method.contains('+') ? 'Mixto' : method,
          };
    final note = _wideRoll
        ? [
            if (customerNote.isNotEmpty) customerNote,
            if (paymentLabel.isNotEmpty) 'Pago: $paymentLabel',
          ].join('\n')
        : customerNote;
    if (note.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _rule(dashed: true),
        pw.Text('NOTA', style: _style(8, bold: true)),
        pw.Text(note, maxLines: null, style: _style(8)),
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
      padding: pw.EdgeInsets.symmetric(
        vertical: 2,
        horizontal: _wideRoll ? 0.5 : 1.4,
      ),
      child: _wideRoll
          ? _singleLine(text, size: 7.5, bold: true, align: align)
          : pw.Text(
              text,
              textAlign: align,
              style: _style(paperWidthMm == 58 ? 5.5 : 7.0, bold: true),
            ),
    );
  }

  pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    double fontSize = 8,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.4),
      child: _wideRoll
          ? _singleLine(text, size: fontSize, align: align)
          : pw.Text(text, textAlign: align, style: _style(fontSize)),
    );
  }

  pw.Widget _totalRow(
    String label,
    String amount, {
    bool grand = false,
    bool bold = false,
  }) {
    final strong = grand || bold;
    if (_wideRoll) {
      final size = grand ? 10.5 : 9.0;
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: grand ? 1.2 : 0.6),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: _singleLine(
                label,
                size: size,
                bold: strong,
                align: pw.TextAlign.right,
                total: true,
              ),
            ),
            pw.SizedBox(width: 2 * PdfPageFormat.mm),
            pw.SizedBox(
              width: 21 * PdfPageFormat.mm,
              child: _singleLine(
                amount,
                size: size,
                bold: strong,
                align: pw.TextAlign.right,
                total: true,
              ),
            ),
          ],
        ),
      );
    }
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
            flex: _wideRoll ? 60 : 1,
            child: _wideRoll
                ? _singleLine(label, size: grand ? 11 : 9, bold: strong)
                : pw.Text(label, style: _style(grand ? 11 : 8.5, bold: strong)),
          ),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          if (_wideRoll)
            pw.Expanded(
              flex: 40,
              child: _singleLine(
                amount,
                size: grand ? 11 : 9,
                bold: strong,
                align: pw.TextAlign.right,
              ),
            )
          else
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
      text: pw.TextSpan(
        style: _style(9),
        children: [
          pw.TextSpan(text: '$label ', style: _style(9, bold: true)),
          pw.TextSpan(text: value),
        ],
      ),
    );
  }

  // 80mm: one regular 9pt face throughout; medium weight only for totals.
  // Keep the existing 58mm typography independent of this template.
  pw.TextStyle _style(double size, {bool bold = false, bool total = false}) {
    return pw.TextStyle(
      font: _wideRoll
          ? null
          : bold
          ? pw.Font.helveticaBold()
          : pw.Font.helvetica(),
      fontWeight: bold && (!_wideRoll || total)
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
      fontSize: _wideRoll ? 9 : size,
      height: 1.1,
    );
  }

  pw.Widget _singleLine(
    String text, {
    required double size,
    bool bold = false,
    bool total = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.SizedBox(
    height: (_wideRoll ? 9 : size) * 1.25,
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : align == pw.TextAlign.center
          ? pw.Alignment.center
          : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: _style(size, bold: bold, total: total),
        softWrap: false,
        maxLines: 1,
      ),
    ),
  );

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _money(double value) => ReceiptTextUtils.money(value);

  String _amount(double value) => _amountFormat.format(value);

  static final _amountFormat = NumberFormat('#,##0.00', 'en_US');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _time = DateFormat('h:mm a');
}
