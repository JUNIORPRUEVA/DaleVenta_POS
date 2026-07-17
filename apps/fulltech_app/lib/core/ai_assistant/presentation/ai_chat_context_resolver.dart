import 'package:flutter/foundation.dart';

import '../../routing/routes.dart';
import '../domain/models/ai_chat_context.dart';

AiChatContext buildAiChatContextFromLocation(String location) {
  final normalized = location.trim();
  final uri = Uri.tryParse(normalized) ?? Uri(path: normalized);
  final path = uri.path.trim().toLowerCase();
  final segments = uri.pathSegments
      .map((segment) => segment.trim().toLowerCase())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  var module = 'general';
  final screenName = _screenNameFromPath(path);
  String? entityType;
  String? entityId;

  if (path.startsWith('/clientes')) {
    module = 'clientes';
    if (segments.length >= 2 && segments[1] != 'nuevo') {
      entityType = 'client';
      entityId = segments[1];
    }
  } else if (path.startsWith('/service-orders')) {
    module = 'service-orders';
    if (segments.length >= 2 && segments[1] != 'nueva') {
      entityType = 'service-order';
      entityId = segments[1];
    }
  } else if (path.startsWith('/media-gallery')) {
    module = 'media-gallery';
  } else if (path.startsWith('/catalogo')) {
    module = 'catalogo';
  } else if (path.startsWith('/ventas')) {
    module = 'ventas';
  } else if (path.startsWith('/contabilidad')) {
    module = 'contabilidad';
  } else if (path.startsWith('/nomina') || path.startsWith('/mis-pagos')) {
    module = 'nomina';
  } else if (path.startsWith('/manual-interno')) {
    module = 'manual-interno';
  } else if (path.startsWith('/ia')) {
    module = 'general';
  } else if (path.startsWith('/configuracion')) {
    module = 'configuracion';
  } else if (path.startsWith('/administracion')) {
    module = 'administracion';
  } else if (path.startsWith('/cotizaciones')) {
    module = 'cotizaciones';
    final quoteId = (uri.queryParameters['quoteId'] ?? '').trim();
    final customerPhone = (uri.queryParameters['customerPhone'] ?? '').trim();
    if (quoteId.isNotEmpty) {
      entityType = 'quote';
      entityId = quoteId;
    } else if (customerPhone.isNotEmpty) {
      entityType = 'client-phone';
      entityId = customerPhone;
    }
  } else if (path.startsWith('/users')) {
    module = 'administracion';
    if (segments.length >= 2) {
      entityType = 'user';
      entityId = segments[1];
    }
  }

  return AiChatContext(
    module: module,
    route: uri.toString(),
    screenName: screenName,
    entityType: entityType,
    entityId: entityId,
  );
}

String? _screenNameFromPath(String path) {
  switch (path) {
    case Routes.profile:
      return 'Perfil';
    case Routes.catalogo:
      return 'Catálogo';
    case Routes.contabilidad:
      return 'Contabilidad';
    case Routes.contabilidadCierresDiarios:
      return 'Cierres diarios';
    case Routes.contabilidadDepositos:
      return 'Depósitos bancarios';
    case Routes.contabilidadFacturaFiscal:
      return 'Facturas fiscales';
    case Routes.contabilidadPagosPendientes:
      return 'Pagos pendientes';
    case Routes.clientes:
      return 'Clientes';
    case Routes.clienteNuevo:
      return 'Nuevo cliente';
    case Routes.ventas:
      return 'Ventas';
    case Routes.registrarVenta:
      return 'Registrar venta';
    case Routes.cotizaciones:
      return 'Cotizaciones';
    case Routes.cotizacionesHistorial:
      return 'Historial de cotizaciones';
    case Routes.serviceOrders:
      return 'Operaciones';
    case Routes.serviceOrderCreate:
      return 'Crear orden';
    case Routes.mediaGallery:
      return 'Galería media';
    case Routes.nomina:
      return 'Nómina';
    case Routes.misPagos:
      return 'Mis pagos';
    case Routes.manualInterno:
      return 'Manual interno';
    case Routes.ai:
      return 'IA';
    case Routes.configuracion:
      return 'Configuración';
    case Routes.administracion:
      return 'Administración';
    case Routes.users:
    case Routes.user:
      return 'Usuarios';
  }

  if (path.startsWith('/clientes/') && path.endsWith('/editar')) {
    return 'Editar cliente';
  }
  if (path.startsWith('/clientes/')) {
    return 'Detalle de cliente';
  }
  if (path == Routes.poncheHistorial) {
    return 'Historial de ponches';
  }
  if (path.startsWith('/service-orders/')) {
    return 'Detalle de orden';
  }
  if (path.startsWith('/users/')) {
    return 'Detalle de usuario';
  }

  if (!kReleaseMode) {
    // Keep generic but predictable in debug/dev.
    if (path.isEmpty) return null;
  }

  return null;
}
