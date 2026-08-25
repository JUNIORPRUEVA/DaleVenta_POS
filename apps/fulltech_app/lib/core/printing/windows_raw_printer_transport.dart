import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class RawPrintResult {
  const RawPrintResult({
    required this.success,
    required this.message,
    required this.printerName,
    required this.bytesWritten,
    required this.datatype,
  });

  final bool success;
  final String message;
  final String printerName;
  final int bytesWritten;
  final String datatype;
}

abstract class RawPrinterTransport {
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  });
}

class RawPrinterException implements Exception {
  const RawPrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WindowsRawPrinterTransport implements RawPrinterTransport {
  WindowsRawPrinterTransport({WindowsRawSpooler? spooler})
    : _spooler = spooler ?? _defaultSpooler(),
      _requiresWindowsPlatform = spooler == null;

  static const String datatype = 'RAW';

  /// Solo se crea el spooler FFI en Windows. Fuera de Windows se usa un stub
  /// que NUNCA abre `winspool.drv`/`kernel32.dll`: construir el transporte en
  /// Android/iOS no debe lanzar "Failed to load dynamic library".
  static WindowsRawSpooler _defaultSpooler() {
    if (Platform.isWindows) return FfiWindowsRawSpooler();
    return const _UnavailableWindowsSpooler();
  }

  final WindowsRawSpooler _spooler;
  final bool _requiresWindowsPlatform;

  @override
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  }) async {
    final normalizedPrinter = printerName.trim();
    if (normalizedPrinter.isEmpty) {
      throw const RawPrinterException('No hay impresora seleccionada.');
    }
    if (bytes.isEmpty) {
      throw const RawPrinterException('No hay bytes ESC/POS para imprimir.');
    }
    if (_requiresWindowsPlatform && !Platform.isWindows) {
      throw const RawPrinterException(
        'Windows RAW solo esta disponible en Windows.',
      );
    }

    final normalizedCopies = copies.clamp(1, 5);
    var totalWritten = 0;
    for (var i = 0; i < normalizedCopies; i++) {
      totalWritten += _spooler.writeRaw(
        printerName: normalizedPrinter,
        documentName: normalizedCopies == 1
            ? documentName
            : '$documentName copia ${i + 1}',
        datatype: datatype,
        bytes: bytes,
      );
    }
    return RawPrintResult(
      success: true,
      message: 'Impresion RAW enviada.',
      printerName: normalizedPrinter,
      bytesWritten: totalWritten,
      datatype: datatype,
    );
  }
}

abstract class WindowsRawSpooler {
  int writeRaw({
    required String printerName,
    required String documentName,
    required String datatype,
    required Uint8List bytes,
  });
}

final class FfiWindowsRawSpooler implements WindowsRawSpooler {
  FfiWindowsRawSpooler({DynamicLibrary? spoolLibrary, DynamicLibrary? kernel})
    : _spool = spoolLibrary ?? DynamicLibrary.open('winspool.drv'),
      _kernel = kernel ?? DynamicLibrary.open('kernel32.dll') {
    _openPrinter = _spool.lookupFunction<_OpenPrinterNative, _OpenPrinterDart>(
      'OpenPrinterW',
    );
    _startDocPrinter = _spool
        .lookupFunction<_StartDocPrinterNative, _StartDocPrinterDart>(
          'StartDocPrinterW',
        );
    _startPagePrinter = _spool
        .lookupFunction<_PrinterHandleBoolNative, _PrinterHandleBoolDart>(
          'StartPagePrinter',
        );
    _writePrinter = _spool
        .lookupFunction<_WritePrinterNative, _WritePrinterDart>('WritePrinter');
    _endPagePrinter = _spool
        .lookupFunction<_PrinterHandleBoolNative, _PrinterHandleBoolDart>(
          'EndPagePrinter',
        );
    _endDocPrinter = _spool
        .lookupFunction<_PrinterHandleBoolNative, _PrinterHandleBoolDart>(
          'EndDocPrinter',
        );
    _closePrinter = _spool
        .lookupFunction<_PrinterHandleBoolNative, _PrinterHandleBoolDart>(
          'ClosePrinter',
        );
    _getLastError = _kernel
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
  }

  final DynamicLibrary _spool;
  final DynamicLibrary _kernel;

