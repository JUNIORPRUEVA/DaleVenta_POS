import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

enum WindowsPrinterQueueState {
  ready,
  busy,
  paused,
  offline,
  unknown,
  notFound,
  spoolerDown,
}

class WindowsPrinterQueueStatus {
  const WindowsPrinterQueueStatus({
    required this.printerName,
    required this.state,
    required this.message,
    this.attributes = 0,
    this.status = 0,
    this.jobCount = 0,
    this.technicalDetails,
  });

  final String printerName;
  final WindowsPrinterQueueState state;
  final String message;
  final int attributes;
  final int status;
  final int jobCount;
  final String? technicalDetails;

  bool get isUsable =>
      state == WindowsPrinterQueueState.ready ||
      state == WindowsPrinterQueueState.busy ||
      state == WindowsPrinterQueueState.unknown;
}

class WindowsPrinterQueueInspector {
  WindowsPrinterQueueInspector({DynamicLibrary? spoolLibrary})
    : _spool = Platform.isWindows
          ? (spoolLibrary ?? DynamicLibrary.open('winspool.drv'))
          : null,
      _kernel = Platform.isWindows
          ? DynamicLibrary.open('kernel32.dll')
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
    _getLastError = _kernel!
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
  }

  static const int _errorInvalidPrinterName = 1801;
  static const int _errorPrinterDeleted = 1905;
  static const int _rpcServerUnavailable = 1722;
  static const int _rpcCallFailed = 1726;
  static const int _errorSpoolerNotLoaded = 3003;

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
  final DynamicLibrary? _kernel;
  late final _OpenPrinterDart _openPrinter;
  late final _GetPrinterDart _getPrinter;
  late final _ClosePrinterDart _closePrinter;
  late final _GetLastErrorDart _getLastError;

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
        final errorCode = _getLastError();
        final state = _openPrinterFailureState(errorCode);
        return WindowsPrinterQueueStatus(
          printerName: normalized,
          state: state,
          message: _friendlyMessageForState(state),
          technicalDetails: 'OpenPrinterW fallo. Win32 error: $errorCode',
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
            state: WindowsPrinterQueueState.unknown,
            message:
                'Windows no entrego el estado de la impresora. Se intentara imprimir.',
            technicalDetails: 'GetPrinterW nivel 2 no entrego tamano.',
          );
        }
        buffer = calloc<Uint8>(needed);
        if (_getPrinter(handle, 2, buffer, needed, neededPtr) == 0) {
          final errorCode = _getLastError();
          return WindowsPrinterQueueStatus(
            printerName: normalized,
            state: WindowsPrinterQueueState.unknown,
            message:
                'Windows no entrego el estado de la impresora. Se intentara imprimir.',
            technicalDetails: 'GetPrinterW fallo. Win32 error: $errorCode',
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
      final state = _stateFromFlags(
        attributes: attributes,
        status: status,
        workOffline: workOffline,
      );
      if (state != WindowsPrinterQueueState.ready &&
          state != WindowsPrinterQueueState.busy &&
          state != WindowsPrinterQueueState.unknown) {
        final details = blockingStatuses.join(', ');
        return WindowsPrinterQueueStatus(
          printerName: normalized,
          state: state,
          message: _friendlyMessageForState(state),
          attributes: attributes,
          status: status,
          jobCount: info.cJobs,
          technicalDetails:
              'Bloqueo de cola Windows: ${details.isEmpty ? 'sin detalle' : details}.',
        );
      }
      return WindowsPrinterQueueStatus(
        printerName: normalized,
        state: state,
        message: state == WindowsPrinterQueueState.unknown
            ? 'Windows reporto estado desconocido. Se intentara imprimir.'
            : info.cJobs > 0
            ? 'Cola de Windows disponible con ${info.cJobs} trabajo(s) pendiente(s).'
            : 'Cola de Windows disponible.',
        attributes: attributes,
        status: status,
        jobCount: info.cJobs,
        technicalDetails: workOffline
            ? 'Windows reporto WorkOffline sin estado OFFLINE confiable.'
            : null,
      );
    } finally {
      if (handle != null) _closePrinter(handle);
      if (buffer != null) calloc.free(buffer);
      calloc.free(handlePtr);
      calloc.free(namePtr);
    }
  }

  WindowsPrinterQueueState _openPrinterFailureState(int errorCode) {
    if (errorCode == _errorInvalidPrinterName ||
        errorCode == _errorPrinterDeleted) {
      return WindowsPrinterQueueState.notFound;
    }
    if (errorCode == _rpcServerUnavailable ||
        errorCode == _rpcCallFailed ||
        errorCode == _errorSpoolerNotLoaded) {
      return WindowsPrinterQueueState.spoolerDown;
    }
    return WindowsPrinterQueueState.unknown;
  }

  WindowsPrinterQueueState _stateFromFlags({
    required int attributes,
    required int status,
    required bool workOffline,
  }) {
    if ((status & _printerStatusPaused) != 0) {
      return WindowsPrinterQueueState.paused;
    }
    if ((status &
            (_printerStatusOffline |
                _printerStatusNotAvailable |
                _printerStatusPendingDeletion |
                _printerStatusPaperJam |
                _printerStatusPaperOut |
                _printerStatusUserIntervention |
                _printerStatusOutOfMemory |
                _printerStatusDoorOpen)) !=
        0) {
      return WindowsPrinterQueueState.offline;
    }
    if ((status &
            (_printerStatusBusy |
                _printerStatusPrinting |
                _printerStatusIoActive |
                _printerStatusWaiting |
                _printerStatusProcessing |
                _printerStatusInitializing |
                _printerStatusWarmingUp |
                _printerStatusPowerSave)) !=
        0) {
      return WindowsPrinterQueueState.busy;
    }
    if ((status & (_printerStatusServerUnknown | _printerStatusError)) != 0 ||
        workOffline) {
      return WindowsPrinterQueueState.unknown;
    }
    return WindowsPrinterQueueState.ready;
  }

  String _friendlyMessageForState(WindowsPrinterQueueState state) {
    switch (state) {
      case WindowsPrinterQueueState.paused:
        return 'La cola de impresion esta pausada en Windows.';
      case WindowsPrinterQueueState.offline:
        return 'La impresora parece estar desconectada. Verifica que este encendida y conectada.';
      case WindowsPrinterQueueState.notFound:
        return 'La impresora configurada no esta disponible. Selecciona una impresora nuevamente.';
      case WindowsPrinterQueueState.spoolerDown:
        return 'El servicio de impresion de Windows no esta disponible.';
      case WindowsPrinterQueueState.unknown:
        return 'Windows no entrego el estado de la impresora. Se intentara imprimir.';
      case WindowsPrinterQueueState.busy:
        return 'La impresora esta ocupada. Windows pondra el trabajo en cola.';
      case WindowsPrinterQueueState.ready:
        return 'Cola de Windows disponible.';
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

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
