import 'dart:js_interop';

@JS('fullposCompleteWebStartup')
external void _completeWebStartup();

void completeWebStartup() {
  try {
    _completeWebStartup();
  } catch (_) {
    // Older cached shells remove their loader on the first Flutter frame.
  }
}