  late final _OpenPrinterDart _openPrinter;
  late final _StartDocPrinterDart _startDocPrinter;
  late final _PrinterHandleBoolDart _startPagePrinter;
  late final _WritePrinterDart _writePrinter;
  late final _PrinterHandleBoolDart _endPagePrinter;
  late final _PrinterHandleBoolDart _endDocPrinter;
  late final _PrinterHandleBoolDart _closePrinter;
  late final _GetLastErrorDart _getLastError;

  @override
  int writeRaw({
    required String printerName,
    required String documentName,
    required String datatype,
    required Uint8List bytes,
  }) {
    final printerNamePtr = printerName.toNativeUtf16();
    final documentNamePtr = documentName.toNativeUtf16();
    final datatypePtr = datatype.toNativeUtf16();
    final printerHandlePtr = calloc<Pointer<Void>>();
    final docInfo = calloc<_DocInfo1W>();
    final writtenPtr = calloc<Uint32>();
    final buffer = calloc<Uint8>(bytes.length);

    Pointer<Void>? printerHandle;
    var docStarted = false;
    var pageStarted = false;

    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      docInfo.ref
        ..pDocName = documentNamePtr
        ..pOutputFile = nullptr
        ..pDatatype = datatypePtr;

      _ensureWin32(
        _openPrinter(printerNamePtr, printerHandlePtr, nullptr) != 0,
        'OpenPrinterW',
      );
      printerHandle = printerHandlePtr.value;
      final jobId = _startDocPrinter(printerHandle, 1, docInfo);
      _ensureWin32(jobId != 0, 'StartDocPrinterW');
      docStarted = true;
      _ensureWin32(_startPagePrinter(printerHandle) != 0, 'StartPagePrinter');
      pageStarted = true;
      _ensureWin32(
        _writePrinter(
              printerHandle,
              buffer.cast<Void>(),
              bytes.length,
              writtenPtr,
            ) !=
            0,
        'WritePrinter',
      );
      if (writtenPtr.value != bytes.length) {
        throw RawPrinterException(
          'WritePrinter escribio ${writtenPtr.value} de ${bytes.length} bytes.',
        );
      }
      return writtenPtr.value;
    } finally {
      if (pageStarted && printerHandle != null) {
        _endPagePrinter(printerHandle);
      }
      if (docStarted && printerHandle != null) {
        _endDocPrinter(printerHandle);
      }
      if (printerHandle != null) {
        _closePrinter(printerHandle);
      }
      calloc.free(buffer);
      calloc.free(writtenPtr);
      calloc.free(docInfo);
      calloc.free(printerHandlePtr);
      calloc.free(datatypePtr);
      calloc.free(documentNamePtr);
      calloc.free(printerNamePtr);
    }
  }

  void _ensureWin32(bool condition, String operation) {
    if (condition) return;
    final code = _getLastError();
    throw RawPrinterException('$operation fallo. Win32 error: $code');
  }
}

final class _DocInfo1W extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

typedef _OpenPrinterNative =
    Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);
typedef _OpenPrinterDart =
    int Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);

typedef _StartDocPrinterNative =
    Uint32 Function(Pointer<Void>, Uint32, Pointer<_DocInfo1W>);
typedef _StartDocPrinterDart =
    int Function(Pointer<Void>, int, Pointer<_DocInfo1W>);

typedef _PrinterHandleBoolNative = Int32 Function(Pointer<Void>);
typedef _PrinterHandleBoolDart = int Function(Pointer<Void>);

typedef _WritePrinterNative =
    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<Uint32>);
typedef _WritePrinterDart =
    int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// Spooler NO disponible fuera de Windows: NUNCA abre `winspool.drv`/
/// `kernel32.dll`. Permite construir `WindowsRawPrinterTransport` en
/// Android/iOS sin lanzar \"Failed to load dynamic library\" (la impresión
/// RAW solo existe en Windows; `printRaw` ya lo valida antes de usarlo).
class _UnavailableWindowsSpooler implements WindowsRawSpooler {
  const _UnavailableWindowsSpooler();

  @override
  int writeRaw({
    required String printerName,
    required String documentName,
    required String datatype,
    required Uint8List bytes,
  }) {
    throw const RawPrinterException(
      'La impresión RAW de Windows solo está disponible en Windows.',
    );
  }
}
