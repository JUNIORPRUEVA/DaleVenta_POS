import 'package:web/web.dart' as web;

/// Implementación Web: navega en la **misma pestaña**, sin `window.open` ni
/// `_blank`. La app se sustituye por el portal, que es exactamente lo que pide
/// el recorrido (un solo gesto, sin ventanas nuevas).
Future<bool> navigateSameTabImpl(String url) async {
  web.window.location.assign(url);
  return true;
}
