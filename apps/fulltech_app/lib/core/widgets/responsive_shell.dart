import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/cash/cash_dialogs.dart';
import '../../modules/cash/cash_providers.dart';
import '../auth/app_role.dart';
import '../auth/auth_provider.dart';
import '../location/location_tracker_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import '../theme/role_branding.dart';
import '../utils/date_time_formatters.dart';
import 'app_drawer.dart';
import 'app_navigation.dart';
import 'user_avatar.dart';

BoxDecoration _desktopSurfaceDecoration(ThemeData theme) {
  return BoxDecoration(
    color: const Color(0xFFEFF5F8),
    borderRadius: BorderRadius.circular(0),
    border: Border.all(color: const Color(0xFFD3E0E7)),
  );
}

class DesktopShellActionItem {
  const DesktopShellActionItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selectedIcon,
    this.selected = false,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;
}

class DesktopShellRouteActions {
  const DesktopShellRouteActions({required this.route, required this.actions});

  final String route;
  final List<DesktopShellActionItem> actions;
}

final desktopShellRouteActionsProvider =
    StateProvider<DesktopShellRouteActions?>((ref) => null);

class DesktopShellFooterContent {
  const DesktopShellFooterContent({required this.route, required this.builder});

  final String route;
  final WidgetBuilder builder;
}

final desktopShellFooterContentProvider =
    StateProvider<DesktopShellFooterContent?>((ref) => null);

