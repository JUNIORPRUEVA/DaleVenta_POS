import 'dart:convert';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import 'esc_pos_layout.dart';
import 'thermal_printer_profile.dart';
import 'thermal_receipt_view_model.dart';

export 'thermal_printer_profile.dart';

abstract class ThermalReceiptRenderer {
  Future<Uint8List> render(ThermalReceiptViewModel receipt);
  List<String> previewLines(ThermalReceiptViewModel receipt);
}

class FullPosEscPosReceiptRenderer implements ThermalReceiptRenderer {
  FullPosEscPosReceiptRenderer({
    ThermalPrinterProfile? profile,
    this.profileName = 'default',
    this.codeTable = 'CP1252',
    this.cutPaper = true,
    this.openCashDrawer = false,
    this.warrantyPolicy = '',
  }) : thermalProfile = profile ?? ThermalPrinterProfile.mm80();

  static final ThermalPrinterProfile defaultProfile =
      ThermalPrinterProfile.mm80();
  static int get paperWidthDots => defaultProfile.paperWidthDots;
  static const int fontAChars = 48;
  static int get fontBChars => defaultProfile.physicalChars;
  static int get usableChars => defaultProfile.usableChars;
  static int get leftSafeChars => defaultProfile.leftSafeChars;
  static int get rightSafeChars => defaultProfile.rightSafeChars;
  static int get qtyChars => defaultProfile.qtyChars;
  static int get itemChars => defaultProfile.itemChars;
  static const int priceChars = 10;
  static int get totalChars => defaultProfile.totalChars;
  static int get safeRightChars => defaultProfile.rightSafeChars;

  final ThermalPrinterProfile thermalProfile;
  final String profileName;
  final String codeTable;
  final bool cutPaper;
  final bool openCashDrawer;
  final String warrantyPolicy;

