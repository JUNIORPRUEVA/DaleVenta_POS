import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_info.dart';
import 'receipt_text_utils.dart';
import 'ticket_data.dart';
import 'ticket_layout_config.dart';
import 'ticket_renderer.dart';

class TicketBuilder {
  const TicketBuilder({required this.layout, required this.company});

  static const double _thermal80WidthMm = 80;
  static const double _thermal58WidthMm = 58;
  static const double _thermalVerticalPadding = 2.0;
  static const double _thermalPageMaxHeight = 2000 * PdfPageFormat.mm;
  static const double _hairline = 0.55;

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

    final executableDir = kIsWeb
        ? ''
        : File(Platform.resolvedExecutable).parent.path;
    final regularCandidates = preferSans
        ? [
            'assets/fonts/manrope/Manrope-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/manrope/Manrope-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/manrope/Manrope-Regular.ttf',
            'assets/fonts/RobotoMono-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
          ]
        : [
            'assets/fonts/RobotoMono-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/RobotoMono-Regular.ttf',
          ];
    final boldCandidates = preferSans
        ? [
            'assets/fonts/manrope/Manrope-SemiBold.ttf',
            'assets/fonts/manrope/Manrope-Bold.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/manrope/Manrope-SemiBold.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/manrope/Manrope-Bold.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/manrope/Manrope-SemiBold.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/manrope/Manrope-Bold.ttf',
            'assets/fonts/RobotoMono-Medium.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
          ]
        : [
            'assets/fonts/RobotoMono-Medium.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/data/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
            if (executableDir.isNotEmpty)
              '$executableDir/flutter_assets/assets/fonts/RobotoMono-Medium.ttf',
          ];
    final regular = loadFont(regularCandidates);
    final bold = loadFont(boldCandidates);

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
    final fonts = _loadThermalFonts();
    final metrics = _salesMetrics();
    final pageHeight = _estimatedSalesPageHeight(data, metrics);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(metrics.pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.SizedBox(
            width: metrics.pageWidth,
            child: pw.Padding(
              padding: pw.EdgeInsets.only(
                left: metrics.leftInset,
                right: metrics.rightInset,
                top: metrics.topMargin,
                bottom: metrics.bottomMargin,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  _companyBlock(fonts, metrics),
                  _invoiceIdentityBlock(data, fonts, metrics),
                  if (layout.showClient) ...[
                    _lightRule(top: 4, bottom: 3),
                    _customerBlock(data, fonts, metrics),
                  ],
                  if (_isFiscalTicket(data)) ...[
                    _lightRule(top: 4, bottom: 3),
                    _fiscalVoucherBlock(data, fonts, metrics),
                  ],
                  _lightRule(top: 5, bottom: 4),
                  _itemsBlock(data, fonts, metrics),
                  _totalsBlock(data, fonts, metrics),
                  if ((data.note ?? '').trim().isNotEmpty) ...[
                    _lightRule(top: 5, bottom: 4),
                    _sectionLabel('NOTA', fonts.bold, metrics.sectionFontSize),
                    _wrappedText(
                      data.note!,
                      fonts.regular,
                      metrics.smallFontSize,
                    ),
                  ],
                  if (layout.warrantyPolicy.trim().isNotEmpty) ...[
                    _lightRule(top: 5, bottom: 4),
                    _sectionLabel(
                      'POLITICA DE GARANTIA',
                      fonts.bold,
                      metrics.sectionFontSize,
                    ),
                    _wrappedText(
                      layout.warrantyPolicy.trim(),
                      fonts.regular,
                      metrics.smallFontSize,
                    ),
                  ],
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _upper(
                      layout.footerMessage.trim().isEmpty
                          ? 'Gracias por preferirnos.'
                          : layout.footerMessage.trim(),
                    ),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: metrics.footerFontSize,
                      height: 1.08,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'FULLPOS CLOUD',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: metrics.footerFontSize - 0.2,
                      height: 1.05,
                    ),
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
    _ThermalSalesMetrics metrics,
  ) {
    final detailLines = <String>[
      company.address.trim(),
      if (company.phone.trim().isNotEmpty) 'TEL: ${company.phone.trim()}',
      if (company.rnc.trim().isNotEmpty) 'RNC: ${company.rnc.trim()}',
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    final hasLogo = layout.showLogo && company.logoBytes != null;
    final logoWidth = hasLogo ? metrics.contentWidth * 0.28 : 0.0;

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (hasLogo) ...[
            pw.SizedBox(
              width: logoWidth,
              child: pw.Align(
                alignment: pw.Alignment.topLeft,
                child: pw.Image(
                  pw.MemoryImage(company.logoBytes!),
                  width: metrics.logoSize,
                  height: metrics.logoSize,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
            pw.SizedBox(width: 6),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _upper(company.name),
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: metrics.companyFontSize,
                    height: 1.02,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.SizedBox(height: 1.5),
                for (final line in detailLines)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 0.6),
                    child: pw.Text(
                      _upper(line),
                      textAlign: pw.TextAlign.left,
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: metrics.headerFontSize,
                        height: 1.05,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _invoiceIdentityBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _lightRule(top: 1, bottom: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _upper(_titleFor(data)),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: metrics.invoiceTitleFontSize,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                  pw.SizedBox(height: 2),
                  _inlineLabelValue(
                    'No.',
                    _fitText(
                      data.ticketNumber,
                      metrics.metaFontSize,
                      metrics.contentWidth * 0.56,
                    ),
                    fonts,
                    metrics.metaFontSize,
                    boldValue: true,
                  ),
                  if ((data.cashierName ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    _inlineLabelValue(
                      'CAJERO',
                      _upper(data.cashierName!.trim()),
                      fonts,
                      metrics.metaFontSize,
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.SizedBox(
              width: metrics.dateColumnWidth,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _rightMeta('FECHA', _rdDate(data.dateTime), fonts, metrics),
                  _rightMeta('HORA', _rdTime12h(data.dateTime), fonts, metrics),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _customerBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    final client = data.client;
    final phone = (client?.phone ?? '').trim();
    final document = (client?.document ?? '').trim();
    final name = _cleanClientName(client?.name ?? '');
    final rows = <({String label, String value})>[
      (label: 'CLIENTE', value: _upper(name)),
      if (phone.isNotEmpty) (label: 'TEL', value: _upper(phone)),
      if (document.isNotEmpty) (label: 'RNC/CEDULA', value: _upper(document)),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          _inlineLabelValue(row.label, row.value, fonts, metrics.metaFontSize),
      ],
    );
  }

  pw.Widget _fiscalVoucherBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    final rows = <({String label, String value, bool bold})>[
      (label: '', value: _fiscalSubtitleFor(data), bold: true),
      (label: 'NCF', value: data.ncf!.trim(), bold: true),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          row.label.isEmpty
              ? pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1.5),
                  child: pw.Text(
                    _upper(row.value),
                    style: pw.TextStyle(
                      font: row.bold ? fonts.bold : fonts.regular,
                      fontSize: metrics.metaFontSize,
                      height: 1.05,
                    ),
                    maxLines: 1,
                  ),
                )
              : _inlineLabelValue(
                  row.label,
                  _upper(row.value),
                  fonts,
                  metrics.metaFontSize,
                  boldValue: row.bold,
                ),
      ],
    );
  }

  String _cleanClientName(String value) {
    final clean = value.trim();
    return clean.isEmpty ? 'CONSUMIDOR FINAL' : clean;
  }

  pw.Widget _rightMeta(
    String label,
    String value,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1),
      child: pw.RichText(
        textAlign: pw.TextAlign.right,
        text: pw.TextSpan(
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: metrics.metaFontSize,
          ),
          children: [
            pw.TextSpan(text: '${_upper(label)} '),
            pw.TextSpan(
              text: _upper(value),
              style: pw.TextStyle(font: fonts.bold),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _inlineLabelValue(
    String label,
    String value,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize, {
    bool boldValue = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.2),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: fontSize,
            height: 1.05,
          ),
          children: [
            pw.TextSpan(text: '${_upper(label)}: '),
            pw.TextSpan(
              text: _upper(value),
              style: pw.TextStyle(font: boldValue ? fonts.bold : fonts.regular),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _sectionLabel(String text, pw.Font font, double fontSize) {
    return pw.Text(
      _upper(text),
      style: pw.TextStyle(font: font, fontSize: fontSize, height: 1.0),
      maxLines: 1,
    );
  }

  pw.Widget _itemsBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    final columns = _TicketColumns.forWidth(metrics.contentWidth);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _itemHeader(columns, fonts, metrics),
        _lightRule(top: 2, bottom: 3),
        ...data.items.toList().asMap().entries.expand((entry) {
          final index = entry.key + 1;
          final item = entry.value;
          return [
            _itemRow(item, columns, fonts, metrics),
            if (layout.showDiscounts && item.discount > 0)
              _discountRow(item.discount, columns, fonts, metrics),
            if (index < data.items.length) pw.SizedBox(height: metrics.itemGap),
          ];
        }),
      ],
    );
  }

  pw.Widget _itemHeader(
    _TicketColumns columns,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    return pw.Row(
      children: [
        _cell(
          'CANT',
          columns.qty,
          fonts.bold,
          metrics.tableFontSize,
          align: pw.TextAlign.center,
        ),
        _gap(columns),
        _cell('ITEM', columns.item, fonts.bold, metrics.tableFontSize),
        _gap(columns),
        _cell(
          'PRECIO',
          columns.price,
          fonts.bold,
          metrics.tableFontSize,
          align: pw.TextAlign.right,
        ),
        _gap(columns),
        _cell(
          'TOTAL',
          columns.amount,
          fonts.bold,
          metrics.tableFontSize,
          align: pw.TextAlign.right,
        ),
      ],
    );
  }

  pw.Widget _itemRow(
    TicketItemData item,
    _TicketColumns columns,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    final qty = ReceiptTextUtils.qty(item.qty);
    final price = _fitMoney(
      _tableMoney(item.unitPrice),
      metrics.tableFontSize,
      columns.price,
    );
    final amount = _fitMoney(
      _tableMoney(item.total),
      metrics.tableFontSize,
      columns.amount,
    );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _cell(
          qty,
          columns.qty,
          fonts.regular,
          metrics.tableFontSize,
          align: pw.TextAlign.center,
        ),
        _gap(columns),
        _itemNameCell(
          item.name.trim().isEmpty ? 'PRODUCTO' : item.name.trim(),
          columns.item,
          fonts.regular,
          metrics.tableFontSize,
        ),
        _gap(columns),
        _cell(
          price,
          columns.price,
          fonts.regular,
          metrics.tableFontSize,
          align: pw.TextAlign.right,
        ),
        _gap(columns),
        _cell(
          amount,
          columns.amount,
          fonts.bold,
          metrics.tableFontSize,
          align: pw.TextAlign.right,
        ),
      ],
    );
  }

  pw.Widget _discountRow(
    double discount,
    _TicketColumns columns,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(width: columns.qty + columns.gap),
          _cell(
            'Desc. -${ReceiptTextUtils.money(discount).replaceFirst('RD\$ ', 'RD\$')}',
            columns.item +
                columns.gap +
                columns.price +
                columns.gap +
                columns.amount,
            fonts.regular,
            metrics.smallFontSize,
          ),
        ],
      ),
    );
  }

  pw.Widget _cell(
    String text,
    double width,
    pw.Font font,
    double fontSize, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.SizedBox(
      width: width,
      child: pw.Text(
        _upper(text),
        textAlign: align,
        maxLines: 1,
        softWrap: false,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: font, fontSize: fontSize, height: 1.02),
      ),
    );
  }

  pw.Widget _itemNameCell(
    String text,
    double width,
    pw.Font font,
    double fontSize,
  ) {
    final fitted = _fitText(_upper(text), fontSize, width, ellipsis: true);
    return pw.SizedBox(
      width: width,
      child: pw.Text(
        fitted,
        textAlign: pw.TextAlign.left,
        maxLines: 1,
        softWrap: false,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: font, fontSize: fontSize, height: 1.0),
      ),
    );
  }

  pw.Widget _gap(_TicketColumns columns) => pw.SizedBox(width: columns.gap);

  String _fitText(
    String text,
    double fontSize,
    double maxWidth, {
    bool ellipsis = false,
  }) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    if (_textWidth(clean, fontSize) <= maxWidth) return clean;
    var low = 0;
    var high = clean.length;
    while (low < high) {
      final mid = ((low + high + 1) / 2).floor();
      final candidate = clean.substring(0, mid).trimRight();
      if (_textWidth(candidate, fontSize) <= maxWidth) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    if (!ellipsis || low <= 3) return clean.substring(0, low).trimRight();
    var prefixLength = math.min(low, clean.length);
    while (prefixLength > 0) {
      final candidate = '${clean.substring(0, prefixLength).trimRight()}...';
      if (_textWidth(candidate, fontSize) <= maxWidth) return candidate;
      prefixLength--;
    }
    return '...';
  }

  double _textWidth(String text, double fontSize) {
    // Conservative average for the compact receipt fonts. It keeps numeric
    // columns protected without forcing product names to wrap.
    return text.runes.length * fontSize * 0.54;
  }

  String _tableMoney(double value) {
    return ReceiptTextUtils.money(
      value,
    ).replaceFirst('RD\$ ', '').replaceFirst('RD\$', '');
  }

  String _fitMoney(String value, double fontSize, double maxWidth) {
    final clean = _upper(value).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_textWidth(clean, fontSize) <= maxWidth) return clean;
    final compact = clean.replaceFirst('RD\$ ', '').replaceFirst('RD\$', '');
    if (_textWidth(compact, fontSize) <= maxWidth) return compact;
    return _fitText(compact, fontSize, maxWidth);
  }

  pw.Widget _totalsBlock(
    TicketData data,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    final rows = <({String label, String value, bool bold})>[];
    final showFiscalTotals =
        layout.showItbis &&
        (data.fiscalTaxEnabled ||
            data.taxableBase > 0 ||
            data.exemptAmount > 0 ||
            data.itbis > 0) &&
        (data.taxableBase > 0 || data.exemptAmount > 0 || data.itbis > 0);
    if (layout.showSubtotalItbisTotal) {
      rows.add((
        label: 'SUBTOTAL',
        value: ReceiptTextUtils.money(data.resolvedSubtotal),
        bold: false,
      ));
      if (layout.showDiscounts) {
        if (data.productDiscount > 0) {
          rows.add((
            label: 'DESC. PRODUCTOS',
            value: '-${ReceiptTextUtils.money(data.productDiscount)}',
            bold: false,
          ));
        }
        if (data.generalDiscount > 0) {
          rows.add((
            label: 'DESC. GENERAL',
            value: '-${ReceiptTextUtils.money(data.generalDiscount)}',
            bold: false,
          ));
        }
        if (data.productDiscount <= 0 &&
            data.generalDiscount <= 0 &&
            data.discount > 0) {
          rows.add((
            label: 'DESCUENTO',
            value: '-${ReceiptTextUtils.money(data.discount)}',
            bold: false,
          ));
        }
      }
      if (showFiscalTotals) {
        if (data.taxIncluded && data.itbis > 0) {
          rows.add((label: 'ITBIS INCLUIDO', value: '', bold: false));
        }
        if (data.exemptAmount > 0) {
          rows.add((
            label: 'MONTO EXENTO',
            value: ReceiptTextUtils.money(data.exemptAmount),
            bold: false,
          ));
        }
        if (data.taxableBase > 0) {
          rows.add((
            label: 'MONTO GRAVADO',
            value: ReceiptTextUtils.money(data.taxableBase),
            bold: false,
          ));
        }
        if (data.itbis > 0) {
          rows.add((
            label: 'ITBIS',
            value: ReceiptTextUtils.money(data.itbis),
            bold: false,
          ));
        }
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _lightRule(top: metrics.totalsTopGap, bottom: 6),
        _totalsPanel(
          rows: rows,
          total: ReceiptTextUtils.money(data.total),
          fonts: fonts,
          metrics: metrics,
        ),
        if (layout.showPaymentMethod &&
            (data.paymentMethod ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 1),
          _paymentPanel(data.paymentMethod!.trim(), fonts, metrics),
        ],
      ],
    );
  }

  pw.Widget _totalsPanel({
    required List<({String label, String value, bool bold})> rows,
    required String total,
    required ({pw.Font regular, pw.Font bold}) fonts,
    required _ThermalSalesMetrics metrics,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(right: metrics.totalsRightInset),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: metrics.totalsColumnWidth,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                _moneyRow(
                  row.label,
                  row.value,
                  fonts,
                  metrics.subtotalFontSize,
                  bold: row.bold,
                  valueWidth: metrics.totalsValueWidth,
                ),
              _moneyRow(
                'TOTAL',
                total,
                fonts,
                metrics.grandTotalFontSize,
                bold: true,
                valueWidth: metrics.totalsValueWidth,
                topGap: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _paymentPanel(
    String payment,
    ({pw.Font regular, pw.Font bold}) fonts,
    _ThermalSalesMetrics metrics,
  ) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(right: metrics.totalsRightInset),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: metrics.totalsColumnWidth,
          child: _moneyRow(
            'PAGO',
            _upper(payment),
            fonts,
            metrics.subtotalFontSize,
            valueWidth: metrics.totalsValueWidth,
          ),
        ),
      ),
    );
  }

