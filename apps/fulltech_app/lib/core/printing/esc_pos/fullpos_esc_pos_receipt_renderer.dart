import 'dart:convert';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import 'thermal_receipt_view_model.dart';

abstract class ThermalReceiptRenderer {
  Future<Uint8List> render(ThermalReceiptViewModel receipt);
  List<String> previewLines(ThermalReceiptViewModel receipt);
}

class ThermalLayoutProfile {
  const ThermalLayoutProfile({
    required this.physicalChars,
    required this.contentWidth,
    required this.leftOuterPadding,
    required this.rightOuterPadding,
  }) : assert(physicalChars > 0),
       assert(contentWidth > 0),
       assert(leftOuterPadding >= 0),
       assert(rightOuterPadding >= 0),
       assert(
         leftOuterPadding + contentWidth + rightOuterPadding <= physicalChars,
       );

  factory ThermalLayoutProfile.mm80({
    int physicalChars = 64,
    int contentWidth = 56,
  }) {
    final remaining = physicalChars - contentWidth;
    final left = remaining ~/ 2;
    return ThermalLayoutProfile(
      physicalChars: physicalChars,
      contentWidth: contentWidth,
      leftOuterPadding: left,
      rightOuterPadding: remaining - left,
    );
  }

  final int physicalChars;
  final int contentWidth;
  final int leftOuterPadding;
  final int rightOuterPadding;
}

class ThermalPrinterProfile {
  const ThermalPrinterProfile({
    required this.paperSize,
    required this.paperWidthDots,
    required this.fontAChars,
    required this.layout,
    required this.qtyChars,
    required this.itemChars,
    required this.priceChars,
    required this.totalChars,
    required this.totalsBlockChars,
    this.name = '80mm-576',
  });

  factory ThermalPrinterProfile.mm80({
    int paperWidthDots = 576,
    int physicalChars = 64,
    int contentWidth = 56,
  }) {
    final layout = ThermalLayoutProfile.mm80(
      physicalChars: physicalChars,
      contentWidth: contentWidth,
    );
    return ThermalPrinterProfile(
      paperSize: PaperSize.mm80,
      paperWidthDots: paperWidthDots,
      fontAChars: 48,
      layout: layout,
      qtyChars: 4,
      itemChars: 27,
      priceChars: 10,
      totalChars: 12,
      totalsBlockChars: 36,
    );
  }

  final String name;
  final PaperSize paperSize;
  final int paperWidthDots;
  final int fontAChars;
  final ThermalLayoutProfile layout;
  final int qtyChars;
  final int itemChars;
  final int priceChars;
  final int totalChars;
  final int totalsBlockChars;

  int get physicalChars => layout.physicalChars;
  int get leftSafeChars => layout.leftOuterPadding;
  int get rightSafeChars => layout.rightOuterPadding;
  int get usableChars => layout.contentWidth;
  int get contentWidth => layout.contentWidth;
  int get printableChars => physicalChars - rightSafeChars;
  int get printableFontBChars => printableChars;
  int get usableFontAChars =>
      fontAChars -
      (leftSafeChars / 1.33).ceil() -
      (rightSafeChars / 1.33).ceil();
  int get printableFontAChars => fontAChars - (rightSafeChars / 1.33).ceil();
  int get tableLineChars => qtyChars + itemChars + priceChars + totalChars + 3;
  int get tableSlackChars => usableChars - tableLineChars;
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
    final normalB = PosStyles(
      fontType: PosFontType.fontB,
      codeTable: codeTable,
    );
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
    final normalA = PosStyles(codeTable: codeTable);
    final boldA = PosStyles(bold: true, codeTable: codeTable);
    final normalB = PosStyles(
      fontType: PosFontType.fontB,
      codeTable: codeTable,
    );
    final boldB = PosStyles(
      bold: true,
      fontType: PosFontType.fontB,
      codeTable: codeTable,
    );

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

  String _totalLine(String label, String amount) {
    const amountWidth = 16;
    const gap = 1;
    final labelWidth = thermalProfile.totalsBlockChars - amountWidth - gap;
    final block =
        '${_padRight(label.toUpperCase(), labelWidth)}${' ' * gap}${_padLeft(amount, amountWidth)}';
    return block.padLeft(thermalProfile.usableChars);
  }

  String _totalSeparator() {
    return ('-' * thermalProfile.totalsBlockChars).padLeft(
      thermalProfile.usableChars,
    );
  }

  String _paymentLine(String method, String amount) {
    return _totalLine('PAGO: ${_clean(method).toUpperCase()}', amount);
  }

  List<String> _companyHeaderLines({
    required String companyName,
    required String address,
    required String phone,
    required String rnc,
  }) {
    final cleanName = _clean(companyName).toUpperCase();
    final lines = <String>[
      _fitSingleLine(cleanName, thermalProfile.usableChars),
    ];
    for (final value in [
      address,
      if (phone.trim().isNotEmpty) 'Tel: $phone',
      if (rnc.trim().isNotEmpty) 'RNC: $rnc',
    ]) {
      final clean = _clean(value);
      if (clean.isEmpty) continue;
      lines.add(_fitSingleLine(clean, thermalProfile.usableChars));
    }
    return lines;
  }

  String _twoColumnLine(String left, String right, {int rightWidth = 18}) {
    const gap = 2;
    final leftWidth = thermalProfile.usableChars - gap - rightWidth;
    final leftText = _fitSingleLine(
      _clean(left),
      leftWidth,
    ).padRight(leftWidth);
    final rightText = _fitSingleLine(
      _clean(right),
      rightWidth,
    ).padLeft(rightWidth);
    return '$leftText${' ' * gap}$rightText';
  }

  String _centerContent(String value) {
    final clean = _fitSingleLine(_clean(value), thermalProfile.usableChars);
    final left = ((thermalProfile.usableChars - clean.length) / 2).floor();
    return clean
        .padLeft(clean.length + left)
        .padRight(thermalProfile.usableChars);
  }

  String _withLeftSafe(String value) {
    if (thermalProfile.leftSafeChars == 0) return value;
    return '${' ' * thermalProfile.leftSafeChars}$value';
  }

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

  String _fitSingleLine(String value, int width) {
    final clean = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    if (clean.length <= width) return clean;
    if (width <= 3) return clean.substring(0, width);
    return '${clean.substring(0, width - 3)}...';
  }

  String _padRight(String value, int width) {
    final clean = _fitSingleLine(value, width);
    return clean.padRight(width);
  }

  String _padLeft(String value, int width) {
    final clean = _fitSingleLine(value, width);
    return clean.padLeft(width);
  }

  String _rule(int width) => '-' * width;

  String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _money(double value) => ReceiptTextUtils.money(value);

  String _amount(double value) => _amountFormat.format(value);

  static final _amountFormat = NumberFormat('#,##0.00', 'en_US');
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