class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  final _shellScaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    ref.watch(locationTrackingBootstrapProvider);

    final media = MediaQuery.sizeOf(context);
    if (media.width < kDesktopShellBreakpoint) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    final sections = buildAppNavigationSections(ref, user);
    final location = safeCurrentLocation(context);
    final title = resolveNavigationTitle(location, sections);
    final showShellAppBar = desktopShellShouldShowOwnAppBar(location);
    final routeActions = ref.watch(desktopShellRouteActionsProvider);
    final shellActions = routeActions?.route == location
        ? routeActions!.actions
        : const <DesktopShellActionItem>[];
    final customFooter = ref.watch(desktopShellFooterContentProvider);
    final footerBuilder = customFooter?.route == location
        ? customFooter!.builder
        : null;

    return Scaffold(
      key: _shellScaffoldKey,
      backgroundColor: Colors.transparent,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              left: 0,
              child: Column(
                children: [
                  if (showShellAppBar)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: DesktopShellAppBar(
                        collapsed: true,
                        title: title,
                        currentUser: user,
                        onToggleSidebar: () =>
                            _shellScaffoldKey.currentState?.openDrawer(),
                        extraActions: shellActions,
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: DecoratedBox(
                          decoration: _desktopSurfaceDecoration(theme),
                          child: Theme(
                            data: theme.copyWith(
                              scaffoldBackgroundColor: Colors.transparent,
                            ),
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  footerBuilder == null
                      ? const DesktopShellFooter()
                      : footerBuilder(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopShellFooter extends ConsumerWidget {
  const DesktopShellFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 15),
        (_) => DateTime.now(),
      ),
      initialData: now,
      builder: (context, snapshot) {
        final dateTime = snapshot.data ?? DateTime.now();
        final timeText = formatRdTime(dateTime);

        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFC),
            border: Border(top: BorderSide(color: const Color(0xFFD6E1E8))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '© 2026 DaleVenta POS — Todos los derechos reservados',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF183548),
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                timeText,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF183548),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DesktopShellAppBar extends ConsumerWidget {
  const DesktopShellAppBar({
    super.key,
    required this.collapsed,
    required this.title,
    required this.currentUser,
    required this.onToggleSidebar,
    this.extraActions = const <DesktopShellActionItem>[],
  });

  final bool collapsed;
  final String title;
  final UserModel? currentUser;
  final VoidCallback onToggleSidebar;
  final List<DesktopShellActionItem> extraActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photoUrl = (currentUser?.fotoPersonalUrl ?? '').trim();
    final branding = resolveRoleBranding(
      currentUser?.appRole ?? AppRole.unknown,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: kToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final showRangeBadge =
              !collapsed && availableWidth >= 1120 && extraActions.isEmpty;
          final showUserMeta = !collapsed && availableWidth >= 860;

          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCFE0FF)),
                ),
                child: IconButton(
                  tooltip: 'Menú',
                  onPressed: onToggleSidebar,
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: Color(0xFF1957E6),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    if (showUserMeta) const SizedBox(height: 2),
                    if (showUserMeta)
                      Text(
                        branding.departmentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (showRangeBadge) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFCFE0FF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xFF1957E6),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1957E6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (extraActions.isNotEmpty) ...[
                const SizedBox(width: 10),
                _DesktopShellActionGroup(actions: extraActions),
              ],
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: showUserMeta ? 260 : 56),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 8 : 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFCFE0FF)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        radius: 15,
                        backgroundColor: Colors.white,
                        imageUrl: photoUrl,
                        child: Text(
                          userInitials(currentUser),
                          style: const TextStyle(
                            color: Color(0xFF1957E6),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showUserMeta) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                (currentUser?.nombreCompleto ?? 'Usuario')
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              Text(
                                branding.departmentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopShellActionGroup extends StatelessWidget {
  const _DesktopShellActionGroup({required this.actions});

  final List<DesktopShellActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            Tooltip(
              message: action.tooltip,
              child: InkWell(
                onTap: action.onPressed,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: action.selected
                        ? Colors.white.withValues(alpha: 0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    action.selected
                        ? action.selectedIcon ?? action.icon
                        : action.icon,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarMenuGroup {
  const _SidebarMenuGroup({
    required this.key,
    required this.title,
    required this.icon,
    required this.items,
  });

  final String key;
  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
}

const List<String> _desktopSidebarFooterRoutes = <String>[
  Routes.users,
];

Map<String, AppNavigationItem> _desktopRouteToItem(
  List<AppNavigationSection> sections,
) {
  final allItems = <AppNavigationItem>[
    for (final section in sections) ...section.items,
  ];
  return {for (final item in allItems) item.route: item};
}

List<AppNavigationItem> _buildDesktopSidebarFooterItems(
  List<AppNavigationSection> sections,
) {
  final routeToItem = _desktopRouteToItem(sections);
  return [
    for (final route in _desktopSidebarFooterRoutes)
      if (routeToItem.containsKey(route)) routeToItem[route]!,
  ];
}

List<_SidebarMenuGroup> _buildDesktopSidebarGroups(
  List<AppNavigationSection> sections,
) {
  final routeToItem = _desktopRouteToItem(sections);
  final allItems = routeToItem.values.toList(growable: false);

  List<AppNavigationItem> pick(List<String> routes) {
    return [
      for (final route in routes)
        if (routeToItem.containsKey(route)) routeToItem[route]!,
    ];
  }

  AppNavigationItem menuItem(String route, String title, IconData icon) {
    final original = routeToItem[route];
    return AppNavigationItem(
      icon: icon,
      title: title,
      route: route,
      showIndicator: original?.showIndicator ?? false,
    );
  }

  final groups = <_SidebarMenuGroup>[
    _SidebarMenuGroup(
      key: 'principal',
      title: 'Principal',
      icon: Icons.dashboard_outlined,
      items: pick([Routes.clientes]),
    ),
    _SidebarMenuGroup(
      key: 'ventas_tpv',
      title: 'Ventas TPV',
      icon: Icons.point_of_sale_outlined,
      items: [
        if (routeToItem.containsKey(Routes.cotizaciones))
          menuItem(
            Routes.cotizaciones,
            'Punto de venta',
            Icons.shopping_cart_checkout_outlined,
          ),
        if (routeToItem.containsKey(Routes.catalogo))
          menuItem(Routes.catalogo, 'Inventario', Icons.inventory_2_outlined),
        if (routeToItem.containsKey(Routes.compras))
          menuItem(
            Routes.compras,
            'Compras',
            Icons.shopping_cart_checkout_outlined,
          ),
        if (routeToItem.containsKey(Routes.ventas))
          menuItem(Routes.ventas, 'Reportes', Icons.query_stats_outlined),
      ],
    ),
    _SidebarMenuGroup(
      key: 'administracion',
      title: 'Administración',
      icon: Icons.admin_panel_settings_outlined,
      items: pick([
        Routes.nomina,
        Routes.misPagos,
      ]),
    ),
    _SidebarMenuGroup(
      key: 'contabilidad',
      title: 'Contabilidad',
      icon: Icons.account_balance_outlined,
      items: pick([Routes.contabilidad]),
    ),
    _SidebarMenuGroup(
      key: 'herramientas',
      title: 'Herramientas',
      icon: Icons.smart_toy_outlined,
      items: pick([Routes.ai]),
    ),
  ];

  final knownRoutes = <String>{
    ..._desktopSidebarFooterRoutes,
    for (final group in groups)
      for (final item in group.items) item.route,
  };
  final extras = allItems
      .where((item) => !knownRoutes.contains(item.route))
      .toList(growable: false);
  if (extras.isNotEmpty) {
    groups.add(
      _SidebarMenuGroup(
        key: 'otros',
        title: 'Otros',
        icon: Icons.apps_outlined,
        items: extras,
      ),
    );
  }

  return groups
      .where((group) => group.items.isNotEmpty)
      .toList(growable: false);
}

String? _resolveActiveGroupKey(
  List<_SidebarMenuGroup> groups,
  String currentLocation,
) {
  for (final group in groups) {
    for (final item in group.items) {
      if (isNavigationRouteActive(currentLocation, item.route)) {
        return group.key;
      }
    }
  }
  return groups.isEmpty ? null : groups.first.key;
}

class DesktopSidebar extends ConsumerStatefulWidget {
  const DesktopSidebar({
    super.key,
    required this.collapsed,
    required this.currentUser,
    required this.sections,
    required this.currentLocation,
    required this.onToggleSidebar,
    required this.onNavigate,
  });

  final bool collapsed;
  final UserModel? currentUser;
  final List<AppNavigationSection> sections;
  final String currentLocation;
  final VoidCallback onToggleSidebar;
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar> {
  String? _openGroupKey;
  bool _clientsExpanded = false;
  bool _adminExpanded = false;
  bool _cashExpanded = false;

  Future<void> _openCashMovement(String type) async {
    final input = await showCashMovementDialog(context, type: type);
    if (input == null || !mounted) return;
    try {
      await ref
          .read(activeCashSessionControllerProvider.notifier)
          .addMovement(
            type: type,
            amount: input.amount,
            reason: input.reason,
            movementType: input.movementType,
            affectsProfit: input.affectsProfit,
          );
      if (!mounted) return;
      showCashToast(
        context,
        type == 'IN' ? 'Ingreso registrado' : 'Salida registrada',
      );
    } catch (error) {
      if (!mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  @override
  void initState() {
    super.initState();
    final groups = _buildDesktopSidebarGroups(widget.sections);
    _openGroupKey = _resolveActiveGroupKey(groups, widget.currentLocation);
    _restoreSidebarPreference();
    _syncSubmenusWithRoute();
  }

  Future<void> _restoreSidebarPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final collapsed = prefs.getBool('premium_sidebar_collapsed');
    if (!mounted || collapsed == null || collapsed == widget.collapsed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && collapsed != widget.collapsed) widget.onToggleSidebar();
    });
  }

  Future<void> _persistSidebarPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('premium_sidebar_collapsed', !widget.collapsed);
  }

  void _toggleSidebar() {
    widget.onToggleSidebar();
    unawaited(_persistSidebarPreference());
  }

  void _syncSubmenusWithRoute() {
    final path =
        Uri.tryParse(widget.currentLocation)?.path ?? widget.currentLocation;
    if (path.startsWith(Routes.clientes) ||
        path.startsWith(Routes.cotizacionesHistorial) ||
        path.startsWith(Routes.contabilidadPagosPendientes)) {
      _clientsExpanded = true;
    }
    if (path.startsWith(Routes.cajaRegistrarIngreso) ||
        path.startsWith(Routes.cajaRegistrarSalida) ||
        path.startsWith(Routes.cajaMovimientos)) {
      _cashExpanded = true;
    }
    if (path.startsWith(Routes.administracion) ||
        path.startsWith(Routes.contabilidad) ||
        path.startsWith(Routes.contabilidadPagosPendientes)) {
      _adminExpanded = true;
    }
  }

  @override
  void didUpdateWidget(covariant DesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation == widget.currentLocation &&
        oldWidget.sections == widget.sections) {
      return;
    }
    final groups = _buildDesktopSidebarGroups(widget.sections);
    final next = _resolveActiveGroupKey(groups, widget.currentLocation);
    if (next != null && next != _openGroupKey) {
      setState(() => _openGroupKey = next);
    }
    _syncSubmenusWithRoute();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final scale = (screenSize.height / 860).clamp(0.72, 1.0);
    final width = widget.collapsed
        ? (screenSize.width * 0.05 * scale).clamp(58.0, 68.0)
        : (screenSize.width * 0.124).clamp(176.0, 194.0);
    final baseColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF2F6F9);
    final textColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1E293B);
    final mutedText = Color.alphaBlend(
      textColor.withValues(alpha: 0.55),
      baseColor,
    );
    final activeColor = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final hoverColor = Color.alphaBlend(
      activeColor.withValues(alpha: 0.08),
      baseColor,
    );
    final borderColor = Color.alphaBlend(
      const Color(0xFFCBD5E1).withValues(alpha: 0.18),
      baseColor,
    );
    final routeToItem = _desktopRouteToItem(widget.sections);
    final footerItems = _buildDesktopSidebarFooterItems(widget.sections);
    final visualCollapsed = widget.collapsed;
    final navPaddingH = visualCollapsed ? 8.0 : 12.0;

    AppNavigationItem? nav(String route, String title, IconData icon) {
      final original = routeToItem[route];
      if (original == null) return null;
      return AppNavigationItem(
        icon: icon,
        title: title,
        route: route,
        showIndicator: original.showIndicator,
      );
    }

    final ventas = nav(
      Routes.cotizaciones,
      'Ventas',
      Icons.storefront_outlined,
    );
    final productos = nav(
      Routes.catalogo,
      'Productos',
      Icons.inventory_2_outlined,
    );
    final clientes = nav(
      Routes.clientes,
      'Clientes',
      Icons.people_alt_outlined,
    );
    final cotizaciones = nav(
      Routes.cotizacionesHistorial,
      'Cotizaciones',
      Icons.edit_note_outlined,
    );
    final creditosVentas = nav(
      Routes.ventasCreditos,
      'Créditos',
      Icons.credit_score_outlined,
    );
    final creditos = nav(
      Routes.contabilidadPagosPendientes,
      'Créditos',
      Icons.credit_card_outlined,
    );
    final reportes = nav(Routes.ventas, 'Reportes', Icons.bar_chart_rounded);
    final comprasTpv = nav(
      Routes.compras,
      'Compras',
      Icons.shopping_cart_checkout_outlined,
    );
    final cashIngreso = nav(
      Routes.cajaRegistrarIngreso,
      'Registrar entrada',
      Icons.add_circle_outline_rounded,
    );
    final cashSalida = nav(
      Routes.cajaRegistrarSalida,
      'Registrar salida',
      Icons.remove_circle_outline_rounded,
    );
    final cashHistorial = nav(
      Routes.cajaMovimientos,
      'Historial efectivo',
      Icons.history_rounded,
    );
    final compras = nav(
      Routes.contabilidad,
      'Compras',
      Icons.shopping_cart_outlined,
    );
    final gastos = nav(
      Routes.contabilidadPagosPendientes,
      'Gastos',
      Icons.payments_outlined,
    );
    final configuracion = nav(
      Routes.configuracion,
      'Configuración',
      Icons.settings_outlined,
    );

    final clientRoutes = {
      if (clientes != null) clientes.route,
      if (cotizaciones != null) cotizaciones.route,
    };
    final cashRoutes = {
      if (cashIngreso != null) cashIngreso.route,
      if (cashSalida != null) cashSalida.route,
      if (cashHistorial != null) cashHistorial.route,
    };
    final adminRoutes = {
      if (compras != null) compras.route,
      if (gastos != null) gastos.route,
      Routes.administracion,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: baseColor,
        border: Border(right: BorderSide(color: borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
            spreadRadius: -14,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.03 : 0.26),
                        Colors.transparent,
                        const Color(
                          0xFFE2E8F0,
                        ).withValues(alpha: isDark ? 0.04 : 0.42),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _PremiumSidebarHeader(
                  collapsed: visualCollapsed,
                  textColor: textColor,
                  mutedText: mutedText,
                  activeColor: activeColor,
                  borderColor: borderColor,
                  baseColor: baseColor,
                  scale: scale,
                  onToggle: _toggleSidebar,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compactHeight = constraints.maxHeight < 780;
                      final showLabels = !visualCollapsed && !compactHeight;
                      return ListView(
                        padding: EdgeInsets.fromLTRB(
                          navPaddingH,
                          visualCollapsed ? 12 : 8,
                          navPaddingH,
                          12,
                        ),
                        children: [
                          _PremiumSectionLabel(
                            text: 'Principal',
                            visible: showLabels,
                            color: mutedText,
                            scale: scale,
                          ),
                          if (ventas != null)
                            _PremiumSidebarNavItem(
                              item: ventas,
                              collapsed: visualCollapsed,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () => widget.onNavigate(ventas.route),
                            ),
                          if (productos != null)
                            _PremiumSidebarNavItem(
                              item: productos,
                              collapsed: visualCollapsed,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () => widget.onNavigate(productos.route),
                            ),
                          _PremiumSidebarNavItem(
                            item: const AppNavigationItem(
                              icon: Icons.groups_outlined,
                              title: 'Clientes',
                              route: '__clients__',
                            ),
                            activeRoutes: clientRoutes,
                            collapsed: visualCollapsed,
                            currentLocation: widget.currentLocation,
                            textColor: textColor,
                            activeColor: activeColor,
                            hoverColor: hoverColor,
                            baseColor: baseColor,
                            scale: scale,
                            showSubmenuBadge: true,
                            trailing: AnimatedRotation(
                              turns: _clientsExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: textColor.withValues(alpha: 0.58),
                              ),
                            ),
                            onTap: () {
                              if (visualCollapsed) {
                                _toggleSidebar();
                                setState(() => _clientsExpanded = true);
                              } else {
                                setState(
                                  () => _clientsExpanded = !_clientsExpanded,
                                );
                              }
                            },
                          ),
                          _PremiumSidebarSubmenu(
                            visible: !visualCollapsed && _clientsExpanded,
                            children: [
                              if (clientes != null)
                                _PremiumSidebarNavItem(
                                  item: clientes,
                                  collapsed: false,
                                  lowEmphasis: true,
                                  currentLocation: widget.currentLocation,
                                  textColor: textColor,
                                  activeColor: activeColor,
                                  hoverColor: hoverColor,
                                  baseColor: baseColor,
                                  scale: scale,
                                  onTap: () =>
                                      widget.onNavigate(clientes.route),
                                ),
                              if (cotizaciones != null)
                                _PremiumSidebarNavItem(
                                  item: cotizaciones,
                                  collapsed: false,
                                  lowEmphasis: true,
                                  currentLocation: widget.currentLocation,
                                  textColor: textColor,
                                  activeColor: activeColor,
                                  hoverColor: hoverColor,
                                  baseColor: baseColor,
                                  scale: scale,
                                  onTap: () =>
                                      widget.onNavigate(cotizaciones.route),
                                ),
                              if (creditos != null)
                                _PremiumSidebarNavItem(
                                  item: creditos,
                                  collapsed: false,
                                  lowEmphasis: true,
                                  currentLocation: widget.currentLocation,
                                  textColor: textColor,
                                  activeColor: activeColor,
                                  hoverColor: hoverColor,
                                  baseColor: baseColor,
                                  scale: scale,
                                  onTap: () =>
                                      widget.onNavigate(creditos.route),
                                ),
                            ],
                          ),
                          if (cashRoutes.isNotEmpty)
                            MouseRegion(
                              onEnter: (_) {
                                if (!visualCollapsed && !_cashExpanded) {
                                  setState(() => _cashExpanded = true);
                                }
                              },
                              onExit: (_) {
                                if (!visualCollapsed && _cashExpanded) {
                                  setState(() => _cashExpanded = false);
                                }
                              },
                              child: Column(
                                children: [
                                  _PremiumSidebarNavItem(
                                    item: const AppNavigationItem(
                                      icon:
                                          Icons.account_balance_wallet_outlined,
                                      title: 'Movimiento efectivo',
                                      route: '__cash__',
                                    ),
                                    activeRoutes: cashRoutes,
                                    collapsed: visualCollapsed,
                                    currentLocation: widget.currentLocation,
                                    textColor: textColor,
                                    activeColor: activeColor,
                                    hoverColor: hoverColor,
                                    baseColor: baseColor,
                                    scale: scale,
                                    showSubmenuBadge: true,
                                    trailing: AnimatedRotation(
                                      turns: _cashExpanded ? 0.25 : 0,
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: textColor.withValues(
                                          alpha: 0.58,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      if (visualCollapsed) {
                                        _toggleSidebar();
                                        setState(() => _cashExpanded = true);
                                      } else {
                                        setState(
                                          () => _cashExpanded = !_cashExpanded,
                                        );
                                      }
                                    },
                                  ),
                                  _PremiumSidebarSubmenu(
                                    visible: !visualCollapsed && _cashExpanded,
                                    children: [
                                      if (cashIngreso != null)
                                        _PremiumSidebarNavItem(
                                          item: cashIngreso,
                                          collapsed: false,
                                          lowEmphasis: true,
                                          currentLocation:
                                              widget.currentLocation,
                                          textColor: textColor,
                                          activeColor: activeColor,
                                          hoverColor: hoverColor,
                                          baseColor: baseColor,
                                          scale: scale,
                                          onTap: () => _openCashMovement('IN'),
                                        ),
                                      if (cashSalida != null)
                                        _PremiumSidebarNavItem(
                                          item: cashSalida,
                                          collapsed: false,
                                          lowEmphasis: true,
                                          currentLocation:
                                              widget.currentLocation,
                                          textColor: textColor,
                                          activeColor: activeColor,
                                          hoverColor: hoverColor,
                                          baseColor: baseColor,
                                          scale: scale,
                                          onTap: () => _openCashMovement('OUT'),
                                        ),
                                      if (cashHistorial != null)
                                        _PremiumSidebarNavItem(
                                          item: cashHistorial,
                                          collapsed: false,
                                          lowEmphasis: true,
                                          currentLocation:
                                              widget.currentLocation,
                                          textColor: textColor,
                                          activeColor: activeColor,
                                          hoverColor: hoverColor,
                                          baseColor: baseColor,
                                          scale: scale,
                                          onTap: () => widget.onNavigate(
                                            cashHistorial.route,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          if (creditosVentas != null)
                            _PremiumSidebarNavItem(
                              item: creditosVentas,
                              collapsed: visualCollapsed,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () =>
                                  widget.onNavigate(creditosVentas.route),
                            ),
                          if (comprasTpv != null)
                            _PremiumSidebarNavItem(
                              item: comprasTpv,
                              collapsed: visualCollapsed,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () => widget.onNavigate(comprasTpv.route),
                            ),
                          if (reportes != null)
                            _PremiumSidebarNavItem(
                              item: reportes,
                              collapsed: visualCollapsed,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () => widget.onNavigate(reportes.route),
                            ),
                          _PremiumSidebarNavItem(
                            item: const AppNavigationItem(
                              icon: Icons.grid_view_rounded,
                              title: 'Administración',
                              route: '__admin__',
                            ),
                            activeRoutes: adminRoutes,
                            collapsed: visualCollapsed,
                            currentLocation: widget.currentLocation,
                            textColor: textColor,
                            activeColor: activeColor,
                            hoverColor: hoverColor,
                            baseColor: baseColor,
                            scale: scale,
                            showSubmenuBadge: true,
                            trailing: AnimatedRotation(
                              turns: _adminExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: textColor.withValues(alpha: 0.58),
                              ),
                            ),
                            onTap: () {
                              if (visualCollapsed) {
                                _toggleSidebar();
                                setState(() => _adminExpanded = true);
                              } else {
                                setState(
                                  () => _adminExpanded = !_adminExpanded,
                                );
                              }
                            },
                          ),
                          _PremiumSidebarSubmenu(
                            visible: !visualCollapsed && _adminExpanded,
                            children: [
                              if (compras != null)
                                _PremiumSidebarNavItem(
                                  item: compras,
                                  collapsed: false,
                                  lowEmphasis: true,
                                  currentLocation: widget.currentLocation,
                                  textColor: textColor,
                                  activeColor: activeColor,
                                  hoverColor: hoverColor,
                                  baseColor: baseColor,
                                  scale: scale,
                                  onTap: () => widget.onNavigate(compras.route),
                                ),
                              if (gastos != null)
                                _PremiumSidebarNavItem(
                                  item: gastos,
                                  collapsed: false,
                                  lowEmphasis: true,
                                  currentLocation: widget.currentLocation,
                                  textColor: textColor,
                                  activeColor: activeColor,
                                  hoverColor: hoverColor,
                                  baseColor: baseColor,
                                  scale: scale,
                                  onTap: () => widget.onNavigate(gastos.route),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: borderColor),
                          ),
                          _PremiumSectionLabel(
                            text: 'Sistema',
                            visible: showLabels,
                            color: mutedText,
                            scale: scale,
                          ),
                          if (configuracion != null)
                            _PremiumSidebarNavItem(
                              item: configuracion,
                              collapsed: visualCollapsed,
                              lowEmphasis: true,
                              currentLocation: widget.currentLocation,
                              textColor: textColor,
                              activeColor: activeColor,
                              hoverColor: hoverColor,
                              baseColor: baseColor,
                              scale: scale,
                              onTap: () =>
                                  widget.onNavigate(configuracion.route),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: borderColor),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.collapsed ? 8 : 10,
                    8,
                    widget.collapsed ? 8 : 10,
                    12,
                  ),
                  child: Column(
                    children: [
                      for (final item in footerItems) ...[
                        _SidebarFooterButton(
                          collapsed: widget.collapsed,
                          tooltip: item.title,
                          icon: item.icon,
                          label: item.title,
                          selected: isNavigationRouteActive(
                            widget.currentLocation,
                            item.route,
                          ),
                          onTap: () => widget.onNavigate(item.route),
                        ),
                        const SizedBox(height: 4),
                      ],
                      _SidebarFooterButton(
                        collapsed: widget.collapsed,
                        tooltip: 'Mi perfil',
                        icon: Icons.person_outline_rounded,
                        label: widget.currentUser?.nombreCompleto ?? 'Perfil',
                        sublabel: resolveRoleBranding(
                          widget.currentUser?.appRole ?? AppRole.unknown,
                        ).departmentName,
                        useAvatar: true,
                        avatarInitials: userInitials(widget.currentUser),
                        selected: isNavigationRouteActive(
                          widget.currentLocation,
                          Routes.profile,
                        ),
                        onTap: () => context.push(Routes.profile),
                      ),
                      const SizedBox(height: 4),
                      _SidebarFooterButton(
                        collapsed: widget.collapsed,
                        tooltip: 'Cerrar sesión',
                        icon: Icons.logout_rounded,
                        label: 'Cerrar sesión',
                        isDestructive: true,
                        onTap: () async {
                          await ref.read(authStateProvider.notifier).logout();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumSidebarHeader extends StatelessWidget {
  const _PremiumSidebarHeader({
    required this.collapsed,
    required this.textColor,
    required this.mutedText,
    required this.activeColor,
    required this.borderColor,
    required this.baseColor,
    required this.scale,
    required this.onToggle,
  });

  final bool collapsed;
  final Color textColor;
  final Color mutedText;
  final Color activeColor;
  final Color borderColor;
  final Color baseColor;
  final double scale;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final brandSize = collapsed
        ? (40 * scale).clamp(34.0, 44.0)
        : (34 * scale).clamp(30.0, 38.0);
    final icon = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: brandSize,
      height: brandSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.16), baseColor),
            Color.alphaBlend(Colors.white.withValues(alpha: 0.04), baseColor),
          ],
        ),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            spreadRadius: -10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, color: textColor, size: 19),
          Positioned(
            right: 5,
            bottom: 7,
            child: Icon(
              Icons.credit_card_rounded,
              color: activeColor,
              size: 10,
            ),
          ),
          if (collapsed)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: baseColor, width: 2),
                ),
                child: const Icon(
                  Icons.keyboard_arrow_right_rounded,
                  color: Colors.white,
                  size: 11,
                ),
              ),
            ),
        ],
      ),
    );

    return SizedBox(
      height: 52,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
          child: collapsed
              ? Center(child: icon)
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FULLPOS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13.6,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.44,
                            ),
                          ),
                          Text(
                            'Sistema comercial',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Colapsar menú',
                      onPressed: onToggle,
                      icon: Icon(
                        Icons.keyboard_arrow_left_rounded,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PremiumSectionLabel extends StatelessWidget {
  const _PremiumSectionLabel({
    required this.text,
    required this.visible,
    required this.color,
    required this.scale,
  });

  final String text;
  final bool visible;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: color.withValues(alpha: 0.92),
            fontSize: (8.4 * scale).clamp(7.8, 9.4),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.45,
          ),
        ),
      ),
    );
  }
}

class _PremiumSidebarSubmenu extends StatelessWidget {
  const _PremiumSidebarSubmenu({required this.visible, required this.children});

  final bool visible;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(left: 14, top: 3, bottom: 5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: visible ? 1 : 0,
                child: Column(children: children),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _PremiumSidebarNavItem extends StatefulWidget {
  const _PremiumSidebarNavItem({
    required this.item,
    required this.collapsed,
    required this.currentLocation,
    required this.textColor,
    required this.activeColor,
    required this.hoverColor,
    required this.baseColor,
    required this.scale,
    required this.onTap,
    this.activeRoutes,
    this.lowEmphasis = false,
    this.showSubmenuBadge = false,
    this.trailing,
  });

  final AppNavigationItem item;
  final bool collapsed;
  final String currentLocation;
  final Color textColor;
  final Color activeColor;
  final Color hoverColor;
  final Color baseColor;
  final double scale;
  final VoidCallback onTap;
  final Set<String>? activeRoutes;
  final bool lowEmphasis;
  final bool showSubmenuBadge;
  final Widget? trailing;

  @override
  State<_PremiumSidebarNavItem> createState() => _PremiumSidebarNavItemState();
}

class _PremiumSidebarNavItemState extends State<_PremiumSidebarNavItem> {
  bool _hovered = false;

  bool get _active {
    final path =
        Uri.tryParse(widget.currentLocation)?.path ?? widget.currentLocation;
    final route = widget.item.route;
    final ownRoute =
        !route.startsWith('__') &&
        (path == route || path.startsWith('$route/'));
    final childRoute =
        widget.activeRoutes?.any((r) => path == r || path.startsWith('$r/')) ??
        false;
    return ownRoute || childRoute;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final active = _active;
    final rowHeight = collapsed
        ? (42 * widget.scale).clamp(40.0, 46.0)
        : (38 * widget.scale).clamp(35.0, 42.0);
    final radius = BorderRadius.circular((9 * widget.scale).clamp(7.0, 9.0));
    final fg = active
        ? Colors.white
        : widget.textColor.withValues(
            alpha: widget.lowEmphasis && !_hovered ? 0.62 : 1,
          );
    final activeTop = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.10),
      widget.activeColor,
    );
    final activeBottom = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.18),
      widget.activeColor,
    );

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      height: rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : (11 * widget.scale).clamp(9.0, 13.0),
      ),
      decoration: BoxDecoration(
        color: active
            ? null
            : (_hovered ? widget.hoverColor : Colors.transparent),
        gradient: active
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [activeTop, activeBottom],
              )
            : null,
        borderRadius: radius,
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.18)
              : widget.textColor.withValues(alpha: _hovered ? 0.10 : 0.0),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: widget.activeColor.withValues(alpha: 0.42),
                  blurRadius: 20,
                  spreadRadius: -8,
                  offset: const Offset(0, 10),
                ),
              ]
            : _hovered
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 14,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: collapsed
          ? Center(
              child: _PremiumCollapsedIcon(
                icon: widget.item.icon,
                active: active,
                hovered: _hovered,
                textColor: widget.textColor,
                activeColor: widget.activeColor,
                showSubmenuBadge: widget.showSubmenuBadge,
              ),
            )
          : Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(widget.item.icon, color: fg, size: 19.5),
                    if (widget.showSubmenuBadge)
                      Positioned(
                        right: -6,
                        bottom: -5,
                        child: _SubmenuBadge(
                          color: active ? Colors.white : widget.activeColor,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 12.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.12,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
    );

    content = AnimatedScale(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      scale: _hovered ? 1.05 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: widget.onTap, child: content),
      ),
    );

    if (collapsed) {
      content = Tooltip(
        message: widget.item.title,
        preferBelow: false,
        verticalOffset: 30,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16.5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF475569),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 20,
              spreadRadius: -10,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: collapsed ? 8 : 5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: content,
      ),
    );
  }
}

