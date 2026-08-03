import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/cash/cash_dialogs.dart';
import '../../modules/cash/cash_providers.dart';
import '../../modules/cash/cash_repository.dart';

import '../auth/admin_authorization.dart';
import '../auth/app_permissions.dart';
import '../auth/auth_provider.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';

import '../design_system/icons/app_icon.dart';
import '../design_system/icons/app_icon_sizes.dart';
import '../design_system/icons/app_icons.dart';
import '../routing/app_navigator.dart';
import '../routing/routes.dart';
import '../routing/route_access.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_navigation.dart';

const String _drawerCloseTurnAction = '__drawer_close_turn__';

class AppDrawer extends ConsumerStatefulWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _DrawerSettingsMenuEntry extends StatelessWidget {
  const _DrawerSettingsMenuEntry({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: effectiveColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: effectiveColor,
                fontWeight: FontWeight.w600,
                fontSize: 14.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  int? _openGroupIndex;

  void _openGroup(int index) {
    if (_openGroupIndex == index) return;
    setState(() => _openGroupIndex = index);
  }

  void _toggleGroup(int index) {
    setState(() => _openGroupIndex = _openGroupIndex == index ? null : index);
  }

  void _closeGroup(int index) {
    if (_openGroupIndex != index) return;
    setState(() => _openGroupIndex = null);
  }

  Future<void> _openMovementDialog(BuildContext context, String type) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final controller = ref.read(activeCashSessionControllerProvider.notifier);
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;
    final input = await showCashMovementDialog(rootContext, type: type);
    if (input == null || !rootContext.mounted) return;
    try {
      await controller.addMovement(
        type: type,
        amount: input.amount,
        reason: input.reason,
        movementType: input.movementType,
        affectsProfit: input.affectsProfit,
      );
      if (!rootContext.mounted) return;
      showCashToast(
        rootContext,
        type == 'IN' ? 'Ingreso registrado' : 'Salida registrada',
      );
    } catch (error) {
      if (!rootContext.mounted) return;
      showCashToast(rootContext, resolveCashError(error), isError: true);
    }
  }

  Future<void> _closeTurnFromDrawer(BuildContext context) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;

    try {
      final summary = await ref.read(cashRepositoryProvider).summary();
      if (!rootContext.mounted) return;
      final result = await showCloseShiftDialog(
        rootContext,
        expectedCash: summary.expectedCash,
        onCloseShift: (amount) {
          return ref
              .read(activeCashSessionControllerProvider.notifier)
              .close(amount);
        },
      );
      if (!rootContext.mounted || result?.success != true) return;
      await ref.read(activeCashSessionControllerProvider.notifier).refresh();
      if (!rootContext.mounted) return;
      final printResult = result?.printResult;
      final message = printResult == null
          ? 'Turno cerrado'
          : printResult.success
          ? 'Turno cerrado e impreso'
          : 'Turno cerrado. ${printResult.message}';
      showCashToast(rootContext, message);
    } catch (error) {
      if (!rootContext.mounted) return;
      showCashToast(rootContext, resolveCashError(error), isError: true);
    }
  }

  Future<void> _handleItemTap(
    BuildContext context,
    AppNavigationItem item,
  ) async {
    if (item.route == _drawerCloseTurnAction) {
      await _closeTurnFromDrawer(context);
      return;
    }
    final permission = RouteAccess.permissionForLocation(item.route);
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: permission,
      reason: 'Entrar a ${item.title}',
    );
    if (!allowed || !context.mounted) return;
    if (item.route == Routes.cajaRegistrarIngreso) {
      _openMovementDialog(context, 'IN');
      return;
    }
    if (item.route == Routes.cajaRegistrarSalida) {
      _openMovementDialog(context, 'OUT');
      return;
    }
    final routerContext = Navigator.of(context, rootNavigator: true).context;

