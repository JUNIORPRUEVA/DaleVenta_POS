import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../features/settings/data/mobile_printer_settings_repository.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import '../../modules/ventas/sales_models.dart';
import '../update/print_activity_tracker.dart';
import 'esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'esc_pos/thermal_receipt_view_model.dart';
import 'html/html_thermal_receipt_pdf_renderer.dart';
import 'mobile_print_service.dart';
import 'models/models.dart';
import 'printing_platform_resolver.dart';
import 'thermal_printer_service.dart';
import 'windows_raw_printer_transport.dart';

typedef HtmlToPdfConverter =
    Future<Uint8List> Function(
      ThermalReceiptViewModel receipt,
      double paperWidthMm,
      String warrantyPolicy,
    );

final unifiedTicketPrinterProvider = Provider<UnifiedTicketPrinter>((ref) {
  return UnifiedTicketPrinter(ref);
});

class PrintTicketResult {
  const PrintTicketResult({
    required this.success,
    required this.message,
    this.ticketNumber,
    this.skipped = false,
  });

  final bool success;
  final String message;
  final String? ticketNumber;
  final bool skipped;
}

class TicketPreviewConfig {
  const TicketPreviewConfig({
    required this.text,
    required this.paperWidthMm,
    required this.charsPerLine,
  });

  final String text;
  final int paperWidthMm;
  final int charsPerLine;
}

class UnifiedTicketPrinter {
  UnifiedTicketPrinter(
    this._ref, {
    ThermalPrinterService? thermalPrinterService,
    RawPrinterTransport? windowsRawPrinterTransport,
    bool? useEscPosReceiptRenderer,
    HtmlToPdfConverter? htmlToPdfConverter,
  }) : _thermal = thermalPrinterService ?? ThermalPrinterService(),
       _windowsRaw = windowsRawPrinterTransport ?? WindowsRawPrinterTransport(),
       _htmlToPdfConverter =
           htmlToPdfConverter ?? UnifiedTicketPrinter._convertHtmlToPdf,
       _useEscPosReceiptRenderer =
           useEscPosReceiptRenderer ?? _defaultUseEscPosReceiptRenderer;

  static const bool _defaultUseEscPosReceiptRenderer = bool.fromEnvironment(
    'FULLPOS_ESC_POS_RECEIPT',
  );

  final Ref _ref;
  final ThermalPrinterService _thermal;
  final RawPrinterTransport _windowsRaw;
  final HtmlToPdfConverter _htmlToPdfConverter;
  final bool _useEscPosReceiptRenderer;

  static Future<Uint8List> _convertHtmlToPdf(
    ThermalReceiptViewModel receipt,
    double paperWidthMm,
    String warrantyPolicy,
  ) {
    return HtmlThermalReceiptPdfRenderer(
      paperWidthMm: paperWidthMm,
      warrantyPolicy: warrantyPolicy,
    ).render(receipt);
  }

