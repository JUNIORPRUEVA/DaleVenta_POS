import 'package:web/web.dart' as web;

String clientWebInstallMode() {
  final displayModeStandalone = web.window
      .matchMedia('(display-mode: standalone)')
      .matches;
  return displayModeStandalone ? 'pwa' : 'web';
}
