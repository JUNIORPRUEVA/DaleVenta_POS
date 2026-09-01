enum WindowsPrinterMode {
  automatic,
  driver,
  escPosRaw;

  static WindowsPrinterMode fromValue(String? value) {
    switch ((value ?? '').trim()) {
      case 'driver':
        return WindowsPrinterMode.driver;
      case 'escPosRaw':
        return WindowsPrinterMode.escPosRaw;
      case 'automatic':
      default:
        return WindowsPrinterMode.automatic;
    }
  }

  String get label {
    switch (this) {
      case WindowsPrinterMode.automatic:
        return 'Automatico';
      case WindowsPrinterMode.driver:
        return 'Windows driver';
      case WindowsPrinterMode.escPosRaw:
        return 'ESC/POS RAW';
    }
  }
}

class PrinterSettingsModel {
  const PrinterSettingsModel({
    this.id,
    this.selectedPrinterName,
    this.windowsPrinterMode = WindowsPrinterMode.automatic,
    this.paperWidthMm = 80,
    this.charsPerLine = 48,
    this.autoPrintOnPayment = true,
    this.autoOpenDrawerOnChargeWithoutTicket = false,
    this.copies = 1,
    this.showItbis = true,
    this.showElectronicInvoiceReference = true,
    this.showCashier = true,
    this.showClient = true,
    this.showPaymentMethod = true,
    this.showDiscounts = true,
    this.showCode = true,
    this.showDatetime = true,
    this.headerBusinessName = 'FULLPOS',
    this.headerRnc = '',
    this.headerAddress = '',
    this.headerPhone = '',
    this.headerExtra = '',
    this.footerMessage = '¡Gracias por su preferencia!',
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
    this.autoHeight = true,
    this.topMargin = 8,
    this.bottomMargin = 8,
    this.fontSizeLevel = 6,
    this.lineSpacingLevel = 6,
    this.sectionSpacingLevel = 6,
    this.sectionSeparatorStyle = 'single',
    this.headerAlignment = 'left',
    this.detailsAlignment = 'left',
    this.totalsAlignment = 'right',
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  final int? id;
  final String? selectedPrinterName;
  final WindowsPrinterMode windowsPrinterMode;
  final int paperWidthMm;
  final int charsPerLine;
  final bool autoPrintOnPayment;
  final bool autoOpenDrawerOnChargeWithoutTicket;
  final int copies;
  final bool showItbis;
  final bool showElectronicInvoiceReference;
  final bool showCashier;
  final bool showClient;
  final bool showPaymentMethod;
  final bool showDiscounts;
  final bool showCode;
  final bool showDatetime;
  final String headerBusinessName;
  final String headerRnc;
  final String headerAddress;
  final String headerPhone;
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
  final bool autoHeight;
  final int topMargin;
  final int bottomMargin;
  final int fontSizeLevel;
  final int lineSpacingLevel;
  final int sectionSpacingLevel;
  final String sectionSeparatorStyle;
  final String headerAlignment;
  final String detailsAlignment;
  final String totalsAlignment;
  final int createdAtMs;
  final int updatedAtMs;

  PrinterSettingsModel copyWith({
    int? id,
    String? selectedPrinterName,
    bool clearPrinter = false,
    WindowsPrinterMode? windowsPrinterMode,
    int? paperWidthMm,
    int? charsPerLine,
    bool? autoPrintOnPayment,
    bool? autoOpenDrawerOnChargeWithoutTicket,
    int? copies,
    bool? showItbis,
    bool? showElectronicInvoiceReference,
    bool? showCashier,
    bool? showClient,
    bool? showPaymentMethod,
    bool? showDiscounts,
    bool? showCode,
    bool? showDatetime,
    String? headerBusinessName,
    String? headerRnc,
    String? headerAddress,
    String? headerPhone,
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
    bool? autoHeight,
    int? topMargin,
    int? bottomMargin,
    int? fontSizeLevel,
    int? lineSpacingLevel,
    int? sectionSpacingLevel,
    String? sectionSeparatorStyle,
    String? headerAlignment,
    String? detailsAlignment,
    String? totalsAlignment,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return PrinterSettingsModel(
      id: id ?? this.id,
      selectedPrinterName: clearPrinter
          ? null
          : (selectedPrinterName ?? this.selectedPrinterName),
      windowsPrinterMode: windowsPrinterMode ?? this.windowsPrinterMode,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      charsPerLine: charsPerLine ?? this.charsPerLine,
      autoPrintOnPayment: autoPrintOnPayment ?? this.autoPrintOnPayment,
      autoOpenDrawerOnChargeWithoutTicket:
          autoOpenDrawerOnChargeWithoutTicket ??
          this.autoOpenDrawerOnChargeWithoutTicket,
      copies: copies ?? this.copies,
      showItbis: showItbis ?? this.showItbis,
      showElectronicInvoiceReference:
          showElectronicInvoiceReference ?? this.showElectronicInvoiceReference,
      showCashier: showCashier ?? this.showCashier,
      showClient: showClient ?? this.showClient,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showDiscounts: showDiscounts ?? this.showDiscounts,
      showCode: showCode ?? this.showCode,
      showDatetime: showDatetime ?? this.showDatetime,
      headerBusinessName: headerBusinessName ?? this.headerBusinessName,
      headerRnc: headerRnc ?? this.headerRnc,
      headerAddress: headerAddress ?? this.headerAddress,
      headerPhone: headerPhone ?? this.headerPhone,
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
      autoHeight: autoHeight ?? this.autoHeight,
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
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'selectedPrinterName': selectedPrinterName,
    'windowsPrinterMode': windowsPrinterMode.name,
    'paperWidthMm': paperWidthMm,
    'charsPerLine': charsPerLine,
    'autoPrintOnPayment': autoPrintOnPayment,
    'autoOpenDrawerOnChargeWithoutTicket': autoOpenDrawerOnChargeWithoutTicket,
    'copies': copies,
    'showItbis': showItbis,
    'showElectronicInvoiceReference': showElectronicInvoiceReference,
    'showCashier': showCashier,
    'showClient': showClient,
    'showPaymentMethod': showPaymentMethod,
    'showDiscounts': showDiscounts,
    'showCode': showCode,
    'showDatetime': showDatetime,
    'headerBusinessName': headerBusinessName,
    'headerRnc': headerRnc,
    'headerAddress': headerAddress,
    'headerPhone': headerPhone,
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
    'autoHeight': autoHeight,
    'topMargin': topMargin,
    'bottomMargin': bottomMargin,
    'fontSizeLevel': fontSizeLevel,
    'lineSpacingLevel': lineSpacingLevel,
    'sectionSpacingLevel': sectionSpacingLevel,
    'sectionSeparatorStyle': sectionSeparatorStyle,
    'headerAlignment': headerAlignment,
    'detailsAlignment': detailsAlignment,
    'totalsAlignment': totalsAlignment,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
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
      return value ?? fallback;
    }

    return PrinterSettingsModel(
      id: map['id'] is num ? (map['id'] as num).toInt() : null,
      selectedPrinterName: map['selectedPrinterName']?.toString(),
      windowsPrinterMode: WindowsPrinterMode.fromValue(
        map['windowsPrinterMode']?.toString(),
      ),
      paperWidthMm: i('paperWidthMm', 80),
      charsPerLine: i('charsPerLine', 48),
      autoPrintOnPayment: b('autoPrintOnPayment', true),
      autoOpenDrawerOnChargeWithoutTicket: b(
        'autoOpenDrawerOnChargeWithoutTicket',
        false,
      ),
      copies: i('copies', 1).clamp(0, 5),
      showItbis: b('showItbis', true),
      showElectronicInvoiceReference: b('showElectronicInvoiceReference', true),
      showCashier: b('showCashier', true),
      showClient: b('showClient', true),
      showPaymentMethod: b('showPaymentMethod', true),
      showDiscounts: b('showDiscounts', true),
      showCode: b('showCode', true),
      showDatetime: b('showDatetime', true),
      headerBusinessName: s('headerBusinessName', 'FULLPOS'),
      headerRnc: s('headerRnc', ''),
      headerAddress: s('headerAddress', ''),
      headerPhone: s('headerPhone', ''),
      headerExtra: s('headerExtra', ''),
      footerMessage: s('footerMessage', '¡Gracias por su preferencia!'),
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
      autoHeight: b('autoHeight', true),
      topMargin: i('topMargin', 8),
      bottomMargin: i('bottomMargin', 8),
      fontSizeLevel: i('fontSizeLevel', 6),
      lineSpacingLevel: i('lineSpacingLevel', 6),
      sectionSpacingLevel: i('sectionSpacingLevel', 6),
      sectionSeparatorStyle: s('sectionSeparatorStyle', 'single'),
      headerAlignment: s('headerAlignment', 'left'),
      detailsAlignment: s('detailsAlignment', 'left'),
      totalsAlignment: s('totalsAlignment', 'right'),
      createdAtMs: i('createdAtMs', 0),
      updatedAtMs: i('updatedAtMs', 0),
    );
  }
}
