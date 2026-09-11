import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/raw_printer_transport.dart';
import 'package:daleventa_pos/core/printing/windows_printer_queue_inspector.dart';
import 'package:daleventa_pos/core/printing/windows_raw_printer_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sends complete bytes, printer name and RAW datatype to spooler',
    () async {
      final spooler = _FakeRawSpooler();
      final transport = WindowsRawPrinterTransport(spooler: spooler);
      final bytes = Uint8List.fromList([0x1B, 0x40, 0x41, 0x42, 0x43]);

      final result = await transport.printRaw(
        printerName: ' EPSON TM-T20 ',
        bytes: bytes,
        documentName: 'Ticket 123',
      );

      expect(result.success, isTrue);
      expect(result.printerName, 'EPSON TM-T20');
      expect(result.datatype, 'RAW');
      expect(result.bytesWritten, bytes.length);
      expect(spooler.calls, hasLength(1));
      expect(spooler.calls.single.printerName, 'EPSON TM-T20');
      expect(spooler.calls.single.documentName, 'Ticket 123');
      expect(spooler.calls.single.datatype, 'RAW');
      expect(spooler.calls.single.bytes, bytes);
    },
  );

  test('propagates RAW spooler errors', () async {
    final transport = WindowsRawPrinterTransport(
      spooler: _FakeRawSpooler(error: const RawPrinterException('boom')),
    );

    expect(
      () => transport.printRaw(
        printerName: 'POS-80',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<RawPrinterException>()),
    );
  });

  test('UNKNOWN queue status does not block RAW spool attempt', () async {
    final spooler = _FakeRawSpooler();
    final transport = WindowsRawPrinterTransport(
      spooler: spooler,
      queueInspector: _FixedQueueInspector(
        const WindowsPrinterQueueStatus(
          printerName: 'POS-80',
          state: WindowsPrinterQueueState.unknown,
          message: 'Windows reporto estado desconocido. Se intentara imprimir.',
        ),
      ),
    );

    final result = await transport.printRaw(
      printerName: 'POS-80',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(result.success, isTrue);
    expect(spooler.calls, hasLength(1));
  });

  test('PAUSED queue status blocks RAW with friendly message', () async {
    final spooler = _FakeRawSpooler();
    final transport = WindowsRawPrinterTransport(
      spooler: spooler,
      queueInspector: _FixedQueueInspector(
        const WindowsPrinterQueueStatus(
          printerName: 'POS-80',
          state: WindowsPrinterQueueState.paused,
          message: 'La cola de impresion esta pausada en Windows.',
        ),
      ),
    );

    await expectLater(
      transport.printRaw(
        printerName: 'POS-80',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<RawPrinterException>().having(
          (error) => error.message,
          'message',
          'La cola de impresion esta pausada en Windows.',
        ),
      ),
    );
    expect(spooler.calls, isEmpty);
  });

  test(
    'device command (checkQueueBeforeWrite: false) is attempted even when '
    'the queue reports PAUSED',
    () async {
      final spooler = _FakeRawSpooler();
      final transport = WindowsRawPrinterTransport(
        spooler: spooler,
        queueInspector: _FixedQueueInspector(
          const WindowsPrinterQueueStatus(
            printerName: 'SEWOO SLK-TS100',
            state: WindowsPrinterQueueState.paused,
            message: 'La cola de impresion esta pausada en Windows.',
          ),
        ),
        checkQueueBeforeWrite: false,
      );

      final result = await transport.printRaw(
        printerName: 'SEWOO SLK-TS100',
        bytes: Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]),
        documentName: 'FullPOS apertura de caja',
      );

      expect(result.success, isTrue);
      expect(spooler.calls, hasLength(1));
      expect(spooler.calls.single.datatype, 'RAW');
      expect(
        spooler.calls.single.bytes,
        [0x1B, 0x70, 0x00, 0x19, 0xFA],
      );
    },
  );

  test(
    'offline queue does not block a device command but still blocks documents',
    () async {
      final offlineInspector = _FixedQueueInspector(
        const WindowsPrinterQueueStatus(
          printerName: 'SEWOO SLK-TS100',
          state: WindowsPrinterQueueState.offline,
          message: 'La impresora parece estar desconectada.',
        ),
      );
      final deviceSpooler = _FakeRawSpooler();
      final deviceTransport = WindowsRawPrinterTransport(
        spooler: deviceSpooler,
        queueInspector: offlineInspector,
        checkQueueBeforeWrite: false,
      );

      final deviceResult = await deviceTransport.printRaw(
        printerName: 'SEWOO SLK-TS100',
        bytes: Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]),
      );

      expect(deviceResult.success, isTrue);
      expect(deviceSpooler.calls, hasLength(1));

      final documentSpooler = _FakeRawSpooler();
      final documentTransport = WindowsRawPrinterTransport(
        spooler: documentSpooler,
        queueInspector: offlineInspector,
      );

      await expectLater(
        documentTransport.printRaw(
          printerName: 'SEWOO SLK-TS100',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<RawPrinterException>()),
      );
      expect(documentSpooler.calls, isEmpty);
    },
  );

  test(
    'DEVICE COMMAND reaches WritePrinter for every informational queue state',
    () async {
      const states = <WindowsPrinterQueueState, String>{
        WindowsPrinterQueueState.ready: 'Cola de Windows disponible.',
        WindowsPrinterQueueState.busy: 'La impresora esta ocupada.',
        WindowsPrinterQueueState.unknown: 'Estado desconocido.',
        WindowsPrinterQueueState.offline: 'La impresora parece desconectada.',
        WindowsPrinterQueueState.paused: 'La cola esta pausada.',
        WindowsPrinterQueueState.notFound: 'La impresora no esta disponible.',
      };

      for (final entry in states.entries) {
        final spooler = _FakeRawSpooler();
        final transport = WindowsRawPrinterTransport(
          spooler: spooler,
          queueInspector: _FixedQueueInspector(
            WindowsPrinterQueueStatus(
              printerName: 'SEWOO SLK-TS100',
              state: entry.key,
              message: entry.value,
            ),
          ),
          checkQueueBeforeWrite: false,
        );

        final result = await transport.printRaw(
          printerName: 'SEWOO SLK-TS100',
          bytes: Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]),
        );

        final reason = 'estado ${entry.key.name}';
        expect(result.success, isTrue, reason: reason);
        expect(result.stage, RawPrintStage.rawWriteSucceeded, reason: reason);
        expect(spooler.calls, hasLength(1), reason: reason);
      }
    },
  );

  test('PARTIAL WRITE is a transport failure, never a success', () async {
    final spooler = _FakeRawSpooler(reportedBytes: 3);
    final transport = WindowsRawPrinterTransport(spooler: spooler);

    await expectLater(
      transport.printRaw(
        printerName: 'SEWOO SLK-TS100',
        bytes: Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]),
      ),
      throwsA(
        isA<RawPrinterException>()
            .having((e) => e.stage, 'stage', RawPrintStage.partialWrite)
            .having((e) => e.bytesWritten, 'bytesWritten', 3),
      ),
    );
  });

  test('rawWriteSucceeded means command sent, not hardware confirmed', () async {
    final transport = WindowsRawPrinterTransport(spooler: _FakeRawSpooler());

    final result = await transport.printRaw(
      printerName: 'SEWOO SLK-TS100',
      bytes: Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]),
    );

    expect(result.stage, RawPrintStage.rawWriteSucceeded);
    expect(result.stage.isSent, isTrue);
    expect(result.stage.label, 'RAW_WRITE_SUCCEEDED');
  });

  test('empty printer name maps to PRINTER_NOT_FOUND stage', () async {
    final transport = WindowsRawPrinterTransport(spooler: _FakeRawSpooler());

    await expectLater(
      transport.printRaw(
        printerName: '   ',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<RawPrinterException>().having(
          (e) => e.stage,
          'stage',
          RawPrintStage.printerNotFound,
        ),
      ),
    );
  });

  test('transport stage labels are stable for support reports', () {
    expect(RawPrintStage.printerNotFound.label, 'PRINTER_NOT_FOUND');
    expect(RawPrintStage.openPrinterFailed.label, 'OPEN_PRINTER_FAILED');
    expect(RawPrintStage.startDocumentFailed.label, 'START_DOCUMENT_FAILED');
    expect(RawPrintStage.startPageFailed.label, 'START_PAGE_FAILED');
    expect(RawPrintStage.rawWriteFailed.label, 'RAW_WRITE_FAILED');
    expect(RawPrintStage.partialWrite.label, 'PARTIAL_WRITE');
    expect(RawPrintStage.rawWriteSucceeded.label, 'RAW_WRITE_SUCCEEDED');
  });
}

