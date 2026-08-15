import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final IconData icon;
  final AppIconData? appIcon;
  final String title;
  final String route;
  final bool showIndicator;
}

class AppNavigationSection {
  const AppNavigationSection({required this.title, required this.items});

  final String title;
  final List<AppNavigationItem> items;
}

List<AppNavigationSection> buildAppNavigationSections(
  WidgetRef _,
  UserModel? currentUser,
) {
  bool canOrAuthorize(AppPermission _) {
    if (currentUser == null) return false;
    return true;
  }

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
            icon: Icons.add_circle_outline_rounded,
            appIcon: AppIcons.income,
            title: 'Registrar entrada',
            route: Routes.cajaRegistrarIngreso,
          ),
        if (canOrAuthorize(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.remove_circle_outline_rounded,
            appIcon: AppIcons.expense,
            title: 'Registrar salida',
            route: Routes.cajaRegistrarSalida,
          ),
        if (canOrAuthorize(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.history_rounded,
            appIcon: AppIcons.shift,
            title: 'Historial',
            route: Routes.cajaMovimientos,
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
            title: 'Inventario',
            route: Routes.catalogo,
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
        if (canOrAuthorize(AppPermission.viewAccounting))
          const AppNavigationItem(
            icon: Icons.fact_check_outlined,
            appIcon: AppIcons.receipt,
            title: 'Factura fiscal',
            route: Routes.contabilidadFacturaFiscal,
          ),
      ],
    ),
    AppNavigationSection(
      title: 'Contabilidad',
      items: [
        if (canOrAuthorize(AppPermission.viewAccounting))
          const AppNavigationItem(
            icon: Icons.account_balance_outlined,
            appIcon: AppIcons.company,
            title: 'Depósitos',
            route: Routes.contabilidadDepositos,
          ),
        if (canOrAuthorize(AppPermission.viewAccounting))
          const AppNavigationItem(
            icon: Icons.account_balance_wallet_outlined,
            appIcon: AppIcons.payment,
            title: 'Pagos',
            route: Routes.contabilidadPagosPendientes,
          ),
        if (canOrAuthorize(AppPermission.managePayroll))
          const AppNavigationItem(
            icon: Icons.payments_outlined,
            appIcon: AppIcons.payment,
            title: 'Nómina',
            route: Routes.nomina,
          ),
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
    Routes.configuracionBackup,
    Routes.configuracionParametros,
    Routes.configuracionDocumentos,
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
