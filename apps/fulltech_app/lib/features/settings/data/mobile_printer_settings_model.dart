enum MobilePrinterConnectionType { bluetooth, network, systemPrinter, pdfOnly }

enum MobilePrinterConnectionStatus {
  notConfigured,
  searching,
  connecting,
  connected,
  disconnected,
  permissionRequired,
  unavailable,
  error,
}

class MobilePrinterSettingsModel {
  const MobilePrinterSettingsModel({
    this.companyScope = 'default',
    this.printingEnabled = true,
    this.connectionType = MobilePrinterConnectionType.bluetooth,
    this.printerName = '',
    this.bluetoothAddress = '',
    this.networkIp = '',
    this.networkPort = 9100,
    this.paperWidthMm = 80,
    this.charsPerLine = 48,
    this.encoding = 'latin1',
    this.cutPaper = true,
    this.openCashDrawer = false,
    this.printLogo = false,
    this.printBusinessInfo = true,
    this.printCustomerInfo = true,
    this.printCashierName = true,
    this.printPaymentMethod = true,
    this.printTaxDetails = true,
    this.printItemCodes = true,
    this.printDiscounts = true,
    this.printNotes = true,
    this.footerMessage = 'Gracias por su preferencia',
    this.copies = 1,
    this.autoPrintInvoices = true,
    this.autoPrintShiftClosing = true,
    this.autoPrintCashMovements = false,
    this.askBeforePrinting = false,
    this.autoReconnect = true,
    this.markReprintsAsCopy = true,
    this.timeoutSeconds = 5,
    this.lastStatus = MobilePrinterConnectionStatus.notConfigured,
    this.lastSuccessfulConnectionMs,
    this.lastError,
    this.updatedAtMs = 0,
  });

  final String companyScope;
  final bool printingEnabled;
  final MobilePrinterConnectionType connectionType;
  final String printerName;
  final String bluetoothAddress;
  final String networkIp;
  final int networkPort;
  final int paperWidthMm;
  final int charsPerLine;
  final String encoding;
  final bool cutPaper;
  final bool openCashDrawer;
  final bool printLogo;
  final bool printBusinessInfo;
  final bool printCustomerInfo;
  final bool printCashierName;
  final bool printPaymentMethod;
  final bool printTaxDetails;
  final bool printItemCodes;
  final bool printDiscounts;
  final bool printNotes;
  final String footerMessage;
  final int copies;
  final bool autoPrintInvoices;
  final bool autoPrintShiftClosing;
  final bool autoPrintCashMovements;
  final bool askBeforePrinting;
  final bool autoReconnect;
  final bool markReprintsAsCopy;
  final int timeoutSeconds;
  final MobilePrinterConnectionStatus lastStatus;
  final int? lastSuccessfulConnectionMs;
  final String? lastError;
  final int updatedAtMs;

