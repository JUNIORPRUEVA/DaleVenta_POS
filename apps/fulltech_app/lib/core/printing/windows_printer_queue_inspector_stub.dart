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
  const WindowsPrinterQueueInspector();

  Future<WindowsPrinterQueueStatus?> inspect(String printerName) async {
    return null;
  }
}