  Future<PrintTicketResult> printTicket(
    TicketData data, {
    int? overrideCopies,
    bool showSystemDialogIfNoPrinter = true,
  }) async {
    final tracker = PrintActivityTracker.instance;
    tracker.markPrintStarted();
    try {
      debugPrint('[PRINT] entering UnifiedTicketPrinter.printTicket');
      debugPrint(
        '[PRINT] FULLPOS_ESC_POS_RECEIPT = $_useEscPosReceiptRenderer',
      );
      debugPrint('[PRINT] ticketType = ${data.type.name}');
      final company = await _ref
          .read(companyInfoRepositoryProvider)
          .getCurrentCompanyInfo();
      final settings = await _ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      final platform = _ref.read(printingPlatformResolverProvider);
      debugPrint('[PRINT] platform = ${platform.platform.name}');
      final escPosEligible = _supportsEscPosReceipt(data);
      debugPrint('[PRINT] ESC_POS eligible = $escPosEligible');
      final htmlEligible = _supportsHtmlReceipt(data);
      debugPrint('[PRINT] HTML receipt eligible = $htmlEligible');
      if (platform.platform == PrintingPlatform.windows && htmlEligible) {
        return _printWindowsHtmlReceipt(
          data: data,
          company: company,
          settings: settings,
          overrideCopies: overrideCopies,
        );
      }
      final useEscPosForData = _useEscPosReceiptRenderer && escPosEligible;
      if (platform.platform == PrintingPlatform.windows && useEscPosForData) {
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: data,
          company: company,
        );
        final renderer = FullPosEscPosReceiptRenderer(
          cutPaper: settings.autoCut,
          warrantyPolicy: settings.warrantyPolicy,
        );
        final bytes = await renderer.render(receipt);
        return _printWindowsRawEscPos(
          bytes: bytes,
          printerName: settings.selectedPrinterName,
          documentName: 'Ticket ${data.ticketNumber}',
          copies: overrideCopies ?? settings.copies,
          ticketNumber: data.ticketNumber,
        );
      }

      final layout = TicketLayoutConfig.fromPrinterSettings(settings);
      final builder = TicketBuilder(layout: layout, company: company);
      debugPrint('[PRINT] entering TicketBuilder.buildPdf');
      final pdf = await builder.buildPdf(data);
      debugPrint('[PRINT] renderer = LEGACY_PDF');
      debugPrint('[PRINT] pdf bytes generated = ${pdf.length}');
      final escPosReceipt = useEscPosForData
          ? ThermalReceiptViewModel.fromTicketData(data: data, company: company)
          : null;
      final escPosRenderer = useEscPosForData
          ? FullPosEscPosReceiptRenderer(
              cutPaper: settings.autoCut,
              warrantyPolicy: settings.warrantyPolicy,
            )
          : null;
      final escPosBytes = escPosReceipt == null || escPosRenderer == null
          ? null
          : await escPosRenderer.render(escPosReceipt);
      final escPosLines = escPosReceipt == null || escPosRenderer == null
          ? null
          : escPosRenderer.previewLines(escPosReceipt);
      if (escPosBytes == null) {
        debugPrint('[PRINT] renderer ESC_POS = skipped');
      } else {
        debugPrint('[PRINT] renderer ESC_POS = executed');
        debugPrint('[PRINT] escpos bytes generated = ${escPosBytes.length}');
        debugPrint(
          '[PRINT] ESC_POS table = CANT(${FullPosEscPosReceiptRenderer.qtyChars}) '
          'ITEM(${FullPosEscPosReceiptRenderer.itemChars}) '
          'PRECIO(${FullPosEscPosReceiptRenderer.priceChars}) '
          'TOTAL(${FullPosEscPosReceiptRenderer.totalChars})',
        );
      }
      if (platform.capabilities.isMobile) {
        debugPrint(
          '[PRINT] transport = mobile ${escPosBytes == null ? 'legacy raw lines' : 'RAW ESC/POS bytes'}',
        );
        final mobileResult = await _ref
            .read(mobilePrintServiceProvider)
            .printRaw(
              lines: escPosLines ?? builder.buildLines(data),
              pdfBytes: pdf,
              rawBytes: escPosBytes,
              documentName: 'Ticket ${data.ticketNumber}',
              logoBytes: escPosBytes == null ? company.logoBytes : null,
              printLogo: escPosBytes == null && layout.showLogo,
            );
        if (mobileResult.success) {
          return PrintTicketResult(
            success: true,
            message: mobileResult.message,
            ticketNumber: data.ticketNumber,
          );
        }
        // Sin impresora térmica disponible: abrir el diálogo del sistema
        // como respaldo para que el ticket salga de inmediato en móvil.
        if (showSystemDialogIfNoPrinter) {
          await Printing.layoutPdf(
            name: 'Ticket ${data.ticketNumber}',
            format: _thermal.getPageFormat(settings),
            dynamicLayout: false,
            onLayout: (_) async => pdf,
          );
          return PrintTicketResult(
            success: true,
            message:
                '${mobileResult.message} Se abrio el dialogo del sistema como respaldo.',
            ticketNumber: data.ticketNumber,
          );
        }
        return PrintTicketResult(
          success: false,
          message: mobileResult.message,
          ticketNumber: data.ticketNumber,
        );
      }

      debugPrint(
        '[PRINT] transport = Windows Printing.directPrintPdf via PDF spooler',
      );
      if (escPosBytes != null) {
        debugPrint(
          '[PRINT] Windows note = ESC_POS was generated but is NOT sent by current Windows transport',
        );
      }
      final result = await _thermal.printDocument(
        bytes: pdf,
        settings: settings,
        copies: overrideCopies,
        documentName: 'Ticket ${data.ticketNumber}',
      );
      if (result.success) {
        return PrintTicketResult(
          success: true,
          message: result.message,
          ticketNumber: data.ticketNumber,
        );
      }

      if (showSystemDialogIfNoPrinter) {
        await Printing.layoutPdf(
          name: 'Ticket ${data.ticketNumber}',
          format: _thermal.getPageFormat(settings),
          dynamicLayout: false,
          onLayout: (_) async => pdf,
        );
        return PrintTicketResult(
          success: true,
          message:
              '${result.message} Se abrio el dialogo del sistema como respaldo.',
          ticketNumber: data.ticketNumber,
        );
      }
      return PrintTicketResult(
        success: false,
        message: result.message,
        ticketNumber: data.ticketNumber,
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'No se pudo imprimir: $e',
        ticketNumber: data.ticketNumber,
      );
    } finally {
      tracker.markPrintCompleted();
    }
  }

  Future<PrintTicketResult> _printWindowsRawEscPos({
    required Uint8List bytes,
    required String? printerName,
    required String documentName,
    required int copies,
    required String ticketNumber,
  }) async {
    final normalizedPrinter = (printerName ?? '').trim();
    debugPrint('[PRINT] renderer = FullPosEscPosReceiptRenderer');
    debugPrint('[PRINT] transport = Windows RAW ESC/POS');
    debugPrint('[PRINT] printer = $normalizedPrinter');
    debugPrint('[PRINT] bytes = ${bytes.length}');
    debugPrint('[PRINT] datatype = ${WindowsRawPrinterTransport.datatype}');
    debugPrint(
      '[PRINT] ESC_POS table = CANT(${FullPosEscPosReceiptRenderer.qtyChars}) '
      'ITEM(${FullPosEscPosReceiptRenderer.itemChars}) '
      'PRECIO(${FullPosEscPosReceiptRenderer.priceChars}) '
      'TOTAL(${FullPosEscPosReceiptRenderer.totalChars}) '
      'SAFE_RIGHT(${FullPosEscPosReceiptRenderer.safeRightChars})',
    );
    try {
      final result = await _windowsRaw.printRaw(
        printerName: normalizedPrinter,
        bytes: bytes,
        documentName: documentName,
        copies: copies,
      );
      debugPrint('[PRINT] result = SUCCESS');
      return PrintTicketResult(
        success: true,
        message: result.message,
        ticketNumber: ticketNumber,
      );
    } catch (e) {
      debugPrint('[PRINT] RAW ERROR = $e');
      return PrintTicketResult(
        success: false,
        message: 'RAW ERROR: $e',
        ticketNumber: ticketNumber,
      );
    }
  }

  Future<PrintTicketResult> _printWindowsHtmlReceipt({
    required TicketData data,
    required CompanyInfo company,
    required PrinterSettingsModel settings,
    int? overrideCopies,
  }) async {
    final receipt = ThermalReceiptViewModel.fromTicketData(
      data: data,
      company: company,
    );
    final paperWidthMm = settings.paperWidthMm == 58 ? 58.0 : 80.0;
    debugPrint('[PRINT] renderer = HtmlThermalReceiptPdfRenderer');
    debugPrint('[PRINT] transport = Windows HTML-template PDF thermal');
    debugPrint('[PRINT] paperWidthMm = $paperWidthMm');
    final pdf = await _htmlToPdfConverter(
      receipt,
      paperWidthMm,
      settings.warrantyPolicy,
    );
    debugPrint('[PRINT] template pdf bytes generated = ${pdf.length}');
    final result = await _thermal.printDocument(
      bytes: pdf,
      settings: settings,
      copies: overrideCopies,
      documentName: 'Ticket ${data.ticketNumber}',
    );
    return PrintTicketResult(
      success: result.success,
      message: result.message,
      ticketNumber: data.ticketNumber,
    );
  }

  Future<PrintTicketResult> printWindowsRawEscPosBytes({
    required Uint8List bytes,
    required String ticketNumber,
    required String documentName,
    int? copies,
  }) async {
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    return _printWindowsRawEscPos(
      bytes: bytes,
      printerName: settings.selectedPrinterName,
      documentName: documentName,
      copies: copies ?? settings.copies,
      ticketNumber: ticketNumber,
    );
  }

  Future<PrintTicketResult> printPdfBytes({
    required Uint8List bytes,
    required String ticketNumber,
    required String documentName,
    List<String> fallbackLines = const <String>[],
    int? overrideCopies,
    bool showSystemDialogIfNoPrinter = true,
  }) async {
    final tracker = PrintActivityTracker.instance;
    tracker.markPrintStarted();
    try {
      final company = await _ref
          .read(companyInfoRepositoryProvider)
          .getCurrentCompanyInfo();
      final settings = await _ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      final layout = TicketLayoutConfig.fromPrinterSettings(settings);
      final platform = _ref.read(printingPlatformResolverProvider);
      if (platform.capabilities.isMobile) {
        final mobileResult = await _ref
            .read(mobilePrintServiceProvider)
            .printRaw(
              lines: fallbackLines,
              pdfBytes: bytes,
              documentName: documentName,
              logoBytes: company.logoBytes,
              printLogo: layout.showLogo,
            );
        if (mobileResult.success) {
          return PrintTicketResult(
            success: true,
            message: mobileResult.message,
            ticketNumber: ticketNumber,
          );
        }
        if (showSystemDialogIfNoPrinter) {
          await Printing.layoutPdf(
            name: documentName,
            format: _thermal.getPageFormat(settings),
            dynamicLayout: false,
            onLayout: (_) async => bytes,
          );
          return PrintTicketResult(
            success: true,
            message:
                '${mobileResult.message} Se abrio el dialogo del sistema como respaldo.',
            ticketNumber: ticketNumber,
          );
        }
        return PrintTicketResult(
          success: false,
          message: mobileResult.message,
          ticketNumber: ticketNumber,
        );
      }

      final result = await _thermal.printDocument(
        bytes: bytes,
        settings: settings,
        copies: overrideCopies,
        documentName: documentName,
      );
      if (result.success) {
        return PrintTicketResult(
          success: true,
          message: result.message,
          ticketNumber: ticketNumber,
        );
      }

      if (showSystemDialogIfNoPrinter) {
        await Printing.layoutPdf(
          name: documentName,
          format: _thermal.getPageFormat(settings),
          dynamicLayout: false,
          onLayout: (_) async => bytes,
        );
        return PrintTicketResult(
          success: true,
          message:
              '${result.message} Se abrio el dialogo del sistema como respaldo.',
          ticketNumber: ticketNumber,
        );
      }
      return PrintTicketResult(
        success: false,
        message: result.message,
        ticketNumber: ticketNumber,
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'No se pudo imprimir: $e',
        ticketNumber: ticketNumber,
      );
    } finally {
      tracker.markPrintCompleted();
    }
  }

  Future<PrintTicketResult> printCustomLines({
    required List<String> lines,
    required String ticketNumber,
    bool includeLogo = true,
    int? overrideCopies,
    TicketLayoutConfig? layoutOverride,
  }) {
    return printTicket(
      TicketData.custom(lines: lines, ticketNumber: ticketNumber),
      overrideCopies: overrideCopies,
    );
  }

  Future<PrintTicketResult> printSaleTicket({
    required SaleModel sale,
    List<SaleItemModel>? items,
    int? copies,
    bool isCopy = false,
  }) {
    return printTicket(
      TicketData.fromSale(sale, items: items, isCopy: isCopy),
      overrideCopies: copies,
    );
  }

  Future<PrintTicketResult> autoPrintSale({
    required SaleModel sale,
    List<SaleItemModel>? items,
  }) async {
    final platform = _ref.read(printingPlatformResolverProvider);
    if (platform.capabilities.isMobile) {
      final mobileSettings = await _ref
          .read(mobilePrinterSettingsRepositoryProvider)
          .getOrCreate();
      if (!mobileSettings.printingEnabled ||
          !mobileSettings.autoPrintInvoices ||
          mobileSettings.askBeforePrinting) {
        return const PrintTicketResult(
          success: true,
          skipped: true,
          message: 'Auto-print desactivado',
        );
      }
      return printSaleTicket(sale: sale, items: items);
    }

    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    final hasSelectedPrinter = (settings.selectedPrinterName ?? '')
        .trim()
        .isNotEmpty;
    if (!settings.autoPrintOnPayment && !hasSelectedPrinter) {
      return const PrintTicketResult(
        success: true,
        skipped: true,
        message: 'Auto-print desactivado',
      );
    }
    return printSaleTicket(sale: sale, items: items);
  }

  Future<PrintTicketResult> reprintSale({
    required SaleModel sale,
    List<SaleItemModel>? items,
    int? copies,
  }) {
    return printSaleTicket(
      sale: sale,
      items: items,
      copies: copies,
      isCopy: true,
    );
  }

  Future<PrintTicketResult> printTestTicket() {
    return printTicket(TicketData.demo(), overrideCopies: 1);
  }

  Future<PrintTicketResult> printWindowsRawEscPosDiagnosticTicket() async {
    final tracker = PrintActivityTracker.instance;
    tracker.markPrintStarted();
    try {
      debugPrint('[PRINT] platform = Windows');
      debugPrint(
        '[PRINT] FULLPOS_ESC_POS_RECEIPT = $_useEscPosReceiptRenderer',
      );
      final settings = await _ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      final renderer = FullPosEscPosReceiptRenderer(cutPaper: settings.autoCut);
      final bytes = await renderer.renderWindowsRawDiagnostic();
      return _printWindowsRawEscPos(
        bytes: bytes,
        printerName: settings.selectedPrinterName,
        documentName: 'FULLPOS RAW TEST',
        copies: 1,
        ticketNumber: 'RAW-TEST',
      );
    } finally {
      tracker.markPrintCompleted();
    }
  }

  Future<PrintTicketResult> printWidthRulerTest() async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final lines = TicketBuilder(
      layout: layout,
      company: company,
    ).buildDebugRuler();
    return printCustomLines(lines: lines, ticketNumber: 'RULER');
  }

  Future<PrintTicketResult> openCashDrawerPulse() async {
    return printCustomLines(
      lines: const ['', ''],
      ticketNumber: 'DRAWER',
      includeLogo: false,
      overrideCopies: 1,
    );
  }

  Future<String> generatePreviewText({TicketData? data}) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final previewData = data ?? TicketData.demo();
    if (_useEscPosReceiptRenderer && _supportsEscPosReceipt(previewData)) {
      final receipt = ThermalReceiptViewModel.fromTicketData(
        data: previewData,
        company: company,
      );
      return FullPosEscPosReceiptRenderer(
        warrantyPolicy: settings.warrantyPolicy,
      ).previewLines(receipt).join('\n');
    }
    return TicketBuilder(
      layout: layout,
      company: company,
    ).buildPlainText(previewData);
  }

  Future<String> generateEscPosDiagnosticPreview({TicketData? data}) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    final receipt = ThermalReceiptViewModel.fromTicketData(
      data: data ?? TicketData.demo(),
      company: company,
    );
    return FullPosEscPosReceiptRenderer().previewLines(receipt).join('\n');
  }

  bool _supportsEscPosReceipt(TicketData data) {
    return data.type == TicketType.sale ||
        data.type == TicketType.copy ||
        data.type == TicketType.refund ||
        data.type == TicketType.credit;
  }

  bool _supportsHtmlReceipt(TicketData data) {
    return data.type == TicketType.sale ||
        data.type == TicketType.copy ||
        data.type == TicketType.refund ||
        data.type == TicketType.credit;
  }

  Future<TicketPreviewConfig> getPreviewConfig({TicketData? data}) async {
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    return TicketPreviewConfig(
      text: await generatePreviewText(data: data),
      paperWidthMm: settings.paperWidthMm,
      charsPerLine: settings.charsPerLine,
    );
  }

  Future<List<Printer>> getAvailablePrinters() {
    return _thermal.getAvailablePrinters();
  }

  Future<PrinterStatus> checkPrinterStatus() async {
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    return _thermal.checkPrinterStatus(settings);
  }
}
