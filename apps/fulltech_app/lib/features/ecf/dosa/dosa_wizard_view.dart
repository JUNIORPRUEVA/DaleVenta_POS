/// Selección del contenedor del componente según la plataforma.
///
/// En Web/PWA se monta el Web Component real `<dosa-cert-wizard>`. En Windows,
/// Android e iOS la implementación es un stub: el asistente se abre en un
/// navegador externo seguro (ver `dosa_assistant_launcher.dart`), sin añadir un
/// WebView nativo en esta fase.
library;

export 'dosa_wizard_view_stub.dart'
    if (dart.library.js_interop) 'dosa_wizard_view_web.dart';