class _PremiumCollapsedIcon extends StatelessWidget {
  const _PremiumCollapsedIcon({
    required this.icon,
    required this.active,
    required this.hovered,
    required this.textColor,
    required this.activeColor,
    required this.showSubmenuBadge,
  });

  final IconData icon;
  final bool active;
  final bool hovered;
  final Color textColor;
  final Color activeColor;
  final bool showSubmenuBadge;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? Colors.white : textColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? [
                  activeColor,
                  Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.16),
                    activeColor,
                  ),
                ]
              : [
                  Colors.white.withValues(alpha: hovered ? 0.92 : 0.72),
                  Colors.white.withValues(alpha: hovered ? 0.64 : 0.44),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textColor.withValues(
            alpha: active
                ? 0.18
                : hovered
                ? 0.11
                : 0.08,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? activeColor : Colors.black).withValues(
              alpha: active
                  ? 0.44
                  : hovered
                  ? 0.18
                  : 0.10,
            ),
            blurRadius: active ? 18 : 12,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: 7,
            child: Container(
              height: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    iconColor.withValues(alpha: active ? 0.32 : 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(child: Icon(icon, color: iconColor, size: 19.5)),
          if (showSubmenuBadge)
            Positioned(
              right: 5,
              bottom: 4,
              child: _SubmenuBadge(color: active ? Colors.white : activeColor),
            ),
        ],
      ),
    );
  }
}

