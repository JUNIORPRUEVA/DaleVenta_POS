import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/manual_interno/company_manual_repository.dart';
import '../../modules/whatsapp/application/whatsapp_visibility_provider.dart';
import '../auth/app_permissions.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';

const double kDesktopShellBreakpoint = 1100;

class AppNavigationItem {
  const AppNavigationItem({
    required this.icon,
    required this.title,
    required this.route,
    this.showIndicator = false,
  });

  final IconData icon;
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
  WidgetRef ref,
  UserModel? currentUser,
) {
  final role = currentUser?.appRole;

  bool can(AppPermission permission) {
    if (role == null) return false;
    return hasPermission(role, permission);
  }

  final manualSummary = can(AppPermission.viewCompanyManual)
      ? ref.watch(companyManualSummaryProvider)
      : null;
  final showManualIndicator =
      manualSummary?.maybeWhen(
        data: (value) => value.unreadCount > 0,
        orElse: () => false,
      ) ??
      false;
  final showWhatsappEntry = can(AppPermission.viewWhatsapp)
      ? ref
            .watch(whatsappNavigationVisibilityProvider)
            .maybeWhen(
              data: (value) => value,
              orElse: () => role == null ? false : role == AppRole.admin,
            )
      : false;

  final sections = <AppNavigationSection>[
    AppNavigationSection(
      title: 'Principal',
      items: [
        if (can(AppPermission.viewOperations))
          const AppNavigationItem(
            icon: Icons.assignment_outlined,
            title: 'Operaciones',
            route: Routes.serviceOrders,
          ),
        if (can(AppPermission.viewMediaGallery))
          const AppNavigationItem(
            icon: Icons.perm_media_outlined,
            title: 'Galería media',
            route: Routes.mediaGallery,
          ),
        if (can(AppPermission.viewDocumentFlows))
          const AppNavigationItem(
            icon: Icons.verified_outlined,
            title: 'Flujo documental',
            route: Routes.documentFlows,
          ),
        if (can(AppPermission.viewClients))
          const AppNavigationItem(
            icon: Icons.group_outlined,
            title: 'Clientes',
            route: Routes.clientes,
          ),
        if (can(AppPermission.viewQuotes))
          const AppNavigationItem(
            icon: Icons.point_of_sale_outlined,
            title: 'Facturación',
            route: Routes.cotizaciones,
          ),
        if (can(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.receipt_long_outlined,
            title: 'Lista de ventas',
            route: Routes.ventasLista,
          ),
        if (can(AppPermission.viewPunch))
          const AppNavigationItem(
            icon: Icons.access_time_rounded,
            title: 'Ponche',
            route: Routes.ponche,
          ),
        if (can(AppPermission.viewCatalog))
          const AppNavigationItem(
            icon: Icons.inventory_2_outlined,
            title: 'Inventario',
            route: Routes.catalogo,
          ),
        if (can(AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.bar_chart_rounded,
            title: 'Reportes',
            route: Routes.ventas,
          ),
        if (can(AppPermission.viewAccounting))
          const AppNavigationItem(
            icon: Icons.account_balance,
            title: 'Contabilidad',
            route: Routes.contabilidad,
          ),
        if (can(AppPermission.viewAdminPanel))
          const AppNavigationItem(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Administración',
            route: Routes.administracion,
          ),
        if (can(AppPermission.viewPublicidad))
          const AppNavigationItem(
            icon: Icons.campaign_outlined,
            title: 'Publicidad',
            route: Routes.publicidad,
          ),
      ],
    ),
    AppNavigationSection(title: 'Administración', items: const []),
    AppNavigationSection(
      title: 'Nómina',
      items: [
        if (can(AppPermission.managePayroll))
          const AppNavigationItem(
            icon: Icons.payments_outlined,
            title: 'Nómina',
            route: Routes.nomina,
          ),
        if (can(AppPermission.viewOperations))
          const AppNavigationItem(
            icon: Icons.stacked_line_chart_rounded,
            title: 'Comisiones',
            route: Routes.serviceOrderCommissions,
          ),
        if (can(AppPermission.viewMyPayments))
          const AppNavigationItem(
            icon: Icons.receipt_long_outlined,
            title: 'Mis pagos',
            route: Routes.misPagos,
          ),
      ],
    ),
    AppNavigationSection(
      title: 'Cuenta',
      items: [
        const AppNavigationItem(
          icon: Icons.smart_toy_outlined,
          title: 'IA',
          route: Routes.ai,
        ),
        if (showWhatsappEntry)
          const AppNavigationItem(
            icon: Icons.chat_rounded,
            title: 'WhatsApp',
            route: Routes.whatsapp,
          ),
        if (can(AppPermission.viewWhatsappCrm))
          const AppNavigationItem(
            icon: Icons.support_agent_rounded,
            title: 'CRM WhatsApp',
            route: Routes.whatsappCrm,
          ),
        if (can(AppPermission.viewCrmComercial))
          const AppNavigationItem(
            icon: Icons.badge_outlined,
            title: 'CRM Comercial',
            route: Routes.crmComercial,
          ),
        if (can(AppPermission.viewWarnings))
          const AppNavigationItem(
            icon: Icons.warning_amber_rounded,
            title: 'Amonestaciones',
            route: Routes.amonestaciones,
          ),
        if (can(AppPermission.viewCompanyManual))
          AppNavigationItem(
            icon: Icons.menu_book_outlined,
            title: 'Manual Interno',
            route: Routes.manualInterno,
            showIndicator: showManualIndicator,
          ),
        if (can(AppPermission.manageUsers))
          const AppNavigationItem(
            icon: Icons.groups_outlined,
            title: 'Equipo',
            route: Routes.users,
          ),
        if (can(AppPermission.manageSettings))
          const AppNavigationItem(
            icon: Icons.settings_outlined,
            title: 'Configuración',
            route: Routes.configuracion,
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
  if (path == Routes.serviceOrders) return 'Operaciones';
  if (path == Routes.serviceOrderCommissions) return 'Comisiones';
  if (path == Routes.mediaGallery) return 'Galería media';
  if (path == Routes.serviceOrderCreate) return 'Crear orden';
  if (path == Routes.documentFlows) return 'Flujo documental';
  if (path == Routes.cotizacionesHistorial) return 'Historial de ventas';
  if (path == Routes.ventasLista) return 'Lista de ventas';
  if (path == Routes.clienteNuevo) return 'Nuevo cliente';
  if (path == Routes.ai) return 'IA';
  if (path == Routes.publicidad) return 'Publicidad';
  if (path == Routes.publicidadInvestigacion) {
    return 'Publicidad / Investigación';
  }
  if (path == Routes.publicidadEstados) return 'Publicidad / Estados';
  if (path == Routes.publicidadCampanas) return 'Publicidad / Campañas';
  if (path == Routes.publicidadMarketplace) return 'Publicidad / Marketplace';
  if (path == Routes.publicidadGaleria) {
    return 'Publicidad / Galería de Contenido';
  }
  if (path == Routes.galeriaPublicidad) return 'Galería de Publicidad';
  if (path == Routes.whatsappCrm) return 'CRM WhatsApp';
  if (path == Routes.crmComercial) return 'CRM Comercial';
  if (path == Routes.amonestaciones) return 'Amonestaciones';
  if (path == Routes.misAmonestacionesPendientes) {
    return 'Mis pendientes de firma';
  }
  if (path.startsWith('/amonestaciones/')) return 'Detalle amonestación';
  if (path == Routes.profile) return 'Perfil';
  if (path.startsWith('${Routes.serviceOrders}/')) return 'Detalle de orden';
  if (path.startsWith('${Routes.documentFlows}/')) return 'Detalle documental';
  if (path.startsWith('/clientes/') && path.endsWith('/editar')) {
    return 'Editar cliente';
  }
  if (path.startsWith('/clientes/')) return 'Detalle del cliente';
  if (path.startsWith('/users/')) return 'Detalle de usuario';

  final segments = path.split('/').where((part) => part.trim().isNotEmpty);
  if (segments.isEmpty) return 'FullTech';
  final last = segments.last.replaceAll('-', ' ');
  return last.isEmpty
      ? 'FullTech'
      : '${last[0].toUpperCase()}${last.substring(1)}';
}

bool desktopShellShouldShowOwnAppBar(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  const routesWithOwnAppBar = <String>[
    Routes.ponche,
    Routes.catalogo,
    Routes.contabilidad,
    Routes.clientes,
    Routes.ventas,
    Routes.ventasLista,
    Routes.serviceOrders,
    Routes.serviceOrderCommissions,
    Routes.mediaGallery,
    Routes.galeriaPublicidad,
    Routes.documentFlows,
    Routes.cotizaciones,
    Routes.nomina,
    Routes.misPagos,
    Routes.manualInterno,
    Routes.ai,
    Routes.configuracion,
    Routes.administracion,
    Routes.publicidad,
    Routes.users,
    Routes.profile,
  ];

  for (final route in routesWithOwnAppBar) {
    if (path == route || path.startsWith('$route/')) {
      return false;
    }
  }

  if (path == Routes.cotizacionesHistorial) return false;
  if (path == Routes.registrarVenta) return false;
  if (path == Routes.serviceOrderCreate) return false;
  if (path.startsWith('${Routes.documentFlows}/')) return false;
  if (path == Routes.clienteNuevo) return false;
  if (path.startsWith('${Routes.serviceOrders}/')) return false;
  if (path.startsWith('/clientes/')) return false;
  if (path.startsWith('/users/')) return false;

  return true;
}

String userInitials(UserModel? user) {
  final value = (user?.nombreCompleto ?? '').trim();
  if (value.isEmpty) return 'FT';
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'FT';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
