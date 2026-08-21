import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import '../esc_pos/thermal_receipt_view_model.dart';

class HtmlThermalReceiptRenderer {
  const HtmlThermalReceiptRenderer({
    this.paperWidthMm = 80,
    this.safeMarginMm = 2.5,
    this.warrantyPolicy = '',
  });

  final double paperWidthMm;
  final double safeMarginMm;
  final String warrantyPolicy;

  String render(ThermalReceiptViewModel receipt) {
    final logo = receipt.company.logoBytes;
    final logoSrc = logo == null || logo.isEmpty
        ? null
        : 'data:image/png;base64,${base64Encode(logo)}';

    return '''
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Ticket ${_escape(receipt.ticketNumber)}</title>
  <style>
${_css()}
  </style>
</head>
<body>
  <main class="ticket">
    ${_header(receipt, logoSrc)}
    ${_invoiceMeta(receipt)}
    ${_fiscal(receipt)}
    ${_client(receipt)}
    ${_items(receipt)}
    ${_totals(receipt)}
    ${_payment(receipt)}
    ${_notes(receipt)}
    ${_warrantyPolicy()}
    <footer class="footer">
      <strong>¡GRACIAS POR SU PREFERENCIA!</strong>
      <div>FullPOS Cloud</div>
    </footer>
  </main>
</body>
</html>
''';
  }

  String _css() {
    return '''
@page {
  size: ${_num(paperWidthMm)}mm auto;
  margin: 2.2mm;
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  padding: 0;
  background: #fff;
}

body {
  color: #111;
  font-family: "Arial Narrow", Arial, sans-serif;
  font-size: 9px;
  line-height: 1.22;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}

.ticket {
  width: ${_num(paperWidthMm)}mm;
  padding: 2.2mm 8mm 3mm 0.5mm;
  margin: 0 auto;
}

.company {
  display: grid;
  grid-template-columns: 16mm 1fr;
  gap: 2mm;
  align-items: start;
  width: 100%;
  margin-bottom: 1.8mm;
}

.logo {
  width: 16mm;
  height: 16mm;
  object-fit: contain;
}

.logo-placeholder {
  display: grid;
  place-items: center;
  border: 1px solid #222;
  font-size: 8px;
  font-weight: 700;
}

.company-data {
  min-width: 0;
  flex: 1 1 auto;
  overflow: hidden;
}

.company-name {
  font-weight: 800;
  font-size: 13px;
  line-height: 1.1;
  margin-bottom: 0.6mm;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.company-line,
.client-line,
.note-line {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.rule {
  border-top: 1px dashed #999;
  margin: 1.5mm 0;
}

.invoice-meta {
  display: grid;
  grid-template-columns: 1fr 1fr;
  column-gap: 3mm;
  margin-bottom: 1.5mm;
}

.meta-block .title {
  font-weight: 800;
  font-size: 10px;
  margin-bottom: 0.4mm;
}

.meta-value {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.meta-right {
  text-align: right;
}

.client {
  margin-bottom: 1.5mm;
}

.items {
  width: 100%;
  border-collapse: collapse;
  table-layout: fixed;
  margin-top: 0;
  font-size: 8px;
}

.items col.qty {
  width: 13%;
}

.items col.item {
  width: 47%;
}

.items col.price {
  width: 18%;
}

.items col.total {
  width: 22%;
}

.items th,
.items td {
  padding: 0.55mm 0.45mm;
  vertical-align: top;
  border-bottom: 1px dotted #ccc;
}

.items th {
  border-top: 1px solid #333;
  border-bottom: 1px solid #333;
  font-size: 8px;
  font-weight: 800;
}

.items th.price,
.items th.total,
.items td.price,
.items td.total {
  text-align: right;
}

.qty-cell {
  text-align: center;
}

.item-name {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.line-discount {
  margin-top: 0.25mm;
  font-size: 7.5px;
  color: #333;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.totals {
  width: 50mm;
  max-width: 100%;
  margin: 1.8mm 0 0 auto;
  font-size: 8.5px;
}

.total-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 2mm;
  align-items: baseline;
  padding: 0.35mm 0;
}

.total-row .label {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.total-row .amount {
  text-align: right;
  white-space: nowrap;
}

.grand-total {
  border-top: 1px solid #222;
  border-bottom: 3px double #222;
  margin-top: 0.7mm;
  padding: 1mm 0 0.8mm;
  font-weight: 800;
  font-size: 11px;
}

.payment {
  width: 50mm;
  max-width: 100%;
  margin: 1.2mm 0 0 auto;
  font-weight: 700;
}

.notes {
  margin-top: 1.8mm;
}

.section-title {
  font-weight: 700;
  margin-bottom: 0.5mm;
}

.footer {
  text-align: center;
  margin-top: 2.2mm;
  font-size: 8px;
}

.footer strong {
  display: block;
  font-size: 9px;
  margin-bottom: 0.4mm;
}

@media print {
  .ticket {
    width: ${_num(paperWidthMm - 8.5)}mm;
    padding: 0;
  }
}
''';
  }

  String _header(ThermalReceiptViewModel receipt, String? logoSrc) {
    final company = receipt.company;
    final logo = logoSrc == null
        ? '<div class="logo logo-placeholder">LOGO</div>'
        : '<img class="logo" src="$logoSrc" alt="Logo">';
    return '''
    <section class="company">
      $logo
      <div class="company-data">
        <div class="company-name">${_escape(company.name)}</div>
        ${_companyLine(company.address)}
        ${_companyLine(company.phone, prefix: 'Tel: ')}
        ${_companyLine(company.rnc, prefix: 'RNC: ')}
      </div>
    </section>
    <div class="rule"></div>
''';
  }

