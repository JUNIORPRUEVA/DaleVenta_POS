import 'dart:js_interop';

@JS('fullposCompleteWebStartup')
external void _completeWebStartup();

@JS('fullposFailWebStartup')
external void _failWebStartup();

@JS('fullposSetWebStartupStage')
external void _setWebStartupStage(JSString stage);

void setWebStartupStage(String stage) {
  try {
    _setWebStartupStage(stage.toJS);
  } catch (_) {
    // Older cached shells do not expose startup diagnostics.
  }
}

void failWebStartup() {
  try {
    _failWebStartup();
  } catch (_) {
    // Cached shells may not yet expose startup recovery.
  }
}

void completeWebStartup() {
  try {
    _completeWebStartup();
  } catch (_) {
    // Older cached shells remove their loader on the first Flutter frame.
  }
}
