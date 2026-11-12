import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/app_permissions.dart';
import '../design_system/icons/app_icons.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';

const double kDesktopShellBreakpoint = 1100;

class AppNavigationItem {
  const AppNavigationItem({
    required this.icon,
    required this.title,
    required this.route,
    this.appIcon,
    this.showIndicator = false,
    this.enabled = true,
  });

  final IconData icon;
  final AppIconData? appIcon;
  final String title;
  final String route;
  final bool showIndicator;

  /// `false` para ítems meramente informativos/deshabilitados (p. ej. estado
  /// de turno no sincronizado): se renderizan atenuados y no ejecutan acción.
  final bool enabled;
}

class AppNavigationSection {
  const AppNavigationSection({required this.title, required this.items});

  final String title;
  final List<AppNavigationItem> items;
}

/// Construye las secciones de navegación.
///
/// Función PURA: no recibe `WidgetRef` ni ejecuta `ref.watch`/`ref.read`.
/// El estado del que depende (por ahora `multiWarehouseEnabled`) debe ser
/// observado declarativamente por el widget (una sola vez, dentro de su
/// `build`) y llegar aquí ya resuelto.
///
/// Esto evita que un helper invocado en medio del build provoque lecturas de
/// providers con efectos colaterales (Riverpod reconstruye un provider
/// invalidado sincrónicamente y notifica listeners durante el build →
/// `setState() or markNeedsBuild() called during build`).
List<AppNavigationSection> buildAppNavigationSections(
  UserModel? currentUser, {
  required bool multiWarehouseEnabled,
  bool wholesalePriceListsEnabled = false,
  // Interruptor e-CF de la EMPRESA. Es la única compuerta de visibilidad del
  // módulo: apagado significa que la empresa no ha solicitado facturación
  // electrónica y el menú queda exactamente como un POS tradicional.
  bool ecfEnabled = false,

  /// Piloto de certificación: el backend confirmó que ESTA empresa puede
  /// preparar su certificación aunque la emisión siga desactivada. Ya incluye
  /// la comprobación de permiso, así que aquí no se vuelve a evaluar.
  bool ecfPilotEligible = false,
}) {
  bool canOrAuthorize(AppPermission _) {
    if (currentUser == null) return false;
    return true;
  }

  final resolvedMultiWarehouseEnabled = multiWarehouseEnabled;
  final resolvedWholesalePriceListsEnabled = wholesalePriceListsEnabled;

  final sections = <AppNavigationSection>[
    AppNavigationSection(
      title: 'Principal',
      items: [
        if (canOrAuthorize(AppPermission.viewClients))
          const AppNavigationItem(
            icon: Icons.group_outlined,
            appIcon: AppIcons.customer,
            title: 'Clientes',
            route: Routes.clientes,
          ),
        if (canOrAuthorize(AppPermission.viewQuotes))
          const AppNavigationItem(
            icon: Icons.point_of_sale_outlined,
            appIcon: AppIcons.sales,
            title: 'Facturación',
            route: Routes.cotizaciones,
          ),
        if (canOrAuthorize(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.receipt_long_outlined,
            appIcon: AppIcons.receipt,
            title: 'Lista de ventas',
            route: Routes.ventasLista,
          ),
        if (canOrAuthorize(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.credit_score_outlined,
            appIcon: AppIcons.payment,
            title: 'Créditos',
            route: Routes.ventasCreditos,
          ),
        if (canOrAuthorize(AppPermission.viewCatalog))
          const AppNavigationItem(
            icon: Icons.inventory_2_outlined,
            appIcon: AppIcons.inventory,
            title: 'Productos',
            route: Routes.catalogo,
          ),
        if (canOrAuthorize(AppPermission.viewCatalog))
          const AppNavigationItem(
            icon: Icons.tune_outlined,
            appIcon: AppIcons.inventory,
            title: 'Ajuste stock',
            route: Routes.catalogoStock,
          ),
        if (canOrAuthorize(AppPermission.viewCatalog))
          const AppNavigationItem(
            icon: Icons.category_outlined,
            appIcon: AppIcons.inventory,
            title: 'Categorías',
            route: Routes.catalogoCategorias,
          ),
        if (canOrAuthorize(AppPermission.viewCatalog))
          const AppNavigationItem(
            icon: Icons.fact_check_outlined,
            appIcon: AppIcons.inventory,
            title: 'Recuento',
            route: Routes.catalogoConteo,
          ),
        if (resolvedMultiWarehouseEnabled &&
            canOrAuthorize(AppPermission.viewInventoryHistory))
          const AppNavigationItem(
            icon: Icons.history_rounded,
            appIcon: AppIcons.inventory,
            title: 'Kardex',
            route: Routes.catalogoKardex,
          ),
        if (resolvedWholesalePriceListsEnabled &&
            canOrAuthorize(AppPermission.managePriceLists))
          const AppNavigationItem(
            icon: Icons.price_change_outlined,
            appIcon: AppIcons.inventory,
            title: 'Listas precios',
            route: Routes.listasPrecios,
          ),
        if (resolvedMultiWarehouseEnabled &&
            canOrAuthorize(AppPermission.manageWarehouses))
          const AppNavigationItem(
            icon: Icons.warehouse_outlined,
            appIcon: AppIcons.inventory,
            title: 'Almacenes',
            route: Routes.configuracionAlmacenes,
          ),
        if (canOrAuthorize(AppPermission.viewPurchases))
          const AppNavigationItem(
            icon: Icons.shopping_cart_checkout_outlined,
            appIcon: AppIcons.purchase,
            title: 'Compras',
            route: Routes.compras,
          ),
        if (canOrAuthorize(AppPermission.viewSalesReports))
          const AppNavigationItem(
            icon: Icons.bar_chart_rounded,
            appIcon: AppIcons.report,
            title: 'Reportes',
            route: Routes.ventas,
          ),
        // MÓDULO CONTABILIDAD OCULTO DE LA NAVEGACIÓN.
        //
        // Decisión de producto (simplificación del menú): el grupo
        // «Contabilidad» y sus cuatro accesos (Depósitos, Factura fiscal,
        // Pagos y Nómina) ya no se dibujan en ninguna plataforma.
        //
        // Lo que NO cambia:
        // - Las rutas siguen registradas en `app_router.dart` y protegidas por
        //   `route_access.dart` con los mismos permisos.
        // - Las pantallas, repositorios, providers y endpoints siguen igual.
        // - NCF tradicional (`NcfService`, `reserveNextNcf`, `/ncf/sequences`,
        //   `ncf_sequences`, `ncf_audit_logs`, `Sale.ncf`) y facturación
        //   electrónica e-CF no se tocan en absoluto.
        //
        // Como estos ítems ya no entran en `sections`, tampoco pueden reaparecer
        // en los grupos comodín («Otros» del sidebar, «Más módulos» del drawer),
        // que se alimentan de lo que queda sin asignar.
      ],
    ),
    AppNavigationSection(
      title: 'Cuenta',
      items: [
        if (canOrAuthorize(AppPermission.manageUsers))
          const AppNavigationItem(
            icon: Icons.groups_outlined,
            appIcon: AppIcons.users,
            title: 'Usuario',
            route: Routes.users,
          ),
        // La facturación electrónica es OPCIONAL por empresa: la entrada del
        // menú solo existe cuando la empresa la ha activado explícitamente en
        // Configuración → Empresa → Impuestos y e-CF. Un cliente que no la ha
        // solicitado conserva su POS tradicional y no ve nada de e-CF.
        //
        // Mientras la configuración de empresa no esté confirmada el valor es
        // `false`, así que un fallo de red nunca deja el módulo a la vista.
        // Activar el módulo NO autoriza emisión real: eso sigue detrás de las
        // compuertas fiscales del backend.
        if ((ecfEnabled && canOrAuthorize(AppPermission.viewEcfDocuments)) ||
            ecfPilotEligible)
          const AppNavigationItem(
            icon: Icons.receipt_long_outlined,
            appIcon: AppIcons.receipt,
            title: 'Facturación electrónica',
            route: Routes.ecf,
          ),
      ],
    ),
  ];

  return sections.where((section) => section.items.isNotEmpty).toList();
}

String safeCurrentLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    try {
      return GoRouter.of(
        context,
      ).routerDelegate.currentConfiguration.uri.toString();
    } catch (_) {
      final routeName = ModalRoute.of(context)?.settings.name;
      return routeName ?? '';
    }
  }
}

