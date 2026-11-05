import 'dosa_portal_navigation_stub.dart'
    if (dart.library.js_interop) 'dosa_portal_navigation_web.dart';

/// Navega a [url] **en la misma pestaña** del navegador.
///
/// Devuelve `false` en plataformas sin navegador integrado (Windows, Android,
/// iOS): allí el llamador usa el navegador del sistema.
Future<bool> navigateSameTab(String url) => navigateSameTabImpl(url);
