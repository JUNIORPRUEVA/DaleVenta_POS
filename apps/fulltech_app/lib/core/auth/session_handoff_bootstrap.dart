import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'operation_scope.dart';
import 'session_handoff_attempt.dart';
import 'token_storage.dart';
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
/// - Si falla, main abre el acceso público con un aviso y no inicia una sesión
///   parcial ni regresa silenciosamente a la portada.
class SessionHandoffBootstrap {
  static const String _queryKey = 'handoff';

  /// Debe ejecutarse ANTES de `runApp`, para que el `AuthState` inicial ya
  /// encuentre los tokens guardados y no se pida la contraseña otra vez.
  static Future<bool> consumeFromUrl() async {
    if (!kIsWeb) return true;

    final ticket = _readTicket();
    if (ticket == null) return true;

    final container = ProviderContainer();
    try {
      String? expectedUser;
      String? expectedCompany;
      return await completeSessionHandoff(
        stripTicket: _stripTicketFromUrl,
        clearSession: container.read(tokenStorageProvider).clearTokens,
        exchange: () async {
          final user = await container.read(authRepositoryProvider).exchangeHandoffTicket(ticket);
          expectedUser = user.id;
          expectedCompany = user.companyId;
        },
        sessionIsStored: () async {
          final storage = TokenStorage();
          final access = await storage.getAccessToken();
          final user = await storage.getUserSnapshot();
          return access != null && user != null &&
            user.id == expectedUser && user.companyId == expectedCompany &&
            (expectedCompany ?? '').isNotEmpty &&
            OperationScope(expectedCompany!, expectedUser!).matchesToken(access);
        },
      );
    } finally {
      container.dispose();
    }
  }

  static void openRecoveryLogin() => navigateToAccessRecovery();

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

      replaceHistoryState(sessionHandoffCleanPath(base));
    } catch (_) {
      // Si el navegador no permite reescribir el historial, el canje sigue:
      // el ticket es de un solo uso y queda inutilizable igualmente.
    }
  }
}
