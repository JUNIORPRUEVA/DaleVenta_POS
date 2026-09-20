import 'dart:js_interop';

@JS('fulltechPwaInstall')
external JSBoolean _fulltechPwaInstall();

@JS('fulltechPwaBannerVisible')
external JSBoolean _fulltechPwaBannerVisible();

bool requestPwaInstallPrompt() {
  try {
    return _fulltechPwaInstall().toDart;
  } catch (_) {
    return false;
  }
}

/// True while the native PWA install banner (a DOM overlay outside the Flutter
/// canvas) is visible at the bottom of the viewport.
bool pwaInstallBannerVisible() {
  try {
    return _fulltechPwaBannerVisible().toDart;
  } catch (_) {
    return false;
  }
}
