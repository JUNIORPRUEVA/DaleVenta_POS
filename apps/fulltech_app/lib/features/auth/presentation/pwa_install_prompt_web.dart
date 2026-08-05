import 'dart:js_interop';

@JS('fulltechPwaInstall')
external JSBoolean _fulltechPwaInstall();

bool requestPwaInstallPrompt() {
  try {
    return _fulltechPwaInstall().toDart;
  } catch (_) {
    return false;
  }
}