bool isNavigationRouteActive(String location, String route) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (route == Routes.ventas) {
    return path == Routes.ventas;
  }
  if (route == Routes.ventasLista) {
    return path == Routes.ventasLista;
  }
  if (route == Routes.caja) {
    return path == Routes.caja;
  }
  if (route == Routes.serviceOrderCommissions) {
    return location == Routes.serviceOrderCommissions;
  }
  if (route == Routes.serviceOrders) {
    return location == Routes.serviceOrders ||
        location == Routes.serviceOrderCreate ||
        (location.startsWith('${Routes.serviceOrders}/') &&
            location != Routes.serviceOrderCommissions);
  }
  return location == route || location.startsWith('$route/');
}

String resolveNavigationTitle(
  String location,
  List<AppNavigationSection> sections,
) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path == Routes.poncheHistorial) return 'Historial de ponches';
  // Nivel dentro del módulo e-CF: el título del módulo no explica qué se está
  // editando, y el botón de volver regresa a la puesta en marcha.
  if (path == Routes.ecfFiscalData) return 'Datos fiscales';
  if (path == Routes.ecfDocuments) return 'Comprobantes electrónicos';
  if (path == Routes.ecfConfig) return 'Estado del módulo e-CF';
  if (path == Routes.ecfDgii) return 'Habilitación DGII';

  // Las pantallas del módulo Contabilidad ya no forman parte de `sections`
  // (grupo oculto de la navegación), pero siguen siendo accesibles por ruta.
  // Sin estas líneas el título del shell degradaría al último segmento de la
  // URL («depositos-bancarios», «pagos-pendientes»…).
  if (path == Routes.contabilidad) return 'Contabilidad';
  if (path == Routes.contabilidadCierresDiarios) return 'Cierres diarios';
  if (path == Routes.contabilidadDepositos) return 'Depósitos';
  if (path == Routes.contabilidadFacturaFiscal) return 'Factura fiscal';
  if (path == Routes.contabilidadPagosPendientes) return 'Pagos';
  if (path == Routes.nomina) return 'Nómina';

  for (final section in sections) {
    for (final item in section.items) {
      if (isNavigationRouteActive(location, item.route)) {
        return item.title;
      }
    }
  }

  if (path == Routes.registrarVenta) return 'Nueva venta';
  if (path == Routes.cotizacionesHistorial) return 'Cotizaciones';
  if (path == Routes.catalogoStock) return 'Stock';
  if (path == Routes.catalogoCategorias) return 'Categorías';
  if (path == Routes.catalogoConteo) return 'Conteo de stock';
  if (path == Routes.ventasLista) return 'Lista de ventas';
  if (path == Routes.compras) return 'Compras';
  if (path == Routes.comprasLista) return 'Lista de compras';
  if (path == Routes.comprasSuplidores) return 'Suplidores';
  if (path == Routes.comprasFacturas) return 'Facturas';
  if (path == Routes.comprasPorComprar) return 'Productos por comprar';
  if (path == Routes.caja) return 'Movimiento caja';
  if (path == Routes.cajaMovimientos) return 'Historial de efectivo';
  if (path == Routes.cajaRegistrarGasto) return 'Registrar gasto';
  if (path == Routes.cajaGastosHistorial) return 'Historial de gastos';
  if (path == Routes.cajaTurnosHistorial) return 'Historial de turnos';
  if (path == Routes.clienteNuevo) return 'Nuevo cliente';
  if (path == Routes.ai) return 'IA';
  if (path == Routes.profile) return 'Perfil';
  if (path.startsWith('/clientes/') && path.endsWith('/editar')) {
    return 'Editar cliente';
  }
  if (path.startsWith('/clientes/')) return 'Detalle del cliente';
  if (path.startsWith('/users/')) return 'Detalle de usuario';

  final segments = path.split('/').where((part) => part.trim().isNotEmpty);
  if (segments.isEmpty) return 'FullPOS Cloud';
  final last = segments.last.replaceAll('-', ' ');
  return last.isEmpty
      ? 'FullPOS Cloud'
      : '${last[0].toUpperCase()}${last.substring(1)}';
}

