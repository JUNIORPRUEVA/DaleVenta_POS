import 'dart:typed_data';

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
}

class _FakeRawSpooler implements WindowsRawSpooler {
  _FakeRawSpooler({this.error});

  final RawPrinterException? error;
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
    return bytes.length;
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
