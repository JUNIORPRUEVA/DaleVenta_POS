import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

class WindowsPrinterQueueStatus {
  const WindowsPrinterQueueStatus({
    required this.printerName,
    required this.isUsable,
    required this.message,
    this.attributes = 0,
    this.status = 0,
    this.jobCount = 0,
  });

  final String printerName;
  final bool isUsable;
  final String message;
  final int attributes;
  final int status;
  final int jobCount;
}

class WindowsPrinterQueueInspector {
  WindowsPrinterQueueInspector({DynamicLibrary? spoolLibrary})
    : _spool = Platform.isWindows
          ? (spoolLibrary ?? DynamicLibrary.open('winspool.drv'))
          : null {
    final spool = _spool;
    if (spool == null) return;
    _openPrinter = spool.lookupFunction<_OpenPrinterNative, _OpenPrinterDart>(
      'OpenPrinterW',
    );
    _getPrinter = spool.lookupFunction<_GetPrinterNative, _GetPrinterDart>(
      'GetPrinterW',
    );
    _closePrinter = spool
        .lookupFunction<_ClosePrinterNative, _ClosePrinterDart>('ClosePrinter');
  }

  static const int _printerAttributeWorkOffline = 0x00000400;
  static const int _printerStatusPaused = 0x00000001;
  static const int _printerStatusError = 0x00000002;
  static const int _printerStatusPendingDeletion = 0x00000004;
  static const int _printerStatusPaperJam = 0x00000008;
  static const int _printerStatusPaperOut = 0x00000010;
  static const int _printerStatusManualFeed = 0x00000020;
  static const int _printerStatusOffline = 0x00000080;
  static const int _printerStatusIoActive = 0x00000100;
  static const int _printerStatusBusy = 0x00000200;
  static const int _printerStatusPrinting = 0x00000400;
  static const int _printerStatusOutputBinFull = 0x00000800;
  static const int _printerStatusNotAvailable = 0x00001000;
  static const int _printerStatusWaiting = 0x00002000;
  static const int _printerStatusProcessing = 0x00004000;
  static const int _printerStatusInitializing = 0x00008000;
  static const int _printerStatusWarmingUp = 0x00010000;
  static const int _printerStatusTonerLow = 0x00020000;
  static const int _printerStatusNoToner = 0x00040000;
  static const int _printerStatusPagePunt = 0x00080000;
  static const int _printerStatusUserIntervention = 0x00100000;
  static const int _printerStatusOutOfMemory = 0x00200000;
  static const int _printerStatusDoorOpen = 0x00400000;
  static const int _printerStatusServerUnknown = 0x00800000;
  static const int _printerStatusPowerSave = 0x01000000;

  static const Map<int, String> _statusMessages = {
    _printerStatusPaused: 'cola pausada',
    _printerStatusError: 'error',
    _printerStatusPendingDeletion: 'eliminacion pendiente',
    _printerStatusPaperJam: 'papel atascado',
    _printerStatusPaperOut: 'sin papel',
    _printerStatusManualFeed: 'alimentacion manual',
    _printerStatusOffline: 'offline',
    _printerStatusIoActive: 'E/S activa',
    _printerStatusBusy: 'ocupada',
    _printerStatusPrinting: 'imprimiendo',
    _printerStatusOutputBinFull: 'salida llena',
    _printerStatusNotAvailable: 'no disponible',
    _printerStatusWaiting: 'esperando',
    _printerStatusProcessing: 'procesando',
    _printerStatusInitializing: 'inicializando',
    _printerStatusWarmingUp: 'calentando',
    _printerStatusTonerLow: 'toner bajo',
    _printerStatusNoToner: 'sin toner',
    _printerStatusPagePunt: 'pagina descartada',
    _printerStatusUserIntervention: 'requiere intervencion',
    _printerStatusOutOfMemory: 'sin memoria',
    _printerStatusDoorOpen: 'tapa abierta',
    _printerStatusServerUnknown: 'estado desconocido',
    _printerStatusPowerSave: 'ahorro de energia',
  };

  final DynamicLibrary? _spool;
  late final _OpenPrinterDart _openPrinter;
  late final _GetPrinterDart _getPrinter;
  late final _ClosePrinterDart _closePrinter;

