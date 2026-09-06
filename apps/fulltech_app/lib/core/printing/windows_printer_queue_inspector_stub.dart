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
  const WindowsPrinterQueueInspector();

  Future<WindowsPrinterQueueStatus?> inspect(String printerName) async {
    return null;
  }
}
