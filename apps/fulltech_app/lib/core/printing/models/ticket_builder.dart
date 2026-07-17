import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_info.dart';
import 'receipt_text_utils.dart';
import 'ticket_data.dart';
import 'ticket_layout_config.dart';
import 'ticket_renderer.dart';

class TicketBuilder {
  const TicketBuilder({required this.layout, required this.company});

  final TicketLayoutConfig layout;
  final CompanyInfo company;

  static ({pw.Font regular, pw.Font bold}) _loadThermalFonts({
    bool preferSans = false,
  }) {
    pw.Font? loadFont(List<String> candidates) {
      for (final path in candidates) {
        try {
          final file = File(path);
          if (!file.existsSync()) continue;
          final bytes = file.readAsBytesSync();
          if (bytes.isEmpty) continue;
          return pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(bytes)));
        } catch (_) {
          continue;
        }
      }
      return null;
    }

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final regular = loadFont([
      'assets/fonts/RobotoMono-Regular.ttf',
      '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
      '$executableDir/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
    ]);
    final bold = loadFont([
      'assets/fonts/RobotoMono-Medium.ttf',
      '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
      '$executableDir/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
    ]);

    if (regular != null && bold != null) {
      return (regular: regular, bold: bold);
    }
    if (preferSans) {
      return (regular: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    }
    return (regular: pw.Font.courier(), bold: pw.Font.courierBold());
  }

  List<String> buildLines(TicketData data) {
    return TicketRenderer(layout: layout, company: company).buildLines(data);
  }

  String buildPlainText(TicketData data) => buildLines(data).join('\n');

  Future<Uint8List> buildPdf(TicketData data) async {
    if (data.type == TicketType.sale ||
        data.type == TicketType.copy ||
        data.type == TicketType.refund ||
        data.type == TicketType.credit) {
      return _buildStructuredSalesPdf(data);
    }
    return buildPdfFromLines(buildLines(data), includeLogo: true);
  }

  Future<Uint8List> buildPdfFromLines(
    List<String> lines, {
    bool includeLogo = true,
  }) async {
    final doc = pw.Document(author: 'FullTech', title: 'Ticket');
    final fonts = _loadThermalFonts();
    final pageWidth = layout.printableWidthMm * PdfPageFormat.mm;
    final marginLeft = layout.leftMargin.clamp(0, 4) * PdfPageFormat.mm;
    final marginRight = layout.rightMargin.clamp(0, 4) * PdfPageFormat.mm;
    final contentWidth = math.max(20.0, pageWidth - marginLeft - marginRight);
    final fontSize = _thermalFontSize(contentWidth);
    final lineHeight = fontSize * 1.22;
    final logoHeight =
        includeLogo && layout.showLogo && company.logoBytes != null ? 58 : 0;
    final contentHeight = ((lines.length + 10) * lineHeight) + logoHeight;
    final pageHeight = contentHeight
        .clamp(90 * PdfPageFormat.mm, 2000 * PdfPageFormat.mm)
        .toDouble();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.only(
          left: marginLeft,
          right: marginRight,
          top: 5,
          bottom: 8,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (includeLogo && layout.showLogo && company.logoBytes != null)
              _logo(),
            ...lines.map((line) {
              final trimmed = line.trim();
              final isRule = RegExp(r'^[-=]{6,}$').hasMatch(trimmed);
              final isTitle = _isDocumentTitle(trimmed);
              final isTotal = trimmed.startsWith('TOTAL');

              if (isTitle) {
                return _band(trimmed, fonts.bold, fontSize + 1.5);
              }
              if (isRule) {
                return pw.Container(
                  height: 0.8,
                  margin: const pw.EdgeInsets.symmetric(vertical: 2.5),
                  color: PdfColors.grey700,
                );
              }
              return pw.Padding(
                padding: pw.EdgeInsets.only(bottom: isTotal ? 3 : 1.4),
                child: pw.Text(
                  line,
                  style: pw.TextStyle(
                    font: isTotal ? fonts.bold : fonts.regular,
                    fontSize: isTotal ? fontSize + 1.2 : fontSize,
                    height: isTotal ? 1.2 : 1.06,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildStructuredSalesPdf(TicketData data) async {
    final doc = pw.Document(author: 'FullTech', title: data.ticketNumber);
    final fonts = _loadThermalFonts(preferSans: true);
    final pageWidth = layout.printableWidthMm * PdfPageFormat.mm;
    final marginLeft = layout.leftMargin.clamp(0, 4) * PdfPageFormat.mm;
    final marginRight = layout.rightMargin.clamp(0, 4) * PdfPageFormat.mm;
    final contentWidth = math.max(20.0, pageWidth - marginLeft - marginRight);
    final fontSize = _thermalFontSize(contentWidth);
    final titleSize = layout.paperWidthMm == 58 ? fontSize + 2.2 : fontSize + 3;
    final pageHeight = math.min(
      2000 * PdfPageFormat.mm,
      math.max(120 * PdfPageFormat.mm, (data.items.length * 20.0) + 360),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.only(
          left: marginLeft,
          right: marginRight,
          top: 5,
          bottom: 8,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (layout.showLogo && company.logoBytes != null) _logo(size: 44),
            _companyBlock(fonts, fontSize),
            _documentTitle(_titleFor(data), fonts, titleSize),
            _metaBlock(data, fonts, fontSize),
            _sectionRule(),
            _itemsBlock(data, fonts, fontSize),
            _sectionRule(),
            _totalsBlock(data, fonts, fontSize),
            if ((data.note ?? '').trim().isNotEmpty) ...[
              _sectionRule(),
              _wrappedText(data.note!, fonts.regular, fontSize),
            ],
            if (layout.warrantyPolicy.trim().isNotEmpty) ...[
              _sectionRule(),
              _wrappedText(layout.warrantyPolicy, fonts.regular, fontSize),
            ],
            pw.SizedBox(height: 6),
            pw.Text(
              layout.footerMessage.trim().isEmpty
                  ? 'GRACIAS POR SU PREFERENCIA'
                  : layout.footerMessage.trim().toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fonts.bold, fontSize: fontSize),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _logo({double? size}) {
    final logoSize = size ?? layout.logoSize.clamp(34, 70).toDouble();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Center(
        child: pw.Image(
          pw.MemoryImage(company.logoBytes!),
          width: logoSize,
          height: logoSize,
          fit: pw.BoxFit.contain,
        ),
      ),
    );
  }

  pw.Widget _companyBlock(
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize,
  ) {
    final rows = <String>[
      company.name.toUpperCase(),
      if (company.rnc.trim().isNotEmpty) 'RNC: ${company.rnc.trim()}',
      if (company.phone.trim().isNotEmpty) 'TEL: ${company.phone.trim()}',
      if (company.address.trim().isNotEmpty) company.address.trim(),
      if (layout.headerExtra.trim().isNotEmpty) layout.headerExtra.trim(),
    ];

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            rows.first,
            textAlign: pw.TextAlign.left,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: layout.paperWidthMm == 58 ? fontSize + 3 : fontSize + 4,
              height: 1.02,
            ),
          ),
          pw.Container(
            width: double.infinity,
            height: 1.0,
            margin: const pw.EdgeInsets.only(top: 3, bottom: 4),
            color: PdfColors.grey900,
          ),
          ...rows
              .skip(1)
              .map(
                (row) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1.2),
                  child: pw.Text(
                    row,
                    textAlign: pw.TextAlign.left,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: fontSize,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  pw.Widget _metaBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize,
  ) {
    final rows = <({String label, String value})>[
      (label: 'No.', value: data.ticketNumber),
      (label: 'Fecha', value: _dateTime(data.dateTime)),
      if ((data.cashierName ?? '').trim().isNotEmpty)
        (label: 'Cajero', value: data.cashierName!.trim()),
      if (data.client != null && data.client!.name.trim().isNotEmpty)
        (label: 'Cliente', value: data.client!.name.trim()),
      if (data.client != null && data.client!.document.trim().isNotEmpty)
        (label: 'Doc.', value: data.client!.document.trim()),
    ];
    return pw.Column(
      children: rows
          .map((row) => _pair(row.label, row.value, fonts.regular, fontSize))
          .toList(growable: false),
    );
  }

  pw.Widget _itemsBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _pair(
          layout.paperWidthMm == 58 ? 'CANT  DESCRIPCION' : 'CANT  PRODUCTO',
          'IMPORTE',
          fonts.bold,
          fontSize,
        ),
        pw.SizedBox(height: 2),
        ...data.items.expand((item) {
          final qtyPrice =
              '${ReceiptTextUtils.qty(item.qty)} x ${ReceiptTextUtils.money(item.unitPrice)}';
          return [
            pw.Text(
              item.name.trim(),
              style: pw.TextStyle(font: fonts.regular, fontSize: fontSize),
            ),
            _pair(
              qtyPrice,
              ReceiptTextUtils.money(item.total),
              fonts.regular,
              fontSize,
            ),
            if (layout.showDiscounts && item.discount > 0)
              _pair(
                'Desc.',
                '-${ReceiptTextUtils.money(item.discount)}',
                fonts.regular,
                fontSize,
              ),
            pw.SizedBox(height: 2),
          ];
        }),
      ],
    );
  }

  pw.Widget _totalsBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize,
  ) {
    return pw.Column(
      children: [
        if (layout.showSubtotalItbisTotal) ...[
          _pair(
            'Subtotal',
            ReceiptTextUtils.money(data.resolvedSubtotal),
            fonts.regular,
            fontSize,
          ),
          if (layout.showDiscounts && data.discount > 0)
            _pair(
              'Descuento',
              '-${ReceiptTextUtils.money(data.discount)}',
              fonts.regular,
              fontSize,
            ),
          if (layout.showItbis && data.itbis > 0)
            _pair(
              'ITBIS',
              ReceiptTextUtils.money(data.itbis),
              fonts.regular,
              fontSize,
            ),
        ],
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.1, color: PdfColors.grey900),
          ),
          child: _pair(
            'TOTAL',
            ReceiptTextUtils.money(data.total),
            fonts.bold,
            fontSize + 2,
          ),
        ),
        if (layout.showPaymentMethod &&
            (data.paymentMethod ?? '').trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: _pair(
              'Pago',
              data.paymentMethod!.trim(),
              fonts.regular,
              fontSize,
            ),
          ),
      ],
    );
  }

  pw.Widget _pair(String left, String right, pw.Font font, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              left,
              style: pw.TextStyle(font: font, fontSize: fontSize),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Text(
            right,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: font, fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  pw.Widget _band(String text, pw.Font font, double fontSize) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: PdfColors.grey900,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _documentTitle(
    String text,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2, bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(width: 1.2, color: PdfColors.grey900),
          bottom: pw.BorderSide(width: 1.2, color: PdfColors.grey900),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: fontSize,
              height: 1.0,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            'COMPROBANTE DE VENTA',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: math.max(6.2, fontSize - 4.2),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionRule() {
    return pw.Container(
      height: 0.8,
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      color: PdfColors.grey700,
    );
  }

  pw.Widget _wrappedText(String text, pw.Font font, double fontSize) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: ReceiptTextUtils.wrap(text, layout.printableChars)
          .map(
            (line) => pw.Text(
              line,
              style: pw.TextStyle(font: font, fontSize: fontSize),
            ),
          )
          .toList(growable: false),
    );
  }

  double _thermalFontSize(double contentWidth) {
    const charWidthFactor = 0.60;
    final fitted = contentWidth / (layout.printableChars * charWidthFactor);
    final byLevel = 7.2 + ((layout.fontSizeLevel.clamp(1, 10) - 1) * 0.32);
    final byMode = switch (layout.fontSize) {
      'small' => byLevel - 0.8,
      'large' => byLevel + 0.9,
      _ => byLevel,
    };
    return math.min(byMode, fitted * 0.98).clamp(6.0, 12.0);
  }

  String _titleFor(TicketData data) {
    return switch (data.type) {
      TicketType.refund => 'DEVOLUCION',
      TicketType.quote => 'COTIZACION',
      TicketType.credit => 'CREDITO',
      TicketType.copy => 'COPIA',
      _ => data.isCopy ? 'COPIA FACTURA' : 'FACTURA',
    };
  }

  bool _isDocumentTitle(String value) {
    return const {
      'FACTURA',
      'COPIA FACTURA',
      'COPIA',
      'DEVOLUCION',
      'COTIZACION',
      'CREDITO',
      'CORTE DE TURNO',
      'CORTE DE CAJA',
    }.contains(value);
  }

  String _dateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  List<String> buildDebugRuler() {
    final width = layout.printableChars;
    final digits = List.generate(
      width,
      (i) => ((i + 1) % 10).toString(),
    ).join();
    return [
      'ANCHO ${layout.paperWidthMm}mm / $width chars',
      digits,
      '-' * width,
    ];
  }
}
