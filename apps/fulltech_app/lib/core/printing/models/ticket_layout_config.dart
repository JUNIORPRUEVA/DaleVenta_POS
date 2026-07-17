import '../../../features/settings/data/printer_settings_model.dart';

class TicketLayoutConfig {
  const TicketLayoutConfig({
    required this.paperWidthMm,
    required this.charsPerLine,
    required this.fontSize,
    required this.fontFamily,
    required this.showLogo,
    required this.logoSize,
    required this.showBusinessData,
    required this.showItbis,
    required this.showCashier,
    required this.showClient,
    required this.showPaymentMethod,
    required this.showDiscounts,
    required this.showCode,
    required this.showDatetime,
    required this.showSubtotalItbisTotal,
    required this.footerMessage,
    required this.warrantyPolicy,
    required this.headerExtra,
    required this.headerBusinessName,
    required this.headerRnc,
    required this.headerAddress,
    required this.headerPhone,
    required this.fontSizeLevel,
    required this.lineSpacingLevel,
    required this.sectionSpacingLevel,
    required this.headerAlignment,
    required this.detailsAlignment,
    required this.totalsAlignment,
    required this.topMargin,
    required this.bottomMargin,
    required this.leftMargin,
    required this.rightMargin,
    required this.sectionSeparatorStyle,
  });

  final int paperWidthMm;
  final int charsPerLine;
  final String fontSize;
  final String fontFamily;
  final bool showLogo;
  final int logoSize;
  final bool showBusinessData;
  final bool showItbis;
  final bool showCashier;
  final bool showClient;
  final bool showPaymentMethod;
  final bool showDiscounts;
  final bool showCode;
  final bool showDatetime;
  final bool showSubtotalItbisTotal;
  final String footerMessage;
  final String warrantyPolicy;
  final String headerExtra;
  final String headerBusinessName;
  final String headerRnc;
  final String headerAddress;
  final String headerPhone;
  final int fontSizeLevel;
  final int lineSpacingLevel;
  final int sectionSpacingLevel;
  final String headerAlignment;
  final String detailsAlignment;
  final String totalsAlignment;
  final int topMargin;
  final int bottomMargin;
  final int leftMargin;
  final int rightMargin;
  final String sectionSeparatorStyle;

  int get printableChars =>
      (charsPerLine - leftMargin - rightMargin).clamp(24, 64);

  double get adjustedFontSize => switch (fontSize) {
    'small' => 7.2,
    'large' => 9.2,
    _ => 8.2,
  };

  String get fontFamilyName => switch (fontFamily) {
    'arial' => 'Helvetica',
    'times' => 'Times',
    _ => 'Courier',
  };

  factory TicketLayoutConfig.fromPrinterSettings(
    PrinterSettingsModel settings,
  ) {
    return TicketLayoutConfig(
      paperWidthMm: settings.paperWidthMm,
      charsPerLine: settings.charsPerLine,
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      showLogo: settings.showLogo,
      logoSize: settings.logoSize,
      showBusinessData: settings.showBusinessData,
      showItbis: settings.showItbis,
      showCashier: settings.showCashier,
      showClient: settings.showClient,
      showPaymentMethod: settings.showPaymentMethod,
      showDiscounts: settings.showDiscounts,
      showCode: settings.showCode,
      showDatetime: settings.showDatetime,
      showSubtotalItbisTotal: settings.showSubtotalItbisTotal,
      footerMessage: settings.footerMessage,
      warrantyPolicy: settings.warrantyPolicy,
      headerExtra: settings.headerExtra,
      headerBusinessName: settings.headerBusinessName,
      headerRnc: settings.headerRnc,
      headerAddress: settings.headerAddress,
      headerPhone: settings.headerPhone,
      fontSizeLevel: settings.fontSizeLevel,
      lineSpacingLevel: settings.lineSpacingLevel,
      sectionSpacingLevel: settings.sectionSpacingLevel,
      headerAlignment: settings.headerAlignment,
      detailsAlignment: settings.detailsAlignment,
      totalsAlignment: settings.totalsAlignment,
      topMargin: settings.topMargin,
      bottomMargin: settings.bottomMargin,
      leftMargin: settings.leftMargin,
      rightMargin: settings.rightMargin,
      sectionSeparatorStyle: settings.sectionSeparatorStyle,
    );
  }
}