    Navigator.pop(context);
    if (!routerContext.mounted) return;
    AppNavigator.go(routerContext, item.route);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= kDesktopShellBreakpoint;
    final isCompactMobile = mediaQuery.size.width < 390;
    final role =
        currentUser?.appRole ??
        ref.watch(authStateProvider).user?.appRole ??
        AppRole.unknown;
    final sections = buildAppNavigationSections(ref, currentUser);
    final groups = _buildDrawerGroups(
      sections,
      mobileLayout: !isDesktop,
      role: role,
    );
    final location = safeCurrentLocation(context);
    final expandedGroupIndex = isDesktop
        ? (_openGroupIndex ?? 0)
        : _openGroupIndex;
    final panelShadow = BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(6, 0),
    );

    return Drawer(
      width: isDesktop ? 318 : null,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDesktop ? AppColors.surface : const Color(0xFFF7FCFF),
          gradient: isDesktop
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFE6F7FF),
                    Color(0xFFFBFEFF),
                    Color(0xFFE9F5FF),
                  ],
                  stops: [0, 0.52, 1],
                ),
          boxShadow: [panelShadow],
        ),
        child: Stack(
          children: [
            if (!isDesktop)
              const Positioned.fill(child: _MobileDrawerPattern()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 14 : 10,
                      isDesktop ? 12 : 6,
                      isDesktop ? 14 : 10,
                      isDesktop ? 10 : 4,
                    ),
                    child: isDesktop
                        ? Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompactMobile ? 12 : 14,
                              vertical: isCompactMobile ? 12 : 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFD),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFD8E5EC),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: isCompactMobile ? 58 : 66,
                                  height: isCompactMobile ? 48 : 56,
                                  child: Image.asset(
                                    'assets/image/logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.storefront_rounded,
                                        color: AppColors.primary,
                                        size: isCompactMobile ? 32 : 38,
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(width: isCompactMobile ? 8 : 10),
                                Expanded(
                                  child: Text(
                                    'FullPOS Cloud',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.title.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF102436),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar menú',
                                  onPressed: () => Navigator.pop(context),
                                  icon: AppIcon(
                                    AppIcons.close,
                                    size: AppIconSizes.button,
                                    color: AppColors.textSecondary,
                                    semanticLabel: 'Cerrar menú',
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            children: [
                              const Spacer(),
                              IconButton(
                                tooltip: 'Cerrar menú',
                                onPressed: () => Navigator.pop(context),
                                icon: AppIcon(
                                  AppIcons.close,
                                  size: AppIconSizes.button,
                                  color: AppColors.textSecondary,
                                  semanticLabel: 'Cerrar menú',
                                ),
                              ),
                            ],
                          ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        isCompactMobile ? 8 : 10,
                        4,
                        isCompactMobile ? 8 : 10,
                        8,
                      ),
                      children: [
                        for (var i = 0; i < groups.length; i++)
                          _DrawerMenuGroupTile(
                            group: groups[i],
                            index: i,
                            compact: isCompactMobile,
                            expanded: expandedGroupIndex == i,
                            selected: groups[i].containsActiveRoute(location),
                            onHoverOpen: isDesktop && groups[i].openOnHover
                                ? () => _openGroup(i)
                                : null,
                            onHoverExit: isDesktop && groups[i].openOnHover
                                ? () => _closeGroup(i)
                                : null,
                            onTapHeader: () => _toggleGroup(i),
                            itemBuilder: (item) => _DrawerMenuItem(
                              icon: item.icon,
                              appIcon: item.appIcon,
                              title: item.title,
                              compact: isCompactMobile,
                              selected: isNavigationRouteActive(
                                location,
                                item.route,
                              ),
                              showIndicator: item.showIndicator,
                              onTap: () => _handleItemTap(context, item),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompactMobile ? 10 : 12,
                      8,
                      isCompactMobile ? 10 : 12,
                      12,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DrawerMenuItem(
                                icon: Icons.badge_outlined,
                                title: 'Perfil',
                                compact: isCompactMobile,
                                selected: isNavigationRouteActive(
                                  location,
                                  Routes.profile,
                                ),
                                onTap: () {
                                  final routerContext = Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).context;
                                  Navigator.pop(context);
                                  if (routerContext.mounted) {
                                    AppNavigator.go(
                                      routerContext,
                                      Routes.profile,
                                    );
                                  }
                                },
                              ),
                            ),
                            if (!isDesktop)
                              PopupMenuButton<String>(
                                tooltip: 'Configuración',
                                constraints: const BoxConstraints(
                                  minWidth: 230,
                                  maxWidth: 270,
                                ),
                                elevation: 10,
                                color: Colors.white,
                                shadowColor: Colors.black26,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: Color(0xFFE1E8F0),
                                  ),
                                ),
                                onSelected: (route) {
                                  final routerContext = Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).context;
                                  Navigator.pop(context);
                                  if (!routerContext.mounted) return;
                                  if (route == 'delete-account') {
                                    ScaffoldMessenger.of(
                                      routerContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Eliminar mi cuenta estará disponible en configuración.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  AppNavigator.go(routerContext, route);
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: Routes.actualizaciones,
                                    child: _DrawerSettingsMenuEntry(
                                      icon: Icons.system_update_alt_rounded,
                                      label: 'Actualizaciones',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: Routes.apps,
                                    child: _DrawerSettingsMenuEntry(
                                      icon: Icons.apps_rounded,
                                      label: 'Apps',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: Routes.configuracion,
                                    child: _DrawerSettingsMenuEntry(
                                      icon: Icons.tune_rounded,
                                      label: 'Otros ajustes',
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'delete-account',
                                    child: _DrawerSettingsMenuEntry(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Eliminar mi cuenta',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Cerrar sesion',
                              onPressed: () async {
                                Navigator.pop(context);
                                await ref
                                    .read(authStateProvider.notifier)
                                    .logout();
                              },
                              icon: AppIcon(
                                AppIcons.logout,
                                size: AppIconSizes.button,
                                color: AppColors.textSecondary,
                                semanticLabel: 'Cerrar sesión',
                              ),
                            ),
                          ],
                        ),
                        if (hasPermission(role, AppPermission.manageUsers)) ...[
                          const SizedBox(height: 4),
                          _DrawerMenuItem(
                            icon: Icons.manage_accounts_outlined,
                            title: 'Usuario',
                            compact: isCompactMobile,
                            selected: isNavigationRouteActive(
                              location,
                              Routes.users,
                            ),
                            onTap: () {
                              final routerContext = Navigator.of(
                                context,
                                rootNavigator: true,
                              ).context;
                              Navigator.pop(context);
                              if (routerContext.mounted) {
                                AppNavigator.go(routerContext, Routes.users);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<_DrawerMenuGroup> _buildDrawerGroups(
  List<AppNavigationSection> sections, {
  required bool mobileLayout,
  required AppRole role,
}) {
  final itemsByRoute = <String, AppNavigationItem>{};
  for (final section in sections) {
    for (final item in section.items) {
      itemsByRoute.putIfAbsent(item.route, () => item);
    }
  }

  AppNavigationItem? pick(String route) => itemsByRoute.remove(route);
  void discard(List<String> routes) {
    for (final route in routes) {
      itemsByRoute.remove(route);
    }
  }

  final groups = <_DrawerMenuGroup>[];
  void addGroup(String title, IconData icon, List<String> routes) {
    final items = <AppNavigationItem>[
      for (final route in routes)
        if (pick(route) case final item?) item,
    ];
    if (items.isEmpty) return;
    groups.add(_DrawerMenuGroup(title: title, icon: icon, items: items));
  }

  void addDirectItems(List<AppNavigationItem> items) {
    if (items.isEmpty) return;
    groups.add(
      _DrawerMenuGroup(
        title: '',
        icon: Icons.circle_outlined,
        items: items,
        headerVisible: false,
        openOnHover: false,
      ),
    );
  }

  List<AppNavigationItem> pickItems(List<String> routes) {
    return [
      for (final route in routes)
        if (pick(route) case final item?) item,
    ];
  }

  final ventasItems = pickItems([Routes.cotizaciones, Routes.ventasLista]);
  final inventoryItems = pickItems([Routes.catalogo]);
  final cashItems = pickItems([
    Routes.cajaRegistrarIngreso,
    Routes.cajaRegistrarSalida,
    Routes.cajaMovimientos,
  ]);
  final rawClientItem = pick(Routes.clientes);
  final clientItem = rawClientItem == null
      ? null
      : AppNavigationItem(
          icon: rawClientItem.icon,
          appIcon: rawClientItem.appIcon,
          title: 'Cliente',
          route: rawClientItem.route,
          showIndicator: rawClientItem.showIndicator,
        );
  final cotizacionesItem =
      pick(Routes.cotizacionesHistorial) ??
      (hasPermission(role, AppPermission.viewSales)
          ? const AppNavigationItem(
              icon: Icons.edit_note_outlined,
              title: 'Cotizaciones',
              route: Routes.cotizacionesHistorial,
            )
          : null);
  final creditosItem = pick(Routes.ventasCreditos);
  final clientItems = <AppNavigationItem>[
    if (clientItem != null) clientItem,
    if (cotizacionesItem != null) cotizacionesItem,
    if (creditosItem != null) creditosItem,
  ];
  final purchasesItem = pick(Routes.compras);
  final reportsItem = pick(Routes.ventas);
  final directSalesModuleItems = <AppNavigationItem>[
    ...inventoryItems,
    if (purchasesItem != null) purchasesItem,
    if (reportsItem != null) reportsItem,
  ];

  if (mobileLayout) {
    if (ventasItems.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Ventas',
          icon: Icons.point_of_sale_rounded,
          items: ventasItems,
          openOnHover: false,
        ),
      );
    }
    if (clientItems.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Cliente',
          icon: Icons.groups_2_outlined,
          items: clientItems,
          openOnHover: false,
        ),
      );
    }
    if (cashItems.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Movimiento efectivo',
          icon: Icons.account_balance_wallet_outlined,
          items: cashItems,
          openOnHover: false,
        ),
      );
    }

    final turnosItems = <AppNavigationItem>[
      if (hasPermission(role, AppPermission.viewSales))
        const AppNavigationItem(
          icon: Icons.point_of_sale_outlined,
          title: 'Turno actual',
          route: Routes.caja,
        ),
      if (hasPermission(role, AppPermission.viewSales))
        const AppNavigationItem(
          icon: Icons.lock_clock_outlined,
          title: 'Cerrar turno',
          route: _drawerCloseTurnAction,
        ),
      pick(Routes.cajaTurnosHistorial) ??
          const AppNavigationItem(
            icon: Icons.history_rounded,
            title: 'Historial de turnos',
            route: Routes.cajaTurnosHistorial,
          ),
    ];
    groups.add(
      _DrawerMenuGroup(
        title: 'Turno',
        icon: Icons.schedule_outlined,
        items: turnosItems,
        openOnHover: false,
      ),
    );

    discard([
      Routes.apps,
      Routes.licencias,
      Routes.actualizaciones,
      Routes.configuracionEmpresa,
      Routes.configuracion,
    ]);

    addGroup('Contabilidad', Icons.account_balance_outlined, [
      Routes.contabilidad,
      Routes.nomina,
      Routes.misPagos,
    ]);
    if (inventoryItems.isNotEmpty) {
      groups.add(
        const _DrawerMenuGroup(
          title: 'Inventario',
          icon: Icons.inventory_2_outlined,
          items: [
            AppNavigationItem(
              icon: Icons.table_rows_outlined,
              title: 'Catálogo',
              route: Routes.catalogo,
            ),
            AppNavigationItem(
              icon: Icons.tune_outlined,
              title: 'Stock',
              route: Routes.catalogoStock,
            ),
            AppNavigationItem(
              icon: Icons.category_outlined,
              title: 'Categorías',
              route: Routes.catalogoCategorias,
            ),
            AppNavigationItem(
              icon: Icons.fact_check_outlined,
              title: 'Conteo',
              route: Routes.catalogoConteo,
            ),
          ],
          openOnHover: false,
        ),
      );
    }
    if (purchasesItem != null) {
      groups.add(
        const _DrawerMenuGroup(
          title: 'Compras',
          icon: Icons.shopping_bag_outlined,
          items: [
            AppNavigationItem(
              icon: Icons.add_shopping_cart_outlined,
              title: 'Nueva compra',
              route: Routes.compras,
            ),
            AppNavigationItem(
              icon: Icons.receipt_long_outlined,
              title: 'Lista de compra',
              route: Routes.comprasLista,
            ),
            AppNavigationItem(
              icon: Icons.storefront_outlined,
              title: 'Suplidores',
              route: Routes.comprasSuplidores,
            ),
            AppNavigationItem(
              icon: Icons.folder_copy_outlined,
              title: 'Facturas',
              route: Routes.comprasFacturas,
            ),
            AppNavigationItem(
              icon: Icons.trending_up_rounded,
              title: 'Productos por comprar',
              route: Routes.comprasPorComprar,
            ),
          ],
          openOnHover: false,
        ),
      );
    }
    if (reportsItem != null) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Reportes',
          icon: Icons.analytics_outlined,
          items: [reportsItem],
          openOnHover: false,
        ),
      );
    }
    addGroup('Factura fiscal', Icons.fact_check_outlined, [
      Routes.contabilidadFacturaFiscal,
    ]);

    discard([
      Routes.ai,
      Routes.administracion,
      Routes.contabilidadCierresDiarios,
      Routes.users,
      Routes.ponche,
      Routes.serviceOrderCommissions,
      Routes.publicidad,
      Routes.sitioWeb,
      Routes.whatsapp,
      Routes.whatsappCrm,
      Routes.crmComercial,
      Routes.manualInterno,
      Routes.amonestaciones,
    ]);

    if (itemsByRoute.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Más módulos',
          icon: Icons.apps_rounded,
          items: itemsByRoute.values.toList(),
          openOnHover: false,
        ),
      );
    }

    return groups;
  }

  if (ventasItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Ventas',
        icon: Icons.point_of_sale_rounded,
        items: ventasItems,
        openOnHover: false,
      ),
    );
  }
  if (cashItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Movimiento efectivo',
        icon: Icons.account_balance_wallet_outlined,
        items: cashItems,
        openOnHover: false,
      ),
    );
  }
  if (clientItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Cliente',
        icon: Icons.groups_2_outlined,
        items: clientItems,
        openOnHover: false,
      ),
    );
  }
  addDirectItems(directSalesModuleItems);

  discard([
    Routes.ai,
    Routes.administracion,
    Routes.contabilidadCierresDiarios,
    Routes.users,
    Routes.ponche,
    Routes.serviceOrderCommissions,
    Routes.publicidad,
    Routes.sitioWeb,
    Routes.whatsapp,
    Routes.whatsappCrm,
    Routes.crmComercial,
    Routes.manualInterno,
    Routes.amonestaciones,
    Routes.configuracion,
  ]);
  addGroup('Contabilidad', Icons.account_balance_outlined, [
    Routes.contabilidad,
    Routes.nomina,
    Routes.misPagos,
  ]);
  addGroup('Factura fiscal', Icons.fact_check_outlined, [
    Routes.contabilidadFacturaFiscal,
  ]);
  addGroup('Operaciones', Icons.work_outline_rounded, [
    Routes.serviceOrders,
    Routes.mediaGallery,
    Routes.redTecnica,
  ]);

  if (itemsByRoute.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Más módulos',
        icon: Icons.apps_rounded,
        items: itemsByRoute.values.toList(),
      ),
    );
  }

  return groups;
}

