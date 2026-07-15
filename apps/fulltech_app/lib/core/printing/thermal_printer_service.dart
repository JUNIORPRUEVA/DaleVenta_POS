import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../features/settings/data/printer_settings_model.dart';

class PrinterStatus {
  const PrinterStatus({
    required this.isConfigured,
    required this.isAvailable,
    required this.message,
    this.printerName,
    this.printer,
  });

  final bool isConfigured;
  final bool isAvailable;
  final String message;
  final String? printerName;
  final Printer? printer;
}

class PrintResult {
  const PrintResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class ThermalPrinterService {
  Printer? _cachedPrinter;
  String? _cachedName;

  Future<List<Printer>> getAvailablePrinters() {
    return Printing.listPrinters();
  }

  Future<Printer?> findPrinter(String? name) async {
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (_cachedPrinter != null && _cachedName == normalized) {
      return _cachedPrinter;
    }
    final printers = await getAvailablePrinters();
    for (final printer in printers) {
      if (printer.name == normalized) {
        _cachedPrinter = printer;
        _cachedName = normalized;
        return printer;
      }
    }
    return null;
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
    return PrinterStatus(
      isConfigured: true,
      isAvailable: true,
      printerName: configured,
      printer: printer,
      message: 'Impresora lista.',
    );
  }

  Future<PrintResult> printDocument({
    required Uint8List bytes,
    required PrinterSettingsModel settings,
    int? copies,
    String documentName = 'Ticket',
  }) async {
    final status = await checkPrinterStatus(settings);
    if (!status.isAvailable || status.printer == null) {
      return PrintResult(success: false, message: status.message);
    }
    final count = (copies ?? settings.copies).clamp(1, 5);
    try {
      for (var i = 0; i < count; i++) {
        await Printing.directPrintPdf(
          printer: status.printer!,
          name: documentName,
          onLayout: (_) async => bytes,
        );
      }
      return const PrintResult(success: true, message: 'Impresion enviada.');
    } catch (e) {
      return PrintResult(success: false, message: 'No se pudo imprimir: $e');
    }
  }

  void clearCache() {
    _cachedPrinter = null;
    _cachedName = null;
  }
}
