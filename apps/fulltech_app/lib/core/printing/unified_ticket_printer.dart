import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../auth/auth_provider.dart';
import '../../features/settings/data/mobile_printer_settings_repository.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import '../../modules/ventas/sales_models.dart';
import '../update/print_activity_tracker.dart';
import 'mobile_print_service.dart';
import 'models/models.dart';
import 'printing_platform_resolver.dart';
import 'thermal_printer_service.dart';

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
  UnifiedTicketPrinter(this._ref);

  final Ref _ref;
  final ThermalPrinterService _thermal = ThermalPrinterService();

  Future<PrintTicketResult> printTicket(
    TicketData data, {
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
      final builder = TicketBuilder(layout: layout, company: company);
      final pdf = await builder.buildPdf(data);
      final platform = _ref.read(printingPlatformResolverProvider);
      if (platform.capabilities.isMobile) {
        final mobileResult = await _ref
            .read(mobilePrintServiceProvider)
            .printRaw(
              lines: builder.buildLines(data),
              pdfBytes: pdf,
              documentName: 'Ticket ${data.ticketNumber}',
            );
        return PrintTicketResult(
          success: mobileResult.success,
          message: mobileResult.message,
          ticketNumber: data.ticketNumber,
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
    final user = _ref.read(authStateProvider).user;
    final authCashierName = (user?.nombreCompleto ?? '').trim().isNotEmpty
        ? user!.nombreCompleto.trim()
        : (user?.email ?? '').trim();
    return printTicket(
      TicketData.fromSale(
        sale,
        items: items,
        isCopy: isCopy,
        cashierNameOverride: (sale.userName ?? '').trim().isNotEmpty
            ? sale.userName
            : authCashierName,
      ),
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
    return TicketBuilder(
      layout: layout,
      company: company,
    ).buildPlainText(data ?? TicketData.demo());
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