class _DrawerMenuGroup {
  const _DrawerMenuGroup({
    required this.title,
    required this.icon,
    required this.items,
    this.openOnHover = true,
    this.headerVisible = true,
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
  final bool openOnHover;
  final bool headerVisible;

  bool containsActiveRoute(String location) {
    bool active(AppNavigationItem item) {
      return isNavigationRouteActive(location, item.route);
    }

    return items.any(active);
  }
}

Widget? buildAdaptiveDrawer(
  BuildContext context, {
  required UserModel? currentUser,
}) {
  // Never show drawer inside dialogs/bottom-sheet routes.
  final route = ModalRoute.of(context);
  if (route is PopupRoute) return null;
  if (route is PageRoute && route.fullscreenDialog) return null;

  return AppDrawer(currentUser: currentUser);
}

class _MobileDrawerPattern extends StatelessWidget {
  const _MobileDrawerPattern();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _MobileDrawerPatternPainter()),
    );
  }
}

class _MobileDrawerPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final topGlow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x662E9BFF), Color(0x002E9BFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.04),
              radius: size.width * 0.9,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.04),
      size.width * 0.9,
      topGlow,
    );

    final bottomGlow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x553E7BFA), Color(0x003E7BFA)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 0.96),
              radius: size.width * 0.78,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.96),
      size.width * 0.78,
      bottomGlow,
    );

    final patternPaint = Paint()
      ..color = const Color(0x143B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    const gap = 34.0;
    for (double y = -gap; y < size.height + gap; y += gap) {
      final path = Path();
      path.moveTo(-20, y);
      path.quadraticBezierTo(size.width * 0.26, y + 12, size.width * 0.55, y);
      path.quadraticBezierTo(size.width * 0.82, y - 12, size.width + 20, y + 2);
      canvas.drawPath(path, patternPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DrawerMenuGroupTile extends StatelessWidget {
  const _DrawerMenuGroupTile({
    required this.group,
    required this.index,
    required this.compact,
    required this.expanded,
    required this.selected,
    required this.onTapHeader,
    required this.itemBuilder,
    this.onHoverOpen,
    this.onHoverExit,
  });

  final _DrawerMenuGroup group;
  final int index;
  final bool compact;
  final bool expanded;
  final bool selected;
  final VoidCallback onTapHeader;
  final VoidCallback? onHoverOpen;
  final VoidCallback? onHoverExit;
  final Widget Function(AppNavigationItem item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (!group.headerVisible) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 6,
          compact ? 4 : 6,
          compact ? 4 : 6,
          compact ? 8 : 10,
        ),
        child: Column(
          children: [for (final item in group.items) itemBuilder(item)],
        ),
      );
    }

    final foreground = AppColors.textPrimary;
    final headerBg = selected || expanded
        ? AppColors.primary.withValues(alpha: 0.09)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: onHoverOpen == null ? null : (_) => onHoverOpen!(),
      onExit: onHoverExit == null ? null : (_) => onHoverExit!(),
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 4 : 5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: expanded
                ? AppColors.surfaceMuted.withValues(alpha: 0.36)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: onTapHeader,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: compact ? 46 : 50,
                    padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 10),
                    decoration: BoxDecoration(
                      color: headerBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: compact ? 32 : 34,
                          height: compact ? 32 : 34,
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            group.icon,
                            color: foreground,
                            size: compact ? 18 : 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            group.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                              fontSize: compact ? 13.8 : 14.6,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                          size: compact ? 20 : 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 6 : 7,
                    2,
                    compact ? 6 : 7,
                    compact ? 5 : 6,
                  ),
                  child: Column(
                    children: [
                      for (final item in group.items) itemBuilder(item),
                    ],
                  ),
                ),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 170),
                sizeCurve: Curves.easeOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatefulWidget {
  final IconData icon;
  final AppIconData? appIcon;
  final String title;
  final bool compact;
  final bool selected;
  final bool showIndicator;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    this.appIcon,
    required this.title,
    required this.compact,
    required this.selected,
    this.showIndicator = false,
    required this.onTap,
  });

  @override
  State<_DrawerMenuItem> createState() => _DrawerMenuItemState();
}