class _SubmenuBadge extends StatelessWidget {
  const _SubmenuBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DesktopSidebarCollapsedGroupButton extends StatefulWidget {
  const _DesktopSidebarCollapsedGroupButton({
    required this.title,
    required this.icon,
    required this.items,
    required this.currentLocation,
    required this.onNavigate,
    required this.selected,
    required this.showIndicator,
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final bool selected;
  final bool showIndicator;

  @override
  State<_DesktopSidebarCollapsedGroupButton> createState() =>
      _DesktopSidebarCollapsedGroupButtonState();
}

class _DesktopSidebarCollapsedGroupButtonState
    extends State<_DesktopSidebarCollapsedGroupButton> {
  bool _hovered = false;

  Future<void> _openSubmenu() async {
    if (widget.items.isEmpty) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromLTRB(
      bottomRight.dx + 8,
      topLeft.dy,
      overlay.size.width - bottomRight.dx,
      overlay.size.height - topLeft.dy,
    );

    final selectedRoute = await showMenu<String>(
      context: context,
      position: position,
      items: widget.items
          .map(
            (item) => PopupMenuItem<String>(
              value: item.route,
              child: Row(
                children: [
                  Icon(item.icon, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.title)),
                  if (isNavigationRouteActive(
                    widget.currentLocation,
                    item.route,
                  ))
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_rounded, size: 16),
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );

    if (selectedRoute == null) return;
    widget.onNavigate(selectedRoute);
  }

  @override
  Widget build(BuildContext context) {
    const normal = Color(0xFF5F7180);
    const activeColor = Color(0xFF1957E6);

    final icon = SizedBox(
      height: 48,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFFEAF1FF)
                : (_hovered ? const Color(0xFFF3F7FF) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.selected ? activeColor : normal,
              ),
              Positioned(
                right: 5,
                bottom: 6,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 12,
                  color: widget.selected
                      ? activeColor
                      : normal.withValues(alpha: 0.85),
                ),
              ),
              if (widget.showIndicator)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.title,
      preferBelow: false,
      verticalOffset: 30,
      textStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(onTap: _openSubmenu, child: icon),
      ),
    );
  }
}

// ── Footer action button ──────────────────────────────────────────────────────

class _SidebarFooterButton extends StatefulWidget {
  const _SidebarFooterButton({
    required this.collapsed,
    required this.tooltip,
    required this.icon,
    required this.label,
    this.sublabel,
    this.useAvatar = false,
    this.avatarInitials = '',
    this.isDestructive = false,
    this.selected = false,
    required this.onTap,
  });

  final bool collapsed;
  final String tooltip;
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool useAvatar;
  final String avatarInitials;
  final bool isDestructive;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarFooterButton> createState() => _SidebarFooterButtonState();
}

class _SidebarFooterButtonState extends State<_SidebarFooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const slate400 = Color(0xFF5F7180);
    final bg = widget.selected
        ? const Color(0xFFEAF1FF)
        : _hovered
        ? const Color(0xFFF3F7FF)
        : Colors.transparent;
    final fgColor = widget.selected
        ? const Color(0xFF1957E6)
        : widget.isDestructive
        ? Colors.red.shade600
        : slate400;

    Widget content = Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: widget.selected
            ? Border.all(color: const Color(0xFFB9CCFF))
            : null,
      ),
      child: widget.collapsed
          ? Center(child: Icon(widget.icon, size: 18, color: fgColor))
          : Row(
              children: [
                widget.useAvatar
                    ? CircleAvatar(
                        radius: 13,
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                          widget.avatarInitials,
                          style: TextStyle(
                            color: const Color(0xFF1957E6),
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    : Icon(widget.icon, size: 17, color: fgColor),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fgColor,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      if (widget.sublabel != null)
                        Text(
                          widget.sublabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: slate400,
                            fontFamily: 'Inter',
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );

    if (widget.collapsed) {
      content = Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        verticalOffset: 28,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}

class _DesktopSidebarItem extends StatefulWidget {
  const _DesktopSidebarItem({
    required this.collapsed,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DesktopSidebarItem> createState() => _DesktopSidebarItemState();
}

class _DesktopSidebarItemState extends State<_DesktopSidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBase = Color(0xFF1957E6);
    const normalText = Color(0xFF5F7180);
    final selected = widget.selected;
    final collapsed = widget.collapsed;

    Widget content;
    if (collapsed) {
      content = SizedBox(
        height: 46,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEAF1FF)
                  : (_hovered ? const Color(0xFFF3F7FF) : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  widget.item.icon,
                  size: 18,
                  color: selected ? onBase : normalText,
                ),
                if (widget.item.showIndicator)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      final itemBg = selected
          ? const Color(0xFFEAF1FF)
          : (_hovered ? const Color(0xFFF3F7FF) : Colors.transparent);

      content = SizedBox(
        height: 46,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: itemBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1957E6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(width: selected ? 10 : 13),
              Icon(
                widget.item.icon,
                size: 19,
                color: selected ? onBase : normalText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? onBase : normalText,
                    fontSize: 14,
                  ),
                ),
              ),
              if (widget.item.showIndicator)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget wrapped = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(onTap: widget.onTap, child: content),
    );

    // Collapsed: styled tooltip to the right
    if (collapsed) {
      return Tooltip(
        message: widget.item.title,
        preferBelow: false,
        verticalOffset: 30,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: wrapped,
      );
    }
    return wrapped;
  }
}
