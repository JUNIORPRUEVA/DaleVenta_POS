import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/cash/cash_dialogs.dart';
import '../../modules/cash/cash_providers.dart';
import '../auth/auth_provider.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/role_branding.dart';
import 'app_navigation.dart';

class AppDrawer extends ConsumerStatefulWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
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
    final sections = buildAppNavigationSections(ref, currentUser);
    final groups = _buildDrawerGroups(sections);
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= kDesktopShellBreakpoint;
    final isCompactMobile = mediaQuery.size.width < 390;
    final location = safeCurrentLocation(context);
    final role =
        currentUser?.appRole ??
        ref.watch(authStateProvider).user?.appRole ??
        AppRole.unknown;
    final branding = resolveRoleBranding(role);
    final userDisplayName =
        currentUser?.nombreCompleto.trim().isNotEmpty == true
        ? currentUser!.nombreCompleto
        : branding.departmentName;
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
                  padding: EdgeInsets.fromLTRB(
                    isCompactMobile ? 10 : 12,
                    isCompactMobile ? 10 : 11,
                    isCompactMobile ? 10 : 12,
                    isCompactMobile ? 9 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'FullTech POS',
                                style: AppTextStyles.title.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                                children: [
                                  TextSpan(
                                    text: '  Sistema de facturación',
                                    style: AppTextStyles.small.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar menú',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.textSecondary,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: isCompactMobile ? 210 : 240,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                userDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
                        onHoverOpen: isDesktop ? () => _openGroup(i) : null,
                        onHoverExit: isDesktop ? () => _closeGroup(i) : null,
                        onTapHeader: () => _toggleGroup(i),
                        itemBuilder: (item) => _DrawerMenuItem(
                          icon: item.icon,
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        branding.departmentName,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.small.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                          icon: Icon(
                            Icons.logout_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
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

List<_DrawerMenuGroup> _buildDrawerGroups(List<AppNavigationSection> sections) {
  final itemsByRoute = <String, AppNavigationItem>{};
  for (final section in sections) {
    for (final item in section.items) {
      itemsByRoute.putIfAbsent(item.route, () => item);
    }
  }

  AppNavigationItem? pick(String route) => itemsByRoute.remove(route);

  final groups = <_DrawerMenuGroup>[];
  void addGroup(String title, IconData icon, List<String> routes) {
    final items = <AppNavigationItem>[
      for (final route in routes)
        if (pick(route) case final item?) item,
    ];
    if (items.isEmpty) return;
    groups.add(_DrawerMenuGroup(title: title, icon: icon, items: items));
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
  final salesCreditItem = pick(Routes.ventasCreditos);
  final reportsItem = pick(Routes.ventas);
  if (ventasItems.isNotEmpty ||
      inventoryItems.isNotEmpty ||
      cashItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Ventas POS',
        icon: Icons.point_of_sale_rounded,
        items: const [],
        trailingItems: [
          ...inventoryItems,
          if (salesCreditItem != null) salesCreditItem,
          if (reportsItem != null) reportsItem,
        ],
        subgroups: [
          if (ventasItems.isNotEmpty)
            _DrawerMenuSubgroup(
              title: 'Ventas',
              icon: Icons.receipt_long_outlined,
              items: ventasItems,
            ),
          if (cashItems.isNotEmpty)
            _DrawerMenuSubgroup(
              title: 'Movimiento efectivo',
              icon: Icons.account_balance_wallet_outlined,
              items: cashItems,
            ),
        ],
      ),
    );
  }

  addGroup('Operaciones', Icons.work_outline_rounded, [
    Routes.serviceOrders,
    Routes.mediaGallery,
    Routes.documentFlows,
  ]);
  addGroup('Clientes', Icons.groups_2_outlined, [
    Routes.clientes,
    Routes.crmComercial,
  ]);
  addGroup('Administración', Icons.admin_panel_settings_outlined, [
    Routes.contabilidad,
    Routes.administracion,
  ]);
  addGroup('Nómina y equipo', Icons.payments_outlined, [
    Routes.nomina,
    Routes.serviceOrderCommissions,
    Routes.misPagos,
    Routes.ponche,
    Routes.users,
  ]);
  addGroup('Comunicación', Icons.campaign_outlined, [
    Routes.publicidad,
    Routes.whatsapp,
    Routes.whatsappCrm,
    Routes.ai,
  ]);
  addGroup('Sistema', Icons.tune_rounded, [
    Routes.manualInterno,
    Routes.amonestaciones,
    Routes.configuracion,
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
    this.trailingItems = const [],
    this.subgroups = const [],
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
  final List<AppNavigationItem> trailingItems;
  final List<_DrawerMenuSubgroup> subgroups;

  int get count =>
      items.length +
      trailingItems.length +
      subgroups.fold<int>(0, (sum, subgroup) => sum + subgroup.items.length);

  bool containsActiveRoute(String location) {
    bool active(AppNavigationItem item) {
      return isNavigationRouteActive(location, item.route);
    }

    return items.any(active) ||
        trailingItems.any(active) ||
        subgroups.any((subgroup) => subgroup.items.any(active));
  }
}

class _DrawerMenuSubgroup {
  const _DrawerMenuSubgroup({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
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
    final foreground = selected || expanded
        ? AppColors.primary
        : AppColors.textPrimary;
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
                              fontWeight: FontWeight.w900,
                              fontSize: compact ? 13.8 : 14.6,
                            ),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 26),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (selected || expanded)
                                ? Colors.white.withValues(alpha: 0.82)
                                : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${group.count}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.small.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: foreground,
                          ),
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
                      for (final subgroup in group.subgroups)
                        _DrawerMenuSubgroupSection(
                          subgroup: subgroup,
                          compact: compact,
                          itemBuilder: itemBuilder,
                        ),
                      for (final item in group.trailingItems) itemBuilder(item),
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

class _DrawerMenuSubgroupSection extends StatefulWidget {
  const _DrawerMenuSubgroupSection({
    required this.subgroup,
    required this.compact,
    required this.itemBuilder,
  });

  final _DrawerMenuSubgroup subgroup;
  final bool compact;
  final Widget Function(AppNavigationItem item) itemBuilder;

  @override
  State<_DrawerMenuSubgroupSection> createState() =>
      _DrawerMenuSubgroupSectionState();
}

class _DrawerMenuSubgroupSectionState
    extends State<_DrawerMenuSubgroupSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final subgroup = widget.subgroup;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 5 : 6, bottom: compact ? 2 : 3),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: compact ? 38 : 40,
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
                decoration: BoxDecoration(
                  color: _expanded
                      ? AppColors.primary.withValues(alpha: 0.07)
                      : AppColors.surfaceMuted.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.9),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      subgroup.icon,
                      size: compact ? 17 : 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subgroup.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.small.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 12.2 : 12.8,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: EdgeInsets.only(left: compact ? 8 : 10, top: 3),
              child: Column(
                children: [
                  for (final item in subgroup.items) widget.itemBuilder(item),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

class _DrawerMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool compact;
  final bool selected;
  final bool showIndicator;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
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
                      Icon(
                        widget.icon,
                        size: widget.compact ? 19 : 20,
                        color: foreground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : (_hovered
                                      ? FontWeight.w600
                                      : FontWeight.w500),
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