class _FixedQueueInspector extends WindowsPrinterQueueInspector {
  _FixedQueueInspector(this.status);

  final WindowsPrinterQueueStatus status;

  @override
  Future<WindowsPrinterQueueStatus?> inspect(String printerName) async =>
      status;
}

class _FakeRawSpooler implements WindowsRawSpooler {
  _FakeRawSpooler({this.error, this.reportedBytes});

  final RawPrinterException? error;

  /// Si se indica, la simulacion de spooler reporta menos bytes escritos de
  /// los solicitados (escritura parcial).
  final int? reportedBytes;

  final calls = <_RawSpoolerCall>[];

  @override
  int writeRaw({
    required String printerName,
    required String documentName,
    required String datatype,
    required Uint8List bytes,
  }) {
    final error = this.error;
    if (error != null) throw error;
    calls.add(
      _RawSpoolerCall(
        printerName: printerName,
        documentName: documentName,
        datatype: datatype,
        bytes: Uint8List.fromList(bytes),
      ),
    );
    return reportedBytes ?? bytes.length;
  }
}

class _RawSpoolerCall {
  const _RawSpoolerCall({
    required this.printerName,
    required this.documentName,
    required this.datatype,
    required this.bytes,
  });

  final String printerName;
  final String documentName;
  final String datatype;
  final Uint8List bytes;
}