  String _invoiceMeta(ThermalReceiptViewModel receipt) {
    return '''
    <section class="invoice-meta">
      <div class="meta-block">
        <div class="title">${_escape(receipt.documentTitle)}</div>
        <div>No.: ${_escape(receipt.ticketNumber)}</div>
        ${_optionalMeta('Cajero', receipt.cashierName)}
      </div>
      <div class="meta-block meta-right">
        <div class="title">FECHA</div>
        <div>${_date.format(receipt.dateTime)}</div>
        <div>Hora: ${_time.format(receipt.dateTime)}</div>
      </div>
    </section>
    <div class="rule"></div>
''';
  }

  String _client(ThermalReceiptViewModel receipt) {
    final client = receipt.client;
    final name = _clean(client?.name ?? 'Consumidor Final');
    final phone = _clean(client?.phone ?? '');
    final document = _clean(client?.document ?? '');
    return '''
    <section class="client">
      <div class="client-line"><strong>CLIENTE:</strong> ${_escape(name.isEmpty ? 'CONSUMIDOR FINAL' : name)}</div>
      ${phone.isEmpty ? '' : '<div class="client-line"><strong>TEL:</strong> ${_escape(phone)}</div>'}
      ${document.isEmpty ? '' : '<div class="client-line"><strong>RNC/CEDULA:</strong> ${_escape(document)}</div>'}
    </section>
''';
  }

  String _fiscal(ThermalReceiptViewModel receipt) {
    final ncf = _clean(receipt.ncf ?? '');
    final type = _clean(receipt.fiscalVoucherType ?? '');
    if (ncf.isEmpty && type.isEmpty) return '';
    final voucherLabel = _fiscalVoucherLabel(type);
    final lines = <String>[
      '<div class="client-line"><strong>COMPROBANTE:</strong> ${_escape(voucherLabel.isEmpty ? 'FISCAL' : voucherLabel)}</div>',
      if (ncf.isNotEmpty)
        '<div class="client-line"><strong>NCF:</strong> ${_escape(ncf)}</div>',
    ];
    return '''
    <section class="client">
      ${lines.join()}
    </section>
''';
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

  String _items(ThermalReceiptViewModel receipt) {
    final rows = receipt.items.map((item) {
      final discount = item.discount > 0
          ? '<div class="line-discount">Desc. -${_escape(_money(item.discount))}</div>'
          : '';
      return '''
      <tr>
        <td class="qty-cell">${_escape(item.qtyText)}</td>
        <td><div class="item-name">${_escape(item.name.toUpperCase())}</div>$discount</td>
        <td class="price">${_escape(_amount(item.unitPrice))}</td>
        <td class="total">${_escape(_amount(item.total))}</td>
      </tr>
''';
    }).join();
    return '''
    <table class="items">
      <colgroup>
        <col class="qty">
        <col class="item">
        <col class="price">
        <col class="total">
      </colgroup>
      <thead>
        <tr>
          <th>CANT</th>
          <th>ITEM</th>
          <th class="price">PRECIO</th>
          <th class="total">TOTAL</th>
        </tr>
      </thead>
      <tbody>
        $rows
      </tbody>
    </table>
''';
  }

  String _totals(ThermalReceiptViewModel receipt) {
    final rows = <String>[
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
    return '<section class="totals">${rows.join()}</section>';
  }

  String _payment(ThermalReceiptViewModel receipt) {
    final payment = _clean(receipt.paymentMethod ?? '');
    if (payment.isEmpty) return '';
    return '''
    <section class="payment">
      <div class="total-row">
        <span class="label">PAGO: ${_escape(payment.toUpperCase())}</span>
        <span class="amount">${_escape(_money(receipt.total))}</span>
      </div>
    </section>
''';
  }

  String _notes(ThermalReceiptViewModel receipt) {
    final note = _clean(receipt.note ?? '');
    if (note.isEmpty) return '';
    return '''
    <section class="notes">
      <div class="rule"></div>
      <div class="section-title">NOTA</div>
      <div class="note-line">${_escape(note)}</div>
    </section>
''';
  }

  String _warrantyPolicy() {
    final policy = _clean(warrantyPolicy);
    if (policy.isEmpty) return '';
    return '''
    <section class="notes warranty">
      <div class="section-title">POLITICA DE GARANTIA</div>
      <div class="note-line">${_escape(policy)}</div>
    </section>
''';
  }

  String _totalRow(String label, String amount, {bool grand = false}) {
    return '''
      <div class="total-row ${grand ? 'grand-total' : ''}">
        <span class="label">${_escape(label)}</span>
        <span class="amount">${_escape(amount)}</span>
      </div>
''';
  }

  String _companyLine(String value, {String prefix = ''}) {
    final clean = _clean(value);
    if (clean.isEmpty) return '';
    return '<div class="company-line">${_escape('$prefix$clean')}</div>';
  }

  String _optionalMeta(String label, String? value) {
    final clean = _clean(value ?? '');
    if (clean.isEmpty) return '';
    return '''
        <div>${_escape(label)}: ${_escape(clean)}</div>
''';
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _escape(String value) => const HtmlEscape().convert(value);

  String _money(double value) => ReceiptTextUtils.money(value);

  String _amount(double value) => _amountFormat.format(value);

  String _num(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static final _amountFormat = NumberFormat('#,##0.00', 'en_US');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _time = DateFormat('h:mm a');
}
