import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../features/settings/data/printer_settings_model.dart';
import 'windows_printer_queue_inspector_stub.dart'
    if (dart.library.io) 'windows_printer_queue_inspector.dart';

typedef DirectPdfPrinter =
    Future<bool> Function({
      required Printer printer,
      required String name,
      required PdfPageFormat format,
      required bool dynamicLayout,
      required bool usePrinterSettings,
      required Future<Uint8List> Function(PdfPageFormat format) onLayout,
    });

class PrinterStatus {
  const PrinterStatus({
    required this.isConfigured,
    required this.isAvailable,
    required this.message,
    this.printerName,
    this.resolvedPrinterName,
    this.printer,
    this.queueStatus,
  });

  final bool isConfigured;
  final bool isAvailable;
  final String message;
  final String? printerName;
  final String? resolvedPrinterName;
  final Printer? printer;
  final WindowsPrinterQueueStatus? queueStatus;
}

class PrintResult {
  const PrintResult({
    required this.success,
    required this.message,
    this.submittedToSpooler = false,
    this.printerName,
    this.printingMode,
  });

  final bool success;
  final String message;
  final bool submittedToSpooler;
  final String? printerName;
  final WindowsPrinterMode? printingMode;
}

class ThermalPrinterService {
  ThermalPrinterService({
    WindowsPrinterQueueInspector? queueInspector,
    DirectPdfPrinter? directPdfPrinter,
  }) : _queueInspector = queueInspector ?? WindowsPrinterQueueInspector(),
       _directPdfPrinter = directPdfPrinter ?? _defaultDirectPdfPrinter;

  static const double _paper80WidthMm = 80;
  static const double _paper58WidthMm = 58;
  static const double _thermalPageHeightMm = 2000;

  final WindowsPrinterQueueInspector _queueInspector;
  final DirectPdfPrinter _directPdfPrinter;
  Printer? _cachedPrinter;
  String? _cachedName;

  static Future<bool> _defaultDirectPdfPrinter({
    required Printer printer,
    required String name,
    required PdfPageFormat format,
    required bool dynamicLayout,
    required bool usePrinterSettings,
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
  }) async {
    return Printing.directPrintPdf(
      printer: printer,
      name: name,
      format: format,
      dynamicLayout: dynamicLayout,
      usePrinterSettings: usePrinterSettings,
      onLayout: onLayout,
    );
  }

  Future<List<Printer>> getAvailablePrinters() {
    return Printing.listPrinters();
  }

  Future<Printer?> findPrinter(String? name) async {
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (_cachedPrinter != null &&
        _cachedName == normalized &&
        _cachedPrinter!.isAvailable) {
      return _cachedPrinter;
    }
    final printers = await getAvailablePrinters();
    final exact = printers.where((printer) => printer.name == normalized);
    for (final printer in exact) {
      if (printer.isAvailable) return _cache(normalized, printer);
    }
    final family = _printerFamily(normalized);
    for (final printer in printers) {
      if (!printer.isAvailable) continue;
      if (_printerFamily(printer.name) == family) {
        return _cache(normalized, printer);
      }
    }
    if (exact.isNotEmpty) return null;
    return null;
  }

  Printer _cache(String configuredName, Printer printer) {
    _cachedPrinter = printer;
    _cachedName = configuredName;
    return printer;
  }

  String _printerFamily(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\s*\(copy\s+\d+\)\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<PrinterStatus> checkPrinterStatus(
    PrinterSettingsModel settings,
  ) async {
    final configured = (settings.selectedPrinterName ?? '').trim();
    if (configured.isEmpty) {
      return const PrinterStatus(
        isConfigured: false,
        isAvailable: false,
        message: 'No hay impresora seleccionada.',
      );
    }
    final printer = await findPrinter(configured);
    if (printer == null) {
      return PrinterStatus(
        isConfigured: true,
        isAvailable: false,
        printerName: configured,
        message: 'La impresora configurada no esta disponible.',
      );
    }
    final queueStatus = await _queueInspector.inspect(printer.name);
    if (queueStatus != null) {
      debugPrint(
        '[PRINT] Windows queue status printer="${printer.name}" '
        'usable=${queueStatus.isUsable} attributes=${queueStatus.attributes} '
        'status=${queueStatus.status} jobs=${queueStatus.jobCount} '
        'message="${queueStatus.message}"',
      );
      if (!queueStatus.isUsable) {
        return PrinterStatus(
          isConfigured: true,
          isAvailable: false,
          printerName: configured,
          resolvedPrinterName: printer.name,
          printer: printer,
          queueStatus: queueStatus,
          message: queueStatus.message,
        );
      }
    }
    return PrinterStatus(
      isConfigured: true,
      isAvailable: true,
      printerName: configured,
      resolvedPrinterName: printer.name,
      printer: printer,
      queueStatus: queueStatus,
      message: 'Impresora lista.',
    );
  }

  Future<PrintResult> printDocument({
    required Uint8List bytes,
    required PrinterSettingsModel settings,
    int? copies,
    String documentName = 'Ticket',
  }) async {
    final count = copies ?? settings.copies;
    if (count <= 0) {
      return const PrintResult(
        success: true,
        message: 'Sin copias configuradas (0)',
      );
    }
    final status = await checkPrinterStatus(settings);
    if (!status.isAvailable || status.printer == null) {
      return PrintResult(success: false, message: status.message);
    }
    final normalizedCount = count.clamp(1, 5);
    try {
      for (var i = 0; i < normalizedCount; i++) {
        debugPrint(
          '[PRINT] entering ThermalPrinterService.printDocument copy ${i + 1}/$normalizedCount',
        );
        debugPrint('[PRINT] output pdf bytes received = ${bytes.length}');
        debugPrint(
          '[PRINT] entering Printing.directPrintPdf printer="${status.printer!.name}"',
        );
        final submitted = await _directPdfPrinter(
          printer: status.printer!,
          name: '${documentName}_${DateTime.now().millisecondsSinceEpoch}',
          format: getPageFormat(settings),
          dynamicLayout: false,
          usePrinterSettings:
              settings.windowsPrinterMode == WindowsPrinterMode.driver,
          onLayout: (_) async => bytes,
        );
        if (!submitted) {
          return PrintResult(
            success: false,
            submittedToSpooler: false,
            printerName: status.printer!.name,
            printingMode: settings.windowsPrinterMode,
            message:
                'Windows no acepto el trabajo de impresion para ${status.printer!.name}.',
          );
        }
      }
      return PrintResult(
        success: true,
        submittedToSpooler: true,
        printerName: status.printer!.name,
        printingMode: settings.windowsPrinterMode,
        message: 'Trabajo enviado a la cola de Windows.',
      );
    } catch (e) {
      return PrintResult(
        success: false,
        submittedToSpooler: false,
        printerName: status.resolvedPrinterName ?? status.printerName,
        printingMode: settings.windowsPrinterMode,
        message: 'No se pudo enviar a Windows: $e',
      );
    }
  }

  void clearCache() {
    _cachedPrinter = null;
    _cachedName = null;
  }

  PdfPageFormat getPageFormat(PrinterSettingsModel settings) {
    final widthMm = settings.paperWidthMm == 58
        ? _paper58WidthMm
        : _paper80WidthMm;
    return PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      _thermalPageHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );
  }
}
