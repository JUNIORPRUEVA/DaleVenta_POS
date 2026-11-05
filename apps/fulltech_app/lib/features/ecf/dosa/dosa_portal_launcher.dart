import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import 'dosa_portal_navigation.dart';

/// Portal de certificación automática (DOSA) alojado en nuestro dominio.
///
/// El asistente oficial solo puede enmarcarse desde el origen autorizado por el
/// proveedor (`https://fullposcloud.fulltechrd.com`), así que la app **no**
/// monta el componente en local: abre este portal.
///
/// La autenticación no viaja como JWT en la URL: la app pide un **ticket de un
/// solo uso** (120 s) y el portal lo canjea en el servidor por una sesión. Si el
/// enlace se filtra, ya no sirve para nada.
const String defaultDosaPortalBaseUrl = 'https://fullposcloud.fulltechrd.com';

/// Ruta del portal dentro del dominio autorizado.
const String dosaPortalPath = '/ecf/certificacion/';

/// URL del portal con el ticket. Función pura: se prueba sin red.
String buildDosaPortalUrl({
  required String portalBaseUrl,
  required String ticket,
}) {
  final base = portalBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final value = Uri.encodeQueryComponent(ticket.trim());
  return '$base$dosaPortalPath?ticket=$value';
}

/// Base del portal configurada en el build.
String dosaPortalBaseUrlFromEnvironment() {
  const configured = String.fromEnvironment('FULLPOS_PORTAL_URL');
  final value = configured.trim();
  return value.isEmpty ? defaultDosaPortalBaseUrl : value;
}

class DosaPortalTicket {
  const DosaPortalTicket({required this.url, required this.expiresAt});

  final String url;
  final String expiresAt;
}

class DosaPortalException implements Exception {
  DosaPortalException(this.message);
  final String message;

  @override
  String toString() => 'DosaPortalException($message)';
}

/// Pide el ticket al backend y devuelve la URL lista para abrir.
class DosaPortalApi {
  DosaPortalApi(this._dio, {String? portalBaseUrl})
    : _portalBaseUrl = portalBaseUrl ?? dosaPortalBaseUrlFromEnvironment();

  final Dio _dio;
  final String _portalBaseUrl;

  /// ¿Puede esta empresa PREPARAR su certificación?
  ///
  /// Consulta de solo lectura que el backend responde cerrada por defecto: sin
  /// piloto configurado, sin permiso o con cualquier error, la respuesta es
  /// `false`. Nunca crea ticket ni sesión de DOSA.
  Future<bool> isEligible() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        ApiRoutes.ecfCertificationPortalEligibility,
      );
      return (res.data ?? const <String, dynamic>{})['eligible'] == true;
    } on DioException {
      return false;
    }
  }

  Future<DosaPortalTicket> requestTicket() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.ecfCertificationPortalTickets,
      );
      final data = res.data ?? const <String, dynamic>{};
      final ticket = '${data['ticket'] ?? ''}'.trim();
      if (ticket.isEmpty) {
        throw DosaPortalException(
          'El servidor no devolvió un enlace de acceso al portal.',
        );
      }
      return DosaPortalTicket(
        url: buildDosaPortalUrl(portalBaseUrl: _portalBaseUrl, ticket: ticket),
        expiresAt: '${data['expiresAt'] ?? ''}',
      );
    } on DioException catch (error) {
      throw DosaPortalException(_messageFor(error));
    }
  }

  static String _messageFor(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final code = data is Map ? '${data['message'] ?? ''}' : '';

    if (code.contains('PORTAL_PILOT')) {
      return 'El portal de certificación está en fase piloto y tu empresa '
          'todavía no está incluida.';
    }
    if (code.contains('PORTAL_INTENTION_')) {
      return 'Revisa el intento de certificación existente antes de abrir '
          'el portal. Contacta con un administrador de FullPOS.';
    }
    if (status == 401) {
      return 'Tu sesión no permite abrir el portal de certificación. '
          'Vuelve a iniciar sesión como administrador.';
    }
    if (status == 403) {
      return 'Tu usuario no tiene permiso para preparar la certificación '
          'de esta empresa.';
    }
    if (status == 404) {
      return 'El portal de certificación no está disponible en este servidor.';
    }
    return 'No se pudo preparar el acceso al portal. Inténtalo de nuevo.';
  }
}

/// Abre el portal de certificación.
///
/// En Web navega en la **misma pestaña** (`sameTab: true`), que es el recorrido
/// pedido: un solo clic en «Continuar con el asistente» y el portal ocupa la
/// pestaña actual, sin `window.open` ni ventanas nuevas. En Windows, Android e
/// iOS no hay pestañas: se usa el navegador del sistema, porque el componente
/// necesita el origen autorizado y no un WebView con contenido local.
Future<bool> openDosaPortal(String url, {bool sameTab = false}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  if (sameTab && kIsWeb) {
    return navigateSameTab(url);
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

final dosaPortalApiProvider = Provider<DosaPortalApi>((ref) {
  return DosaPortalApi(ref.watch(dioProvider));
});

/// Elegibilidad del piloto para ESTA empresa, consultada al backend.
///
/// Se apoya en la sesión: sin usuario autenticado no se pregunta nada y la
/// respuesta es `false`. Mientras carga, o si falla, también `false`: la
/// entrada de e-CF nunca aparece por un error de red.
///
/// NO se usa para pintar el menú: el Drawer y el shell leen
/// `CompanySettings.ecfPilotEligible`, que el backend sirve junto con el resto
/// de la configuración. Consultar esta sonda desde un `build` provocaba una
/// petición por cada reconstrucción del menú. Se conserva para diagnósticos y
/// para la propia pantalla del portal.
final dosaPortalEligibilityProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      final auth = ref.watch(authStateProvider);
      if (!auth.isAuthenticated) return false;
      return ref.watch(dosaPortalApiProvider).isEligible();
    });