  pw.Widget _moneyRow(
    String label,
    String value,
    ({pw.Font regular, pw.Font bold}) fonts,
    double fontSize, {
    bool bold = false,
    double? valueWidth,
    double topGap = 0,
  }) {
    final font = bold ? fonts.bold : fonts.regular;
    final amountWidth = valueWidth ?? 90;
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: topGap, bottom: bold ? 0 : 0.6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(font: font, fontSize: fontSize, height: 1.0),
              maxLines: 1,
              softWrap: false,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.SizedBox(
            width: amountWidth,
            child: pw.Text(
              _fitMoney(value, fontSize, amountWidth),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: font, fontSize: fontSize, height: 1.0),
              maxLines: 1,
              softWrap: false,
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  _ThermalSalesMetrics _salesMetrics() {
    final is58 = layout.paperWidthMm == 58;
    final pageWidthMm = is58 ? _thermal58WidthMm : _thermal80WidthMm;
    final pageWidth = pageWidthMm * PdfPageFormat.mm;
    final leftInset = (is58 ? 2.2 : 2.4) * PdfPageFormat.mm;
    final rightInset = (is58 ? 4.5 : 7.0) * PdfPageFormat.mm;
    final contentWidth = pageWidth - leftInset - rightInset;
    final baseFont = _thermalFontSize(
      contentWidth,
    ).clamp(is58 ? 7.6 : 8.2, is58 ? 8.8 : 9.4);
    return _ThermalSalesMetrics(
      pageWidth: pageWidth,
      contentWidth: contentWidth,
      leftInset: leftInset,
      rightInset: rightInset,
      topMargin: _thermalVerticalPadding,
      bottomMargin: _thermalVerticalPadding,
      logoSize: is58 ? 34 : 40,
      companyFontSize: baseFont + (is58 ? 0.8 : 1.15),
      headerFontSize: baseFont - (is58 ? 0.7 : 0.8),
      invoiceTitleFontSize: baseFont + (is58 ? 1.4 : 2.0),
      metaFontSize: baseFont,
      sectionFontSize: baseFont,
      tableFontSize: baseFont - (is58 ? 0.6 : 0.45),
      smallFontSize: baseFont - 0.45,
      subtotalFontSize: baseFont - 0.25,
      totalFontSize: baseFont,
      grandTotalFontSize: baseFont + (is58 ? 0.8 : 1.0),
      footerFontSize: baseFont - 0.1,
      itemGap: is58 ? 2 : 2.5,
      totalsTopGap: is58 ? 12 : 18,
      totalsColumnWidth: contentWidth * (is58 ? 0.82 : 0.68),
      totalsValueWidth: contentWidth * (is58 ? 0.40 : 0.34),
      totalsRightInset: is58 ? 4.0 : 7.0,
      dateColumnWidth: contentWidth * (is58 ? 0.42 : 0.38),
    );
  }

  double _warrantyOptionalHeight() {
    final text = layout.warrantyPolicy.trim();
    if (text.isEmpty) return 0;
    final lines = ReceiptTextUtils.wrap(text, layout.printableChars).length;
    return 26 + (lines * 8);
  }

  double _estimatedSalesPageHeight(
    TicketData data,
    _ThermalSalesMetrics metrics,
  ) {
    final companyDetailCount = [
      company.address,
      company.phone,
      company.rnc,
      company.email,
      company.website,
      layout.headerExtra,
    ].where((value) => value.trim().isNotEmpty).length;
    final companyLines = 1 + (companyDetailCount == 0 ? 0 : 2);
    final optionalLines =
        ((data.note ?? '').trim().isNotEmpty ? 28 : 0) +
        (_isFiscalTicket(data) ? 34 : 0) +
        (data.fiscalTaxEnabled ? 22 : 0) +
        _warrantyOptionalHeight();
    final itemRows =
        data.items.length +
        data.items
            .where((item) => layout.showDiscounts && item.discount > 0)
            .length;
    final height =
        92 +
        (layout.showLogo && company.logoBytes != null
            ? metrics.logoSize + 8
            : 0) +
        (companyLines * (metrics.headerFontSize + 2.4)) +
        (itemRows * (metrics.tableFontSize + 4.2)) +
        optionalLines +
        118;
    return math
        .max(120 * PdfPageFormat.mm, height)
        .clamp(120 * PdfPageFormat.mm, _thermalPageMaxHeight)
        .toDouble();
  }

  pw.Widget _lightRule({double top = 4, double bottom = 4}) {
    return pw.Container(
      height: _hairline,
      margin: pw.EdgeInsets.only(top: top, bottom: bottom),
      color: PdfColors.grey500,
    );
  }

  // Legacy text helper below is kept for custom/plain-text tickets.

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

  pw.Widget _wrappedText(String text, pw.Font font, double fontSize) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: ReceiptTextUtils.wrap(text, layout.printableChars)
          .map(
            (line) => pw.Text(
              _upper(line),
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

  bool _isFiscalTicket(TicketData data) {
    final voucher = (data.fiscalVoucherType ?? '').trim().toUpperCase();
    return (voucher == 'B01' || voucher == 'B02') &&
        (data.ncf ?? '').trim().isNotEmpty;
  }

  String _fiscalSubtitleFor(TicketData data) {
    final voucher = (data.fiscalVoucherType ?? '').trim().toUpperCase();
    return switch (voucher) {
      'B01' => 'B01 - CREDITO FISCAL',
      'B02' => 'B02 - CONSUMIDOR FINAL',
      _ => '',
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

  DateTime _dominicanTime(DateTime value) {
    return value.toUtc().subtract(const Duration(hours: 4));
  }

  String _rdDate(DateTime value) {
    final rd = _dominicanTime(value);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(rd.day)}/${two(rd.month)}/${rd.year}';
  }

  String _rdTime12h(DateTime value) {
    final rd = _dominicanTime(value);
    final hour12 = rd.hour == 0 ? 12 : (rd.hour > 12 ? rd.hour - 12 : rd.hour);
    final minute = rd.minute.toString().padLeft(2, '0');
    final suffix = rd.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
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

  String _upper(String value) => value.toUpperCase();
}

class _ThermalSalesMetrics {
  const _ThermalSalesMetrics({
    required this.pageWidth,
    required this.contentWidth,
    required this.leftInset,
    required this.rightInset,
    required this.topMargin,
    required this.bottomMargin,
    required this.logoSize,
    required this.companyFontSize,
    required this.headerFontSize,
    required this.invoiceTitleFontSize,
    required this.metaFontSize,
    required this.sectionFontSize,
    required this.tableFontSize,
    required this.smallFontSize,
    required this.subtotalFontSize,
    required this.totalFontSize,
    required this.grandTotalFontSize,
    required this.footerFontSize,
    required this.itemGap,
    required this.totalsTopGap,
    required this.totalsColumnWidth,
    required this.totalsValueWidth,
    required this.totalsRightInset,
    required this.dateColumnWidth,
  });

  final double pageWidth;
  final double contentWidth;
  final double leftInset;
  final double rightInset;
  final double topMargin;
  final double bottomMargin;
  final double logoSize;
  final double companyFontSize;
  final double headerFontSize;
  final double invoiceTitleFontSize;
  final double metaFontSize;
  final double sectionFontSize;
  final double tableFontSize;
  final double smallFontSize;
  final double subtotalFontSize;
  final double totalFontSize;
  final double grandTotalFontSize;
  final double footerFontSize;
  final double itemGap;
  final double totalsTopGap;
  final double totalsColumnWidth;
  final double totalsValueWidth;
  final double totalsRightInset;
  final double dateColumnWidth;
}

class _TicketColumns {
  const _TicketColumns({
    required this.qty,
    required this.item,
    required this.price,
    required this.amount,
    required this.gap,
  });

  final double qty;
  final double item;
  final double price;
  final double amount;
  final double gap;

  factory _TicketColumns.forWidth(double width) {
    final gap = width >= 190 ? 2.0 : 1.6;
    final available = width - (gap * 3);
    if (width >= 190) {
      final qty = available * 0.08;
      final price = available * 0.18;
      final amount = available * 0.22;
      return _TicketColumns(
        qty: qty,
        item: available - qty - price - amount,
        price: price,
        amount: amount,
        gap: gap,
      );
    }
    final qty = (available * 0.10).clamp(15.0, 18.0).toDouble();
    final price = (available * 0.19).clamp(28.0, 33.0).toDouble();
    final amount = (available * 0.24).clamp(35.0, 41.0).toDouble();
    final item = math.max(44.0, available - qty - price - amount);
    return _TicketColumns(
      qty: qty,
      item: item,
      price: price,
      amount: amount,
      gap: gap,
    );
  }
}
