import 'package:url_launcher/url_launcher.dart';

import 'dosa_assistant_config.dart';

/// Abre el asistente en un navegador externo.
///
/// Es la estrategia para Windows, Android e iOS en esta fase: no se añaden
/// WebViews nativos, y el usuario vuelve a FullPOS cuando termina.
///
/// La URL se valida ANTES de abrir nada: solo https y solo el origen oficial de
/// DOSA. Así una sesión manipulada no puede llevarse al usuario a otro sitio.
typedef DosaExternalOpener = Future<bool> Function(Uri uri);

Future<bool> openDosaAssistantExternally({
  required String sessionUrl,
  DosaExternalOpener? opener,
}) async {
  final uri = Uri.tryParse(sessionUrl.trim());
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  if ('https://${uri.host}' != DosaAssistantConfig.officialOrigin) return false;
  return (opener ?? _launchExternal)(uri);
}

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
