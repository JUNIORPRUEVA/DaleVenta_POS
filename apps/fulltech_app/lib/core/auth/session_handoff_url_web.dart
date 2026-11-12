import 'package:web/web.dart' as web;

/// Reescribe la URL actual sin recargar, quitando el ticket de handoff.
///
/// Se usa `replaceState` (no `pushState`) para no dejar el ticket en el
/// historial del navegador.
void replaceHistoryState(String path) {
  web.window.history.replaceState(null, '', path);
}
