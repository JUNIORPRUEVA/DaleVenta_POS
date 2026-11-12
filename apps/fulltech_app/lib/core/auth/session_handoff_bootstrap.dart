import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'session_handoff_url_stub.dart'
    if (dart.library.js_interop) 'session_handoff_url_web.dart';

/// Handoff de sesión sitio web (Astro) → app Flutter Web.
///
/// El sitio autentica al usuario contra el API y, al terminar la bienvenida,
/// pide un ticket de un solo uso y abre la app con `?handoff=<ticket>`.
///
/// Reglas de seguridad que respeta este lado:
/// - El ticket no es un token: se canjea UNA vez y el backend responde con una
///   sesión ya rotada, así que aquí nunca se guardan credenciales de la URL.
/// - El parámetro se elimina de la barra de direcciones antes de canjearlo,
///   para que no quede en el historial ni se comparta al copiar el enlace.
/// - Si algo falla, se ignora en silencio: el usuario cae en el login normal y
///   puede entrar con su correo y contraseña. Nunca se muestra media sesión.
class SessionHandoffBootstrap {
  static const String _queryKey = 'handoff';

  /// Debe ejecutarse ANTES de `runApp`, para que el `AuthState` inicial ya
  /// encuentre los tokens guardados y no se pida la contraseña otra vez.
  static Future<void> consumeFromUrl() async {
    if (!kIsWeb) return;

    final ticket = _readTicket();
    if (ticket == null) return;

    _stripTicketFromUrl();

    final container = ProviderContainer();
    try {
      await container
          .read(authRepositoryProvider)
          .exchangeHandoffTicket(ticket);
    } catch (error) {
      // Silencioso por diseño: sin sesión de handoff se sigue en el login.
      debugPrint('SESSION_HANDOFF exchange failed: $error');
    } finally {
      container.dispose();
    }
  }

  static String? _readTicket() {
    try {
      final value = Uri.base.queryParameters[_queryKey];
      final ticket = (value ?? '').trim();
      return ticket.isEmpty ? null : ticket;
    } catch (_) {
      return null;
    }
  }

  /// Reescribe la URL actual sin el ticket, conservando ruta y demás parámetros.
  static void _stripTicketFromUrl() {
    try {
      final base = Uri.base;
      if (!base.queryParameters.containsKey(_queryKey)) return;

      final kept = Map<String, String>.from(base.queryParameters)
        ..remove(_queryKey);
      final cleaned = base.replace(queryParameters: kept.isEmpty ? null : kept);

      final path =
          '${cleaned.path}${cleaned.hasQuery ? '?${cleaned.query}' : ''}';
      replaceHistoryState(path);
    } catch (_) {
      // Si el navegador no permite reescribir el historial, el canje sigue:
      // el ticket es de un solo uso y queda inutilizable igualmente.
    }
  }
}
