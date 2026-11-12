import 'package:flutter/services.dart';

import '../../../core/support/support_config.dart';
import '../../../core/utils/safe_url_launcher.dart';

/// Resultado de intentar abrir WhatsApp con un mensaje preparado.
class AssistantLaunchResult {
  const AssistantLaunchResult({required this.opened, required this.copied});

  /// `true` si el sistema reportó que se pudo abrir la app o el navegador.
  final bool opened;

  /// `true` si el mensaje quedó en el portapapeles como respaldo.
  final bool copied;
}

/// Servicio único para abrir WhatsApp desde el Asistente.
///
/// - No usa WhatsApp Business API ni credenciales de Meta.
/// - No envía nada automáticamente: solo abre la app/navegador con el texto
///   preparado para que el usuario decida enviarlo.
/// - Si el dispositivo no puede abrir enlaces, copia el mensaje al portapapeles
///   y lo informa, sin perder lo que el usuario escribió.
class AssistantWhatsAppService {
  const AssistantWhatsAppService._();

  static Uri buildUri(String message) => SupportConfig.whatsappUri(message);

  static Future<AssistantLaunchResult> send(String message) async {
    final uri = buildUri(message);
    final opened = await tryOpenUrl(uri);
    if (opened) {
      return const AssistantLaunchResult(opened: true, copied: false);
    }
    final copied = await _copy(message);
    return AssistantLaunchResult(opened: false, copied: copied);
  }

  /// Copia un texto al portapapeles. Devuelve `false` si el sistema lo impide.
  static Future<bool> copyText(String text) => _copy(text);

  static Future<bool> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
