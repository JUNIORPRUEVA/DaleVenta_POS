import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Physical thermal layout shared by every ESC/POS 80 mm ticket renderer.
///
/// Single source of truth for the printable column grid. Both the sales
/// receipt renderer ([FullPosEscPosReceiptRenderer]) and the shift-close
/// renderer ([FullPosEscPosShiftCloseRenderer]) must use exactly this
/// profile so every ticket keeps the same physical layout.
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

/// Printer-level profile (paper size, dots, column widths) for thermal
/// tickets. [mm80] is the tested production profile for sales tickets and
/// must be reused by every other thermal ticket (shift-close, reprints...).
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