  @override
  Future<Uint8List> render(ThermalReceiptViewModel receipt) async {
    final profile = await CapabilityProfile.load(name: profileName);
    final generator = Generator(
      thermalProfile.paperSize,
      profile,
      codec: latin1,
    );
    final bytes = <int>[];

    bytes.addAll(generator.reset());
    bytes.addAll(generator.setGlobalCodeTable(codeTable));
    for (final entry in _styledLines(receipt)) {
      bytes.addAll(
        generator.text(
          entry.text,
          styles: entry.styles,
          maxCharsPerLine: entry.width,
        ),
      );
    }
    bytes.addAll(generator.feed(2));
    if (openCashDrawer) {
      bytes.addAll(generator.drawer(pin: PosDrawer.pin2));
    }
    if (cutPaper) {
      bytes.addAll(generator.cut(mode: PosCutMode.partial));
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> renderWindowsRawDiagnostic() async {
    final profile = await CapabilityProfile.load(name: profileName);
    final generator = Generator(
      thermalProfile.paperSize,
      profile,
      codec: latin1,
    );
    final bytes = <int>[];
    final normalA = PosStyles(codeTable: codeTable);
    final centerBoldA = PosStyles(
      bold: true,
      align: PosAlign.center,
      codeTable: codeTable,
    );
    final normalB = PosStyles(
      fontType: PosFontType.fontB,
      codeTable: codeTable,
    );
    final boldB = PosStyles(
      bold: true,
      fontType: PosFontType.fontB,
      codeTable: codeTable,
    );

    void text(String value, PosStyles styles, int width) {
      final safeText = _withLeftSafe(_fitSingleLine(value, width));
      bytes.addAll(
        generator.text(
          safeText,
          styles: styles,
          maxCharsPerLine: safeText.length,
        ),
      );
    }

    bytes.addAll(generator.reset());
    bytes.addAll(generator.setGlobalCodeTable(codeTable));
    text('FULLPOS CLOUD', centerBoldA, thermalProfile.usableFontAChars);
    text(
      'PRUEBA ESC/POS WINDOWS',
      centerBoldA,
      thermalProfile.usableFontAChars,
    );
    text('', normalA, thermalProfile.usableFontAChars);
    text('******** CALIBRACION ********', normalB, thermalProfile.usableChars);
    text(_calibrationDigits(), normalB, thermalProfile.usableChars);
    text(_calibrationArrow(), normalB, thermalProfile.usableChars);
    text(_calibrationRuler(), normalB, thermalProfile.usableChars);
    text(_calibrationEdges(), normalB, thermalProfile.usableChars);
    text('', normalA, thermalProfile.usableFontAChars);
    for (final line in _companyHeaderLines(
      companyName: 'FULLTECH, SRL',
      address: 'Centro Calle Beller 9 Local N2, Higüey',
      phone: '8295319442',
      rnc: '133080206',
    )) {
      text(line, normalB, thermalProfile.usableChars);
    }
    text(
      _rule(thermalProfile.usableChars),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _twoColumnLine('FACTURA', 'FECHA', rightWidth: 18),
      boldB,
      thermalProfile.usableChars,
    );
    text(
      _twoColumnLine('No.: 2755079', '20/08/2026', rightWidth: 18),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _twoColumnLine('Cajero: Yunior López', 'Hora: 8:29 PM', rightWidth: 18),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _rule(thermalProfile.usableChars),
      normalB,
      thermalProfile.usableChars,
    );
    text('CLIENTE: CONSUMIDOR FINAL', normalB, thermalProfile.usableChars);
    text('', normalA, thermalProfile.usableFontAChars);
    text(_itemHeader(), boldB, thermalProfile.usableChars);
    text(
      _rule(thermalProfile.usableChars),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _diagnosticItemLine(
        qty: '1',
        product: 'CABLE VGA JACKLIN 1.8M',
        price: '200.00',
        total: '184.41',
      ),
      normalB,
      thermalProfile.usableChars,
    );
    text('   Desc. -RD\$ 43.69', normalB, thermalProfile.usableChars);
    text(
      _diagnosticItemLine(
        qty: '1',
        product: 'CABLE UTP CAT5 EXTERIOR',
        price: '6.00',
        total: '5.53',
      ),
      normalB,
      thermalProfile.usableChars,
    );
    text('   Desc. -RD\$ 1.31', normalB, thermalProfile.usableChars);
    text(
      _diagnosticItemLine(
        qty: '9',
        product: 'AURICULARES PRO 6',
        price: '900.00',
        total: '8,100.00',
      ),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _diagnosticItemLine(
        qty: '1',
        product: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS',
        price: '2,500.00',
        total: '2,500.00',
      ),
      normalB,
      thermalProfile.usableChars,
    );
    text('', normalA, thermalProfile.usableFontAChars);
    text(
      _totalLine('SUBTOTAL', 'RD\$ 3,400.00'),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _totalLine('DESC. PRODUCTOS', '-RD\$ 45.00'),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _totalLine('MONTO GRAVADO', 'RD\$ 2,881.36'),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _totalLine('ITBIS', 'RD\$ 518.64'),
      normalB,
      thermalProfile.usableChars,
    );
    text(
      _totalLine('TOTAL', 'RD\$ 3,400.00'),
      boldB,
      thermalProfile.usableChars,
    );
    text(
      _paymentLine('EFECTIVO', 'RD\$ 3,400.00'),
      boldB,
      thermalProfile.usableChars,
    );
    text('', normalA, thermalProfile.usableFontAChars);
    text('ÁÉÍÓÚ Ñ ñ', normalA, thermalProfile.usableFontAChars);
    text(
      'CÁMARA - ESCÁNER - CÓDIGO - HIGÜEY',
      normalA,
      thermalProfile.usableFontAChars,
    );
    text('', normalA, thermalProfile.usableFontAChars);
    text(
      '¡GRACIAS POR SU PREFERENCIA!',
      centerBoldA,
      thermalProfile.usableFontAChars,
    );
    text('FullPOS Cloud', centerBoldA, thermalProfile.usableFontAChars);
    bytes.addAll(generator.feed(2));
    if (cutPaper) {
      bytes.addAll(generator.cut(mode: PosCutMode.partial));
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> renderTextLines(List<String> lines) async {
    final profile = await CapabilityProfile.load(name: profileName);
    final generator = Generator(
      thermalProfile.paperSize,
      profile,
      codec: latin1,
    );
    final normalB = EscPosLayout.normalB(codeTable: codeTable);
    final bytes = <int>[
      ...generator.reset(),
      ...generator.setGlobalCodeTable(codeTable),
    ];
    for (final line in lines) {
      final safeText = _withLeftSafe(
        _fitSingleLine(line, thermalProfile.usableChars),
      );
      bytes.addAll(
        generator.text(
          safeText,
          styles: normalB,
          maxCharsPerLine: safeText.length,
        ),
      );
    }
    bytes.addAll(generator.feed(2));
    if (cutPaper) {
      bytes.addAll(generator.cut(mode: PosCutMode.partial));
    }
    return Uint8List.fromList(bytes);
  }

  @override
  List<String> previewLines(ThermalReceiptViewModel receipt) {
    return _styledLines(receipt).map((line) => line.text).toList();
  }

  List<_EscPosLine> _styledLines(ThermalReceiptViewModel receipt) {
    final lines = <_EscPosLine>[];
    final normalA = EscPosLayout.normalA(codeTable: codeTable);
    final boldA = EscPosLayout.boldA(codeTable: codeTable);
    final normalB = EscPosLayout.normalB(codeTable: codeTable);
    final boldB = EscPosLayout.boldB(codeTable: codeTable);

    void addA(String text, {PosStyles? styles}) {
      final line = _withLeftSafe(
        _fitSingleLine(text, thermalProfile.usableFontAChars),
      );
      lines.add(_EscPosLine(line, styles ?? normalA, line.length));
    }

    void addB(String text, {PosStyles? styles}) {
      final line = _withLeftSafe(
        _fitSingleLine(text, thermalProfile.usableChars),
      );
      lines.add(_EscPosLine(line, styles ?? normalB, line.length));
    }

    for (final line in _companyHeaderLines(
      companyName: receipt.company.name,
      address: receipt.company.address,
      phone: receipt.company.phone,
      rnc: receipt.company.rnc,
    )) {
      addB(line, styles: line.contains(receipt.company.name) ? boldB : normalB);
    }

    addB(_rule(thermalProfile.usableChars), styles: normalB);
    addB(
      _twoColumnLine(receipt.documentTitle, 'FECHA', rightWidth: 18),
      styles: boldB,
    );
    addB(
      _twoColumnLine(
        'NO.: ${receipt.ticketNumber}',
        _dateFormat.format(receipt.dateTime),
        rightWidth: 18,
      ),
    );
    final cashier = _clean(receipt.cashierName ?? 'No disponible');
    addB(
      _twoColumnLine(
        'Cajero: $cashier',
        'Hora: ${_timeFormat.format(receipt.dateTime)}',
        rightWidth: 18,
      ),
    );

    addB(_rule(thermalProfile.usableChars), styles: normalB);
    _addClient(lines, receipt, normalB);
    _addFiscalHeader(lines, receipt, normalB);

    addB(_rule(thermalProfile.usableChars), styles: normalB);
    addB(_itemHeader(), styles: boldB);
    addB(_rule(thermalProfile.usableChars), styles: normalB);
    for (final item in receipt.items) {
      addB(_itemLine(item), styles: normalB);
      if (item.discount > 0) {
        addB('   Desc. -${_money(item.discount)}', styles: normalB);
      }
    }

    addB(_rule(thermalProfile.usableChars), styles: normalB);
    for (final totalLine in _summaryLines(receipt)) {
      addB(totalLine, styles: normalB);
    }
    addB(_totalSeparator(), styles: normalB);
    addB(_totalLine('TOTAL', _money(receipt.total)), styles: boldB);
    addB('=' * thermalProfile.usableChars, styles: normalB);

    final payment = _clean(receipt.paymentMethod ?? '');
    if (payment.isNotEmpty) {
      addB(
        _paymentLine(payment.toUpperCase(), _money(receipt.total)),
        styles: boldB,
      );
    }

    final note = _clean(receipt.note ?? '');
    if (note.isNotEmpty) {
      addA(_rule(thermalProfile.usableFontAChars));
      addA('NOTA', styles: boldA);
      for (final wrapped in ReceiptTextUtils.wrap(
        note,
        thermalProfile.usableFontAChars,
      )) {
        addA(wrapped);
      }
    }

    final warranty = _clean(warrantyPolicy);
    if (warranty.isNotEmpty) {
      addA(_rule(thermalProfile.usableFontAChars));
      addA('POLITICA DE GARANTIA', styles: boldA);
      for (final wrapped in ReceiptTextUtils.wrap(
        warranty,
        thermalProfile.usableFontAChars,
      )) {
        addA(wrapped);
      }
    }

    addB(_rule(thermalProfile.usableChars), styles: normalB);
    addB(_centerContent('¡GRACIAS POR SU PREFERENCIA!'), styles: boldB);
    addB(_centerContent('FullPOS Cloud'), styles: normalB);

    return lines;
  }

  void _addClient(
    List<_EscPosLine> lines,
    ThermalReceiptViewModel receipt,
    PosStyles styles,
  ) {
    final client = receipt.client;
    final name = _clean(client?.name ?? 'Consumidor Final');
    lines.add(
      _safeEscPosLine(
        'CLIENTE: ${name.toUpperCase()}',
        styles,
        thermalProfile.usableChars,
      ),
    );
    final phone = _clean(client?.phone ?? '');
    if (phone.isNotEmpty) {
      lines.add(
        _safeEscPosLine('TEL: $phone', styles, thermalProfile.usableChars),
      );
    }
    final document = _clean(client?.document ?? '');
    if (document.isNotEmpty) {
      lines.add(
        _safeEscPosLine(
          'RNC/CEDULA: $document',
          styles,
          thermalProfile.usableChars,
        ),
      );
    }
  }

  void _addFiscalHeader(
    List<_EscPosLine> lines,
    ThermalReceiptViewModel receipt,
    PosStyles styles,
  ) {
    final ncf = _clean(receipt.ncf ?? '');
    final voucherType = _clean(receipt.fiscalVoucherType ?? '');
    if (ncf.isEmpty && voucherType.isEmpty) return;
    lines.add(
      _safeEscPosLine(
        _rule(thermalProfile.usableChars),
        styles,
        thermalProfile.usableChars,
      ),
    );
    if (voucherType.isNotEmpty) {
      lines.add(
        _safeEscPosLine(
          'COMPROBANTE: $voucherType',
          styles,
          thermalProfile.usableChars,
        ),
      );
    }
    if (ncf.isNotEmpty) {
      lines.add(
        _safeEscPosLine('NCF: $ncf', styles, thermalProfile.usableChars),
      );
    }
  }

  List<String> _summaryLines(ThermalReceiptViewModel receipt) {
    final lines = <String>[_totalLine('SUBTOTAL', _money(receipt.subtotal))];
    if (receipt.productDiscount > 0) {
      lines.add(
        _totalLine('DESC. PRODUCTOS', '-${_money(receipt.productDiscount)}'),
      );
    }
    if (receipt.generalDiscount > 0) {
      lines.add(
        _totalLine('DESC. GENERAL', '-${_money(receipt.generalDiscount)}'),
      );
    }
    if (receipt.exemptAmount > 0) {
      lines.add(_totalLine('MONTO EXENTO', _money(receipt.exemptAmount)));
    }
    if (receipt.taxableBase > 0) {
      lines.add(_totalLine('MONTO GRAVADO', _money(receipt.taxableBase)));
    }
    if (receipt.taxAmount > 0) {
      lines.add(_totalLine('ITBIS', _money(receipt.taxAmount)));
    }
    return lines;
  }

  String _itemHeader() {
    return '${_padRight('CANT', thermalProfile.qtyChars)} '
        '${_padRight('ITEM', thermalProfile.itemChars)} '
        '${_padLeft('PRECIO', thermalProfile.priceChars)} '
        '${_padLeft('TOTAL', thermalProfile.totalChars)}';
  }

  String _itemLine(ThermalReceiptItemViewModel item) {
    return _diagnosticItemLine(
      qty: item.qtyText,
      product: _clean(item.name).toUpperCase(),
      price: _amount(item.unitPrice),
      total: _amount(item.total),
    );
  }

  String _diagnosticItemLine({
    required String qty,
    required String product,
    required String price,
    required String total,
  }) {
    final qtyText = _fitSingleLine(qty, thermalProfile.qtyChars);
    final priceText = _fitSingleLine(price, thermalProfile.priceChars);
    final totalText = _fitSingleLine(total, thermalProfile.totalChars);
    final productText = _fitSingleLine(
      _clean(product).toUpperCase(),
      thermalProfile.itemChars,
    );
    return '${_padLeft(qtyText, thermalProfile.qtyChars)} '
        '${_padRight(productText, thermalProfile.itemChars)} '
        '${_padLeft(priceText, thermalProfile.priceChars)} '
        '${_padLeft(totalText, thermalProfile.totalChars)}';
  }

  String _totalLine(String label, String amount) =>
      EscPosLayout.totalLine(thermalProfile, label, amount);

  String _totalSeparator() => EscPosLayout.totalSeparator(thermalProfile);

  String _paymentLine(String method, String amount) {
    return _totalLine('PAGO: ${_clean(method).toUpperCase()}', amount);
  }

  List<String> _companyHeaderLines({
    required String companyName,
    required String address,
    required String phone,
    required String rnc,
  }) {
    return EscPosLayout.companyHeaderLines(
      thermalProfile,
      companyName: companyName,
      address: address,
      phone: phone,
      rnc: rnc,
    );
  }

  String _twoColumnLine(String left, String right, {int rightWidth = 18}) {
    return EscPosLayout.twoColumnLine(
      thermalProfile,
      left,
      right,
      rightWidth: rightWidth,
    );
  }

  String _centerContent(String value) =>
      EscPosLayout.centerContent(thermalProfile, value);

  String _withLeftSafe(String value) =>
      EscPosLayout.withLeftSafe(thermalProfile, value);

  _EscPosLine _safeEscPosLine(String text, PosStyles styles, int width) {
    final line = _withLeftSafe(_fitSingleLine(text, width));
    return _EscPosLine(line, styles, line.length);
  }

  String _calibrationDigits() {
    const digits = '1234567890';
    final buffer = StringBuffer();
    while (buffer.length < thermalProfile.usableChars) {
      buffer.write(digits);
    }
    return buffer.toString().substring(0, thermalProfile.usableChars);
  }

  String _calibrationRuler() {
    const marker = '|----10---|----20---|----30---|----40---|----50---|';
    return _fitSingleLine(marker, thermalProfile.usableChars);
  }

  String _calibrationArrow() {
    if (thermalProfile.usableChars <= 4) return '<>';
    return '|<${'-' * (thermalProfile.usableChars - 4)}>|';
  }

  String _calibrationEdges() {
    if (thermalProfile.usableChars <= 2) return 'LR';
    return 'L${'.' * (thermalProfile.usableChars - 2)}R';
  }

  String _fitSingleLine(String value, int width) =>
      EscPosLayout.fitSingleLine(value, width);

  String _padRight(String value, int width) => EscPosLayout.padRight(value, width);

  String _padLeft(String value, int width) => EscPosLayout.padLeft(value, width);

  String _rule(int width) => EscPosLayout.rule(thermalProfile, width);

  String _clean(String value) => EscPosLayout.clean(value);

  String _money(double value) => EscPosLayout.money(value);

  String _amount(double value) => EscPosLayout.amount(value);

  static final _dateFormat = DateFormat('dd/MM/yyyy');
  static final _timeFormat = DateFormat('h:mm a');
}

class _EscPosLine {
  const _EscPosLine(
    this.text,
    this.styles, [
    this.width = FullPosEscPosReceiptRenderer.fontAChars,
  ]);

  final String text;
  final PosStyles styles;
  final int width;
}
