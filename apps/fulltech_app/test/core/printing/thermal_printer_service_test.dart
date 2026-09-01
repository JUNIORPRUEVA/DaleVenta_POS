import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/thermal_printer_service.dart';
import 'package:daleventa_pos/core/printing/windows_printer_queue_inspector_stub.dart'
    if (dart.library.io) 'package:daleventa_pos/core/printing/windows_printer_queue_inspector.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

void main() {
  test(
    'usa copia disponible cuando la impresora base no esta disponible',
    () async {
      final service = _FakeThermalPrinterService([
        const Printer(
          url: 'SEWOO SLK-TS100',
          name: 'SEWOO SLK-TS100',
          isAvailable: false,
        ),
        const Printer(
          url: 'SEWOO SLK-TS100 (copy 1)',
          name: 'SEWOO SLK-TS100 (copy 1)',
          isAvailable: true,
        ),
      ], queueInspector: _FakeQueueInspector());

      final printer = await service.findPrinter('SEWOO SLK-TS100');

      expect(printer?.name, 'SEWOO SLK-TS100 (copy 1)');
    },
  );

  test('marca no disponible cuando no existe copia sana', () async {
    final service = _FakeThermalPrinterService([
      const Printer(
        url: 'SEWOO SLK-TS100',
        name: 'SEWOO SLK-TS100',
        isAvailable: false,
      ),
    ], queueInspector: _FakeQueueInspector());

    final status = await service.checkPrinterStatus(
      const PrinterSettingsModel(selectedPrinterName: 'SEWOO SLK-TS100'),
    );

    expect(status.isAvailable, isFalse);
    expect(status.message, 'La impresora configurada no esta disponible.');
  });

  test('marca no disponible cuando Windows reporta cola offline', () async {
    final service = _FakeThermalPrinterService(
      [
        const Printer(
          url: 'SEWOO SLK-TS100',
          name: 'SEWOO SLK-TS100',
          isAvailable: true,
        ),
      ],
      queueInspector: _FakeQueueInspector(
        status: const WindowsPrinterQueueStatus(
          printerName: 'SEWOO SLK-TS100',
          isUsable: false,
          message: 'La cola de Windows no esta lista: modo sin conexion.',
          attributes: 1024,
          status: 0,
          jobCount: 1,
        ),
      ),
    );

    final status = await service.checkPrinterStatus(
      const PrinterSettingsModel(selectedPrinterName: 'SEWOO SLK-TS100'),
    );

    expect(status.isAvailable, isFalse);
    expect(status.resolvedPrinterName, 'SEWOO SLK-TS100');
    expect(
      status.message,
      'La cola de Windows no esta lista: modo sin conexion.',
    );
  });

  test('no marca exito si Windows rechaza el trabajo inmediatamente', () async {
    final service = _FakeThermalPrinterService(
      [const Printer(url: 'POS-80', name: 'POS-80', isAvailable: true)],
      queueInspector: _FakeQueueInspector(),
      directPdfPrinter:
          ({
            required printer,
            required name,
            required format,
            required dynamicLayout,
            required usePrinterSettings,
            required onLayout,
          }) async => false,
    );

    final result = await service.printDocument(
      bytes: Uint8List.fromList([1, 2, 3]),
      settings: const PrinterSettingsModel(selectedPrinterName: 'POS-80'),
    );

    expect(result.success, isFalse);
    expect(result.submittedToSpooler, isFalse);
    expect(result.message, contains('Windows no acepto'));
  });

  test('modo Windows driver usa configuracion del driver', () async {
    var usePrinterSettingsSeen = false;
    final service = _FakeThermalPrinterService(
      [
        const Printer(
          url: 'SEWOO SLK-TS100',
          name: 'SEWOO SLK-TS100',
          isAvailable: true,
        ),
      ],
      queueInspector: _FakeQueueInspector(),
      directPdfPrinter:
          ({
            required printer,
            required name,
            required format,
            required dynamicLayout,
            required usePrinterSettings,
            required onLayout,
          }) async {
            usePrinterSettingsSeen = usePrinterSettings;
            return true;
          },
    );

    final result = await service.printDocument(
      bytes: Uint8List.fromList([1, 2, 3]),
      settings: const PrinterSettingsModel(
        selectedPrinterName: 'SEWOO SLK-TS100',
        windowsPrinterMode: WindowsPrinterMode.driver,
      ),
    );

    expect(result.success, isTrue);
    expect(result.submittedToSpooler, isTrue);
    expect(usePrinterSettingsSeen, isTrue);
  });
}

class _FakeThermalPrinterService extends ThermalPrinterService {
  _FakeThermalPrinterService(
    this.printers, {
    required WindowsPrinterQueueInspector queueInspector,
    super.directPdfPrinter,
  }) : super(queueInspector: queueInspector);

  final List<Printer> printers;

  @override
  Future<List<Printer>> getAvailablePrinters() async => printers;
}

class _FakeQueueInspector extends WindowsPrinterQueueInspector {
  _FakeQueueInspector({this.status});

  final WindowsPrinterQueueStatus? status;

  @override
  Future<WindowsPrinterQueueStatus?> inspect(String printerName) async {
    return status ??
        WindowsPrinterQueueStatus(
          printerName: printerName,
          isUsable: true,
          message: 'Cola de Windows disponible.',
        );
  }
}
