import 'dart:async';

class PrintActivityTracker {
  PrintActivityTracker._();

  static final PrintActivityTracker instance = PrintActivityTracker._();

  int _activeJobs = 0;

  bool get isPrinting => _activeJobs > 0;
  bool get hasPendingPrintJobs => isPrinting;

  void markPrintStarted() {
    _activeJobs += 1;
  }

  void markPrintCompleted() {
    if (_activeJobs > 0) _activeJobs -= 1;
  }

  Future<bool> waitUntilIdle(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (isPrinting && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return !isPrinting;
  }
}