  Future<WindowsPrinterQueueStatus?> inspect(String printerName) async {
    if (!Platform.isWindows || _spool == null) return null;
    final normalized = printerName.trim();
    if (normalized.isEmpty) return null;

    final namePtr = normalized.toNativeUtf16();
    final handlePtr = calloc<Pointer<Void>>();
    Pointer<Void>? handle;
    Pointer<Uint8>? buffer;
    try {
      if (_openPrinter(namePtr, handlePtr, nullptr) == 0) {
        return WindowsPrinterQueueStatus(
          printerName: normalized,
          isUsable: false,
          message: 'Windows no pudo abrir la cola de impresion.',
        );
      }
      handle = handlePtr.value;
      final neededPtr = calloc<Uint32>();
      try {
        _getPrinter(handle, 2, nullptr, 0, neededPtr);
        final needed = neededPtr.value;
        if (needed == 0) {
          return WindowsPrinterQueueStatus(
            printerName: normalized,
            isUsable: false,
            message: 'Windows no entrego informacion de la cola.',
          );
        }
        buffer = calloc<Uint8>(needed);
        if (_getPrinter(handle, 2, buffer, needed, neededPtr) == 0) {
          return WindowsPrinterQueueStatus(
            printerName: normalized,
            isUsable: false,
            message: 'Windows rechazo la lectura de la cola.',
          );
        }
      } finally {
        calloc.free(neededPtr);
      }

      final info = buffer.cast<_PrinterInfo2W>().ref;
      final attributes = info.attributes;
      final status = info.status;
      final workOffline = (attributes & _printerAttributeWorkOffline) != 0;
      final blockingStatuses = <String>[];
      for (final entry in _statusMessages.entries) {
        if ((status & entry.key) != 0) blockingStatuses.add(entry.value);
      }
      final hasBlockingStatus =
          (status &
              (_printerStatusPaused |
                  _printerStatusError |
                  _printerStatusPendingDeletion |
                  _printerStatusPaperJam |
                  _printerStatusPaperOut |
                  _printerStatusOffline |
                  _printerStatusNotAvailable |
                  _printerStatusUserIntervention |
                  _printerStatusOutOfMemory |
                  _printerStatusDoorOpen |
                  _printerStatusServerUnknown)) !=
          0;
      if (workOffline || hasBlockingStatus) {
        final details = [
          if (workOffline) 'modo sin conexion',
          ...blockingStatuses,
        ].join(', ');
        return WindowsPrinterQueueStatus(
          printerName: normalized,
          isUsable: false,
          message: 'La cola de Windows no esta lista: $details.',
          attributes: attributes,
          status: status,
          jobCount: info.cJobs,
        );
      }
      return WindowsPrinterQueueStatus(
        printerName: normalized,
        isUsable: true,
        message: info.cJobs > 0
            ? 'Cola de Windows disponible con ${info.cJobs} trabajo(s) pendiente(s).'
            : 'Cola de Windows disponible.',
        attributes: attributes,
        status: status,
        jobCount: info.cJobs,
      );
    } finally {
      if (handle != null) _closePrinter(handle);
      if (buffer != null) calloc.free(buffer);
      calloc.free(handlePtr);
      calloc.free(namePtr);
    }
  }
}

final class _PrinterInfo2W extends Struct {
  external Pointer<Utf16> pServerName;
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pShareName;
  external Pointer<Utf16> pPortName;
  external Pointer<Utf16> pDriverName;
  external Pointer<Utf16> pComment;
  external Pointer<Utf16> pLocation;
  external Pointer<Void> pDevMode;
  external Pointer<Utf16> pSepFile;
  external Pointer<Utf16> pPrintProcessor;
  external Pointer<Utf16> pDatatype;
  external Pointer<Utf16> pParameters;
  external Pointer<Void> pSecurityDescriptor;
  @Uint32()
  external int attributes;
  @Uint32()
  external int priority;
  @Uint32()
  external int defaultPriority;
  @Uint32()
  external int startTime;
  @Uint32()
  external int untilTime;
  @Uint32()
  external int status;
  @Uint32()
  external int cJobs;
  @Uint32()
  external int averagePPM;
}

typedef _OpenPrinterNative =
    Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);
typedef _OpenPrinterDart =
    int Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>);

typedef _GetPrinterNative =
    Int32 Function(
      Pointer<Void>,
      Uint32,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
    );
typedef _GetPrinterDart =
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Uint32>);

typedef _ClosePrinterNative = Int32 Function(Pointer<Void>);
typedef _ClosePrinterDart = int Function(Pointer<Void>);
