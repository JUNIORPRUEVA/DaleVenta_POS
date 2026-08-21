import 'dart:convert';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../models/receipt_text_utils.dart';
import 'thermal_printer_profile.dart';

/// A single styled line ready to be sent to the thermal generator.
class EscPosLine {
  const EscPosLine(
    this.text,
    this.styles, [
    this.width = EscPosLayout.fontAChars,
  ]);

  final String text;
  final PosStyles styles;
  final int width;
}

/// Shared ESC/POS layout primitives used by EVERY thermal 80 mm ticket
/// (sales receipt, shift-close, reprints, diagnostics).
///
/// This is the single place where alignment, padding, money formatting,
/// separators, the company header and the physical 80 mm profile live, so no
/// renderer keeps its own private copy of padding/alignment logic.
class EscPosLayout {
  EscPosLayout._();

  static const int fontAChars = 48;

  // ---------------------------------------------------------------------
  // Styles
  // ---------------------------------------------------------------------

  static PosStyles normalA({String codeTable = 'CP1252'}) =>
      PosStyles(codeTable: codeTable);

  static PosStyles boldA({String codeTable = 'CP1252'}) =>
      PosStyles(bold: true, codeTable: codeTable);

  static PosStyles normalB({String codeTable = 'CP1252'}) =>
      PosStyles(fontType: PosFontType.fontB, codeTable: codeTable);

  static PosStyles boldB({String codeTable = 'CP1252'}) =>
      PosStyles(bold: true, fontType: PosFontType.fontB, codeTable: codeTable);

  // ---------------------------------------------------------------------
  // Text primitives
  // ---------------------------------------------------------------------

  static String clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String fitSingleLine(String value, int width) {
    final text = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    if (text.length <= width) return text;
    if (width <= 3) return text.substring(0, width);
    return '${text.substring(0, width - 3)}...';
  }

  static String padRight(String value, int width) {
    return fitSingleLine(value, width).padRight(width);
  }

  static String padLeft(String value, int width) {
    return fitSingleLine(value, width).padLeft(width);
  }

  static String rule(ThermalPrinterProfile profile, int width) =>
      '-' * width;

  static String money(double value) => ReceiptTextUtils.money(value);

  static String amount(double value) => _amountFormat.format(value);

  static final _amountFormat = NumberFormat('#,##0.00', 'en_US');

  static String withLeftSafe(ThermalPrinterProfile profile, String value) {
    if (profile.leftSafeChars == 0) return value;
    return '${' ' * profile.leftSafeChars}$value';
  }

  /// Applies the physical left safe offset + single-line fitting. Used both
  /// when generating bytes and when producing preview lines so the preview
  /// matches exactly what is printed.
  static String layoutLine(
    ThermalPrinterProfile profile,
    String text,
    int width,
  ) {
    return withLeftSafe(profile, fitSingleLine(text, width));
  }

  // ---------------------------------------------------------------------
  // Layout blocks
  // ---------------------------------------------------------------------

  static String centerContent(ThermalPrinterProfile profile, String value) {
    final text = fitSingleLine(clean(value), profile.usableChars);
    final left = ((profile.usableChars - text.length) / 2).floor();
    return text.padLeft(text.length + left).padRight(profile.usableChars);
  }

  static String twoColumnLine(
    ThermalPrinterProfile profile,
    String left,
    String right, {
    int rightWidth = 18,
  }) {
    const gap = 2;
    final leftWidth = profile.usableChars - gap - rightWidth;
    final leftText = fitSingleLine(clean(left), leftWidth).padRight(leftWidth);
    final rightText = fitSingleLine(clean(right), rightWidth).padLeft(
      rightWidth,
    );
    return '$leftText${' ' * gap}$rightText';
  }

  static String totalLine(
    ThermalPrinterProfile profile,
    String label,
    String amount,
  ) {
    const amountWidth = 16;
    const gap = 1;
    final labelWidth = profile.totalsBlockChars - amountWidth - gap;
    final block =
        '${padRight(label.toUpperCase(), labelWidth)}${' ' * gap}${padLeft(amount, amountWidth)}';
    return block.padLeft(profile.usableChars);
  }

  static String totalSeparator(ThermalPrinterProfile profile) {
    return ('-' * profile.totalsBlockChars).padLeft(profile.usableChars);
  }

  static List<String> companyHeaderLines(
    ThermalPrinterProfile profile, {
    required String companyName,
    required String address,
    required String phone,
    required String rnc,
  }) {
    final cleanName = clean(companyName).toUpperCase();
    final lines = <String>[
      fitSingleLine(cleanName, profile.usableChars),
    ];
    for (final value in [
      address,
      if (phone.trim().isNotEmpty) 'Tel: $phone',
      if (rnc.trim().isNotEmpty) 'RNC: $rnc',
    ]) {
      final text = clean(value);
      if (text.isEmpty) continue;
      lines.add(fitSingleLine(text, profile.usableChars));
    }
    return lines;
  }

  static List<String> wrapContent(String value, int width) {
    return ReceiptTextUtils.wrap(clean(value), width);
  }

  // ---------------------------------------------------------------------
  // Byte generation
  // ---------------------------------------------------------------------

  /// Renders styled [lines] to raw ESC/POS bytes using the same generator
  /// pipeline as the sales receipt renderer (reset, global code table, text,
  /// feed, optional drawer, cut).
  static Future<Uint8List> renderLines({
    required List<EscPosLine> lines,
    ThermalPrinterProfile? profile,
    String profileName = 'default',
    String codeTable = 'CP1252',
    bool cutPaper = true,
    bool openCashDrawer = false,
  }) async {
    final p = profile ?? ThermalPrinterProfile.mm80();
    final capability = await CapabilityProfile.load(name: profileName);
    final generator = Generator(
      p.paperSize,
      capability,
      codec: latin1,
    );
    final bytes = <int>[
      ...generator.reset(),
      ...generator.setGlobalCodeTable(codeTable),
    ];
    for (final entry in lines) {
      final safeText = layoutLine(p, entry.text, entry.width);
      bytes.addAll(
        generator.text(
          safeText,
          styles: entry.styles,
          maxCharsPerLine: safeText.length,
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
}
