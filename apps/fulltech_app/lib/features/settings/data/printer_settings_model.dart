class PrinterSettingsModel {
  const PrinterSettingsModel({
    this.selectedPrinterName,
    this.paperWidthMm = 80,
    this.charsPerLine = 48,
    this.autoPrintOnPayment = false,
    this.autoOpenDrawerOnChargeWithoutTicket = false,
    this.copies = 1,
    this.showItbis = true,
    this.showCashier = true,
    this.showClient = true,
    this.showPaymentMethod = true,
    this.showDiscounts = true,
    this.showCode = true,
    this.showDatetime = true,
    this.headerExtra = '',
    this.footerMessage = 'Gracias por su compra',
    this.warrantyPolicy = '',
    this.leftMargin = 0,
    this.rightMargin = 0,
    this.autoCut = true,
    this.itbisRate = 0.18,
    this.fontFamily = 'courier',
    this.fontSize = 'normal',
    this.showLogo = true,
    this.logoSize = 70,
    this.showBusinessData = true,
    this.showSubtotalItbisTotal = true,
    this.topMargin = 8,
    this.bottomMargin = 8,
    this.fontSizeLevel = 6,
    this.lineSpacingLevel = 6,
    this.sectionSpacingLevel = 6,
    this.sectionSeparatorStyle = 'single',
    this.headerAlignment = 'center',
    this.detailsAlignment = 'left',
    this.totalsAlignment = 'right',
  });

  final String? selectedPrinterName;
  final int paperWidthMm;
  final int charsPerLine;
  final bool autoPrintOnPayment;
  final bool autoOpenDrawerOnChargeWithoutTicket;
  final int copies;
  final bool showItbis;
  final bool showCashier;
  final bool showClient;
  final bool showPaymentMethod;
  final bool showDiscounts;
  final bool showCode;
  final bool showDatetime;
  final String headerExtra;
  final String footerMessage;
  final String warrantyPolicy;
  final int leftMargin;
  final int rightMargin;
  final bool autoCut;
  final double itbisRate;
  final String fontFamily;
  final String fontSize;
  final bool showLogo;
  final int logoSize;
  final bool showBusinessData;
  final bool showSubtotalItbisTotal;
  final int topMargin;
  final int bottomMargin;
  final int fontSizeLevel;
  final int lineSpacingLevel;
  final int sectionSpacingLevel;
  final String sectionSeparatorStyle;
  final String headerAlignment;
  final String detailsAlignment;
  final String totalsAlignment;

  PrinterSettingsModel copyWith({
    String? selectedPrinterName,
    bool clearPrinter = false,
    int? paperWidthMm,
    int? charsPerLine,
    bool? autoPrintOnPayment,
    bool? autoOpenDrawerOnChargeWithoutTicket,
    int? copies,
    bool? showItbis,
    bool? showCashier,
    bool? showClient,
    bool? showPaymentMethod,
    bool? showDiscounts,
    bool? showCode,
    bool? showDatetime,
    String? headerExtra,
    String? footerMessage,
    String? warrantyPolicy,
    int? leftMargin,
    int? rightMargin,
    bool? autoCut,
    double? itbisRate,
    String? fontFamily,
    String? fontSize,
    bool? showLogo,
    int? logoSize,
    bool? showBusinessData,
    bool? showSubtotalItbisTotal,
    int? topMargin,
    int? bottomMargin,
    int? fontSizeLevel,
    int? lineSpacingLevel,
    int? sectionSpacingLevel,
    String? sectionSeparatorStyle,
    String? headerAlignment,
    String? detailsAlignment,
    String? totalsAlignment,
  }) {
    return PrinterSettingsModel(
      selectedPrinterName:
          clearPrinter ? null : (selectedPrinterName ?? this.selectedPrinterName),
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      charsPerLine: charsPerLine ?? this.charsPerLine,
      autoPrintOnPayment: autoPrintOnPayment ?? this.autoPrintOnPayment,
      autoOpenDrawerOnChargeWithoutTicket:
          autoOpenDrawerOnChargeWithoutTicket ??
              this.autoOpenDrawerOnChargeWithoutTicket,
      copies: copies ?? this.copies,
      showItbis: showItbis ?? this.showItbis,
      showCashier: showCashier ?? this.showCashier,
      showClient: showClient ?? this.showClient,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showDiscounts: showDiscounts ?? this.showDiscounts,
      showCode: showCode ?? this.showCode,
      showDatetime: showDatetime ?? this.showDatetime,
      headerExtra: headerExtra ?? this.headerExtra,
      footerMessage: footerMessage ?? this.footerMessage,
      warrantyPolicy: warrantyPolicy ?? this.warrantyPolicy,
      leftMargin: leftMargin ?? this.leftMargin,
      rightMargin: rightMargin ?? this.rightMargin,
      autoCut: autoCut ?? this.autoCut,
      itbisRate: itbisRate ?? this.itbisRate,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      showLogo: showLogo ?? this.showLogo,
      logoSize: logoSize ?? this.logoSize,
      showBusinessData: showBusinessData ?? this.showBusinessData,
      showSubtotalItbisTotal:
          showSubtotalItbisTotal ?? this.showSubtotalItbisTotal,
      topMargin: topMargin ?? this.topMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      lineSpacingLevel: lineSpacingLevel ?? this.lineSpacingLevel,
      sectionSpacingLevel: sectionSpacingLevel ?? this.sectionSpacingLevel,
      sectionSeparatorStyle:
          sectionSeparatorStyle ?? this.sectionSeparatorStyle,
      headerAlignment: headerAlignment ?? this.headerAlignment,
      detailsAlignment: detailsAlignment ?? this.detailsAlignment,
      totalsAlignment: totalsAlignment ?? this.totalsAlignment,
    );
  }

  Map<String, dynamic> toMap() => {
        'selectedPrinterName': selectedPrinterName,
        'paperWidthMm': paperWidthMm,
        'charsPerLine': charsPerLine,
        'autoPrintOnPayment': autoPrintOnPayment,
        'autoOpenDrawerOnChargeWithoutTicket':
            autoOpenDrawerOnChargeWithoutTicket,
        'copies': copies,
        'showItbis': showItbis,
        'showCashier': showCashier,
        'showClient': showClient,
        'showPaymentMethod': showPaymentMethod,
        'showDiscounts': showDiscounts,
        'showCode': showCode,
        'showDatetime': showDatetime,
        'headerExtra': headerExtra,
        'footerMessage': footerMessage,
        'warrantyPolicy': warrantyPolicy,
        'leftMargin': leftMargin,
        'rightMargin': rightMargin,
        'autoCut': autoCut,
        'itbisRate': itbisRate,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'showLogo': showLogo,
        'logoSize': logoSize,
        'showBusinessData': showBusinessData,
        'showSubtotalItbisTotal': showSubtotalItbisTotal,
        'topMargin': topMargin,
        'bottomMargin': bottomMargin,
        'fontSizeLevel': fontSizeLevel,
        'lineSpacingLevel': lineSpacingLevel,
        'sectionSpacingLevel': sectionSpacingLevel,
        'sectionSeparatorStyle': sectionSeparatorStyle,
        'headerAlignment': headerAlignment,
        'detailsAlignment': detailsAlignment,
        'totalsAlignment': totalsAlignment,
      };

  factory PrinterSettingsModel.fromMap(Map<String, dynamic> map) {
    bool b(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value == '1' || value.toLowerCase() == 'true';
      return fallback;
    }

    int i(String key, int fallback) {
      final value = map[key];
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? fallback;
    }

    double d(String key, double fallback) {
      final value = map[key];
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? fallback;
    }

    String s(String key, String fallback) {
      final value = map[key]?.toString();
      return value == null ? fallback : value;
    }

    return PrinterSettingsModel(
      selectedPrinterName: map['selectedPrinterName']?.toString(),
      paperWidthMm: i('paperWidthMm', 80),
      charsPerLine: i('charsPerLine', 48),
      autoPrintOnPayment: b('autoPrintOnPayment', false),
      autoOpenDrawerOnChargeWithoutTicket:
          b('autoOpenDrawerOnChargeWithoutTicket', false),
      copies: i('copies', 1).clamp(1, 5),
      showItbis: b('showItbis', true),
      showCashier: b('showCashier', true),
      showClient: b('showClient', true),
      showPaymentMethod: b('showPaymentMethod', true),
      showDiscounts: b('showDiscounts', true),
      showCode: b('showCode', true),
      showDatetime: b('showDatetime', true),
      headerExtra: s('headerExtra', ''),
      footerMessage: s('footerMessage', 'Gracias por su compra'),
      warrantyPolicy: s('warrantyPolicy', ''),
      leftMargin: i('leftMargin', 0),
      rightMargin: i('rightMargin', 0),
      autoCut: b('autoCut', true),
      itbisRate: d('itbisRate', 0.18),
      fontFamily: s('fontFamily', 'courier'),
      fontSize: s('fontSize', 'normal'),
      showLogo: b('showLogo', true),
      logoSize: i('logoSize', 70),
      showBusinessData: b('showBusinessData', true),
      showSubtotalItbisTotal: b('showSubtotalItbisTotal', true),
      topMargin: i('topMargin', 8),
      bottomMargin: i('bottomMargin', 8),
      fontSizeLevel: i('fontSizeLevel', 6),
      lineSpacingLevel: i('lineSpacingLevel', 6),
      sectionSpacingLevel: i('sectionSpacingLevel', 6),
      sectionSeparatorStyle: s('sectionSeparatorStyle', 'single'),
      headerAlignment: s('headerAlignment', 'center'),
      detailsAlignment: s('detailsAlignment', 'left'),
      totalsAlignment: s('totalsAlignment', 'right'),
    );
  }
}