class _DrawerMenuItemState extends State<_DrawerMenuItem>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 140),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handlePointerDown() {
    _pressController.forward();
  }

  void _handlePointerUp() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final tileBg = selected
        ? AppColors.primary.withValues(alpha: 0.09)
        : (_hovered
              ? AppColors.surfaceMuted.withValues(alpha: 0.72)
              : Colors.transparent);
    final foreground = selected ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 2 : 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: (_) => _handlePointerDown(),
          onPointerUp: (_) => _handlePointerUp(),
          onPointerCancel: (_) => _handlePointerUp(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _handlePointerUp();
                  widget.onTap();
                },
                splashColor: AppColors.primary.withValues(alpha: 0.15),
                highlightColor: AppColors.primary.withValues(alpha: 0.08),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: widget.compact ? 44 : 48,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 10 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: selected ? 4 : 3,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      SizedBox(width: selected ? 9 : 12),
                      widget.appIcon == null
                          ? Icon(
                              widget.icon,
                              size: widget.compact ? 19 : 20,
                              color: foreground,
                            )
                          : AppIcon(
                              widget.appIcon!,
                              size: widget.compact ? 19 : 20,
                              color: foreground,
                              semanticLabel: widget.title,
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: widget.compact ? 13.8 : 14.4,
                            color: foreground,
                          ),
                        ),
                      ),
                      if (widget.showIndicator)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 10),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.error.withValues(
                                  alpha: 0.40,
                                ),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
