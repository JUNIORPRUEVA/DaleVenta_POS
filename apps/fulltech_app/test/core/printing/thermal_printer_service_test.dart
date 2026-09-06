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

  test(
    'bloquea con mensaje amable cuando Windows reporta cola pausada',
    () async {
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
            state: WindowsPrinterQueueState.paused,
            message: 'La cola de impresion esta pausada en Windows.',
            status: 1,
            jobCount: 1,
          ),
        ),
      );

      final status = await service.checkPrinterStatus(
        const PrinterSettingsModel(selectedPrinterName: 'SEWOO SLK-TS100'),
      );

      expect(status.isAvailable, isFalse);
      expect(status.resolvedPrinterName, 'SEWOO SLK-TS100');
      expect(status.message, 'La cola de impresion esta pausada en Windows.');
    },
  );

  test(
    'intenta imprimir cuando Windows solo reporta estado desconocido',
    () async {
      var submitted = false;
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
            state: WindowsPrinterQueueState.unknown,
            message:
                'Windows reporto estado desconocido. Se intentara imprimir.',
            attributes: 1024,
            status: 0,
          ),
        ),
        directPdfPrinter:
            ({
              required printer,
              required name,
              required format,
              required dynamicLayout,
              required usePrinterSettings,
              required onLayout,
            }) async {
              submitted = true;
              return true;
            },
      );

      final result = await service.printDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'SEWOO SLK-TS100',
        ),
      );

      expect(result.success, isTrue);
      expect(submitted, isTrue);
    },
  );

  test('permite cola ocupada para que Windows encole el trabajo', () async {
    var submitted = false;
    final service = _FakeThermalPrinterService(
      [const Printer(url: 'POS-80', name: 'POS-80', isAvailable: true)],
      queueInspector: _FakeQueueInspector(
        status: const WindowsPrinterQueueStatus(
          printerName: 'POS-80',
          state: WindowsPrinterQueueState.busy,
          message:
              'La impresora esta ocupada. Windows pondra el trabajo en cola.',
          status: 512,
          jobCount: 2,
        ),
      ),
      directPdfPrinter:
          ({
            required printer,
            required name,
            required format,
            required dynamicLayout,
            required usePrinterSettings,
            required onLayout,
          }) async {
            submitted = true;
            return true;
          },
    );

    final result = await service.printDocument(
      bytes: Uint8List.fromList([1, 2, 3]),
      settings: const PrinterSettingsModel(selectedPrinterName: 'POS-80'),
    );

    expect(result.success, isTrue);
    expect(submitted, isTrue);
  });

  test(
    'bloquea con mensaje offline especifico cuando hay evidencia confiable',
    () async {
      final service = _FakeThermalPrinterService(
        [const Printer(url: 'POS-80', name: 'POS-80', isAvailable: true)],
        queueInspector: _FakeQueueInspector(
          status: const WindowsPrinterQueueStatus(
            printerName: 'POS-80',
            state: WindowsPrinterQueueState.offline,
            message:
                'La impresora parece estar desconectada. Verifica que este encendida y conectada.',
            status: 128,
          ),
        ),
      );

      final result = await service.printDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        settings: const PrinterSettingsModel(selectedPrinterName: 'POS-80'),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('parece estar desconectada'));
    },
  );

  test(
    'reporta servicio de impresion de Windows cuando el spooler no responde',
    () async {
      final service = _FakeThermalPrinterService(
        [const Printer(url: 'POS-80', name: 'POS-80', isAvailable: true)],
        queueInspector: _FakeQueueInspector(
          status: const WindowsPrinterQueueStatus(
            printerName: 'POS-80',
            state: WindowsPrinterQueueState.spoolerDown,
            message: 'El servicio de impresion de Windows no esta disponible.',
          ),
        ),
      );

      final result = await service.printDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        settings: const PrinterSettingsModel(selectedPrinterName: 'POS-80'),
      );

      expect(result.success, isFalse);
      expect(
        result.message,
        'El servicio de impresion de Windows no esta disponible.',
      );
    },
  );

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
          state: WindowsPrinterQueueState.ready,
          message: 'Cola de Windows disponible.',
        );
  }
}