bool desktopShellShouldShowOwnAppBar(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  const routesWithOwnAppBar = <String>[
    Routes.catalogo,
    Routes.catalogoStock,
    Routes.catalogoCategorias,
    Routes.catalogoConteo,
    Routes.contabilidad,
    Routes.clientes,
    Routes.ventas,
    Routes.ventasLista,
    Routes.ventasCreditos,
    Routes.compras,
    Routes.caja,
    Routes.cotizaciones,
    Routes.nomina,
    Routes.misPagos,
    Routes.ai,
    Routes.users,
    Routes.profile,
    Routes.configuracion,
    Routes.configuracionEmpresa,
    Routes.configuracionImpresora,
    Routes.configuracionParametros,
    Routes.configuracionDocumentos,
    Routes.configuracionAlmacenes,
  ];

  for (final route in routesWithOwnAppBar) {
    if (path == route || path.startsWith('$route/')) {
      return false;
    }
  }

  if (path == Routes.cotizacionesHistorial) return false;
  if (path == Routes.registrarVenta) return false;
  if (path == Routes.clienteNuevo) return false;
  if (path.startsWith('/clientes/')) return false;
  if (path.startsWith('/users/')) return false;

  return true;
}

String userInitials(UserModel? user) {
  final value = (user?.nombreCompleto ?? '').trim();
  if (value.isEmpty) return 'DV';
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'DV';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
