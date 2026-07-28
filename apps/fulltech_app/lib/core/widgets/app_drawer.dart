import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/cash/cash_dialogs.dart';
import '../../modules/cash/cash_providers.dart';
import '../auth/app_permissions.dart';
import '../auth/auth_provider.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';
import '../design_system/icons/app_icon.dart';
import '../design_system/icons/app_icon_sizes.dart';
import '../design_system/icons/app_icons.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_navigation.dart';

class AppDrawer extends ConsumerStatefulWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  int? _openGroupIndex = 0;

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

  void _handleItemTap(BuildContext context, AppNavigationItem item) {
    if (item.route == Routes.cajaRegistrarIngreso) {
      _openMovementDialog(context, 'IN');
      return;
    }
    if (item.route == Routes.cajaRegistrarSalida) {
      _openMovementDialog(context, 'OUT');
      return;
    }
    Navigator.pop(context);
    context.go(item.route);
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
      includeMobileAdminShortcuts: !isDesktop,
      role: role,
    );
    final location = safeCurrentLocation(context);
    final panelShadow = BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(6, 0),
    );

    return Drawer(
      width: isDesktop ? 318 : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(18)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [panelShadow],
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 12 : 14,
                  isCompactMobile ? 10 : 12,
                  isCompactMobile ? 12 : 14,
                  10,
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompactMobile ? 12 : 14,
                    vertical: isCompactMobile ? 12 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFD),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD8E5EC)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'DaleVenta POS',
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
                        expanded: _openGroupIndex == i,
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
                              Navigator.pop(context);
                              context.go(Routes.profile);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sesion',
                          onPressed: () async {
                            Navigator.pop(context);
                            await ref.read(authStateProvider.notifier).logout();
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
                          Navigator.pop(context);
                          context.go(Routes.users);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_DrawerMenuGroup> _buildDrawerGroups(
  List<AppNavigationSection> sections, {
  required bool includeMobileAdminShortcuts,
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

  if (includeMobileAdminShortcuts) {
    final turnosItem =
        pick(Routes.cajaTurnosHistorial) ??
        (hasPermission(role, AppPermission.viewSales)
            ? const AppNavigationItem(
                icon: Icons.schedule_outlined,
                title: 'Turnos',
                route: Routes.cajaTurnosHistorial,
              )
            : null);
    final configuracionItem = pick(Routes.configuracion);
    final mobileItems = <AppNavigationItem>[
      if (turnosItem != null) turnosItem,
      if (configuracionItem != null) configuracionItem,
    ];

    if (mobileItems.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'APK',
          icon: Icons.phone_android_rounded,
          items: mobileItems,
          openOnHover: false,
        ),
      );
    }
  }

  discard([
    Routes.ai,
    Routes.administracion,
    Routes.contabilidadCierresDiarios,
    Routes.contabilidadFacturaFiscal,
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