  MobilePrinterSettingsModel copyWith({
    String? companyScope,
    bool? printingEnabled,
    MobilePrinterConnectionType? connectionType,
    String? printerName,
    String? bluetoothAddress,
    String? networkIp,
    int? networkPort,
    int? paperWidthMm,
    int? charsPerLine,
    String? encoding,
    bool? cutPaper,
    bool? openCashDrawer,
    bool? printLogo,
    bool? printBusinessInfo,
    bool? printCustomerInfo,
    bool? printCashierName,
    bool? printPaymentMethod,
    bool? printTaxDetails,
    bool? printItemCodes,
    bool? printDiscounts,
    bool? printNotes,
    String? footerMessage,
    int? copies,
    bool? autoPrintInvoices,
    bool? autoPrintShiftClosing,
    bool? autoPrintCashMovements,
    bool? askBeforePrinting,
    bool? autoReconnect,
    bool? markReprintsAsCopy,
    int? timeoutSeconds,
    MobilePrinterConnectionStatus? lastStatus,
    int? lastSuccessfulConnectionMs,
    String? lastError,
    bool clearLastError = false,
    int? updatedAtMs,
  }) {
    final width = paperWidthMm ?? this.paperWidthMm;
    return MobilePrinterSettingsModel(
      companyScope: companyScope ?? this.companyScope,
      printingEnabled: printingEnabled ?? this.printingEnabled,
      connectionType: connectionType ?? this.connectionType,
      printerName: printerName ?? this.printerName,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      networkIp: networkIp ?? this.networkIp,
      networkPort: networkPort ?? this.networkPort,
      paperWidthMm: width,
      charsPerLine: charsPerLine ?? (width == 58 ? 32 : 48),
      encoding: encoding ?? this.encoding,
      cutPaper: cutPaper ?? this.cutPaper,
      openCashDrawer: openCashDrawer ?? this.openCashDrawer,
      printLogo: printLogo ?? this.printLogo,
      printBusinessInfo: printBusinessInfo ?? this.printBusinessInfo,
      printCustomerInfo: printCustomerInfo ?? this.printCustomerInfo,
      printCashierName: printCashierName ?? this.printCashierName,
      printPaymentMethod: printPaymentMethod ?? this.printPaymentMethod,
      printTaxDetails: printTaxDetails ?? this.printTaxDetails,
      printItemCodes: printItemCodes ?? this.printItemCodes,
      printDiscounts: printDiscounts ?? this.printDiscounts,
      printNotes: printNotes ?? this.printNotes,
      footerMessage: footerMessage ?? this.footerMessage,
      copies: copies ?? this.copies,
      autoPrintInvoices: autoPrintInvoices ?? this.autoPrintInvoices,
      autoPrintShiftClosing:
          autoPrintShiftClosing ?? this.autoPrintShiftClosing,
      autoPrintCashMovements:
          autoPrintCashMovements ?? this.autoPrintCashMovements,
      askBeforePrinting: askBeforePrinting ?? this.askBeforePrinting,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      markReprintsAsCopy: markReprintsAsCopy ?? this.markReprintsAsCopy,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      lastStatus: lastStatus ?? this.lastStatus,
      lastSuccessfulConnectionMs:
          lastSuccessfulConnectionMs ?? this.lastSuccessfulConnectionMs,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toMap() => {
    'companyScope': companyScope,
    'printingEnabled': printingEnabled,
    'connectionType': connectionType.name,
    'printerName': printerName,
    'bluetoothAddress': bluetoothAddress,
    'networkIp': networkIp,
    'networkPort': networkPort,
    'paperWidthMm': paperWidthMm,
    'charsPerLine': charsPerLine,
    'encoding': encoding,
    'cutPaper': cutPaper,
    'openCashDrawer': openCashDrawer,
    'printLogo': printLogo,
    'printBusinessInfo': printBusinessInfo,
    'printCustomerInfo': printCustomerInfo,
    'printCashierName': printCashierName,
    'printPaymentMethod': printPaymentMethod,
    'printTaxDetails': printTaxDetails,
    'printItemCodes': printItemCodes,
    'printDiscounts': printDiscounts,
    'printNotes': printNotes,
    'footerMessage': footerMessage,
    'copies': copies,
    'autoPrintInvoices': autoPrintInvoices,
    'autoPrintShiftClosing': autoPrintShiftClosing,
    'autoPrintCashMovements': autoPrintCashMovements,
    'askBeforePrinting': askBeforePrinting,
    'autoReconnect': autoReconnect,
    'markReprintsAsCopy': markReprintsAsCopy,
    'timeoutSeconds': timeoutSeconds,
    'lastStatus': lastStatus.name,
    'lastSuccessfulConnectionMs': lastSuccessfulConnectionMs,
    'lastError': lastError,
    'updatedAtMs': updatedAtMs,
  };

  factory MobilePrinterSettingsModel.fromMap(Map<String, dynamic> map) {
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

    final typeName = (map['connectionType'] ?? '').toString();
    final statusName = (map['lastStatus'] ?? '').toString();
    return MobilePrinterSettingsModel(
      companyScope: (map['companyScope'] ?? 'default').toString(),
      printingEnabled: b('printingEnabled', true),
      connectionType: MobilePrinterConnectionType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => MobilePrinterConnectionType.bluetooth,
      ),
      printerName: (map['printerName'] ?? '').toString(),
      bluetoothAddress: (map['bluetoothAddress'] ?? '').toString(),
      networkIp: (map['networkIp'] ?? '').toString(),
      networkPort: i('networkPort', 9100),
      paperWidthMm: i('paperWidthMm', 80),
      charsPerLine: i('charsPerLine', i('paperWidthMm', 80) == 58 ? 32 : 48),
      encoding: (map['encoding'] ?? 'latin1').toString(),
      cutPaper: b('cutPaper', true),
      openCashDrawer: b('openCashDrawer', false),
      printLogo: b('printLogo', false),
      printBusinessInfo: b('printBusinessInfo', true),
      printCustomerInfo: b('printCustomerInfo', true),
      printCashierName: b('printCashierName', true),
      printPaymentMethod: b('printPaymentMethod', true),
      printTaxDetails: b('printTaxDetails', true),
      printItemCodes: b('printItemCodes', true),
      printDiscounts: b('printDiscounts', true),
      printNotes: b('printNotes', true),
      footerMessage: (map['footerMessage'] ?? 'Gracias por su preferencia')
          .toString(),
      copies: i('copies', 1).clamp(1, 5),
      autoPrintInvoices: b('autoPrintInvoices', true),
      autoPrintShiftClosing: b('autoPrintShiftClosing', true),
      autoPrintCashMovements: b('autoPrintCashMovements', false),
      askBeforePrinting: b('askBeforePrinting', false),
      autoReconnect: b('autoReconnect', true),
      markReprintsAsCopy: b('markReprintsAsCopy', true),
      timeoutSeconds: i('timeoutSeconds', 5).clamp(2, 30),
      lastStatus: MobilePrinterConnectionStatus.values.firstWhere(
        (item) => item.name == statusName,
        orElse: () => MobilePrinterConnectionStatus.notConfigured,
      ),
      lastSuccessfulConnectionMs: map['lastSuccessfulConnectionMs'] is num
          ? (map['lastSuccessfulConnectionMs'] as num).toInt()
          : null,
      lastError: map['lastError']?.toString(),
      updatedAtMs: i('updatedAtMs', 0),
    );
  }
}
