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
import '../utils/money_formatters.dart';
import 'app_navigation.dart';

const String _drawerCloseTurnAction = '__drawer_close_turn__';
const String _drawerOpenTurnAction = '__drawer_open_turn__';

class AppDrawer extends ConsumerStatefulWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _DrawerCloudFooter extends StatelessWidget {
  const _DrawerCloudFooter({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.cloud_done_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sistema en la nube',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 12.5 : 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Datos sincronizados por empresa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 10.5 : 11.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDrawerAccountFooter extends StatelessWidget {
  const _MobileDrawerAccountFooter({
    required this.compact,
    required this.location,
    required this.canManageUsers,
    required this.onProfileTap,
    required this.onUsersTap,
    required this.onSettingsTap,
    required this.onLogoutTap,
  });

  final bool compact;
  final String location;
  final bool canManageUsers;
  final VoidCallback onProfileTap;
  final VoidCallback onUsersTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogoutTap;

  @override
  Widget build(BuildContext context) {
    const footerBorder = Color(0xFFE8EEF5);
    const logoutColor = Color(0xFFDC2626);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: footerBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MobileDrawerFooterButton(
                      compact: compact,
                      icon: Icons.badge_outlined,
                      label: 'Perfil',
                      selected: isNavigationRouteActive(
                        location,
                        Routes.profile,
                      ),
                      onTap: onProfileTap,
                    ),
                  ),
                  _MobileDrawerFooterIconButton(
                    compact: compact,
                    icon: Icons.settings_outlined,
                    tooltip: 'Configuración',
                    selected: isNavigationRouteActive(
                      location,
                      Routes.configuracion,
                    ),
                    onTap: onSettingsTap,
                  ),
                  _MobileDrawerFooterIconButton(
                    compact: compact,
                    icon: Icons.logout_rounded,
                    tooltip: 'Cerrar sesión',
                    color: logoutColor,
                    onTap: onLogoutTap,
                  ),
                ],
              ),
              if (canManageUsers) ...[
                const Divider(height: 1, color: footerBorder),
                _MobileDrawerFooterButton(
                  compact: compact,
                  icon: Icons.manage_accounts_outlined,
                  label: 'Usuario',
                  selected: isNavigationRouteActive(location, Routes.users),
                  onTap: onUsersTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileDrawerFooterButton extends StatelessWidget {
  const _MobileDrawerFooterButton({
    required this.compact,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primary : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: compact ? 42 : 46,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: compact ? 19 : 20),
              SizedBox(width: compact ? 10 : 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: foreground,
                    fontSize: compact ? 14.2 : 14.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileDrawerFooterIconButton extends StatelessWidget {
  const _MobileDrawerFooterIconButton({
    required this.compact,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.color,
  });

  final bool compact;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground =
        color ?? (selected ? AppColors.primary : AppColors.textSecondary);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: compact ? 38 : 42,
            height: compact ? 42 : 46,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: foreground, size: compact ? 20 : 21),
          ),
        ),
      ),
    );
  }
}

class _DrawerAppLogo extends StatelessWidget {
  const _DrawerAppLogo({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCFE0FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1957E6).withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/image/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.point_of_sale_rounded,
            color: AppColors.primary,
            size: 34,
          );
        },
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
    // Capturar el overlay ANTES de cerrar el drawer. El overlay del drawer es
    // el overlay raíz (sigue montado aunque el drawer se destruya), mientras
    // que el contexto del Navigator raíz no puede resolverlo por sí mismo.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // Capturar el controller ANTES de cerrar el drawer. Al hacer
    // `Navigator.pop(context)` el drawer se destruye, y usar `ref` (WidgetRef
    // del drawer) después lanzaría:
    //   Bad state: Cannot use "ref" after the widget was disposed.
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
        detail: type == 'IN'
            ? 'Se agregaron ${formatRdCurrencyAccounting(input.amount)} a la caja.'
            : 'Se retiraron ${formatRdCurrencyAccounting(input.amount)} de la caja.',
        overlay: overlay,
      );
    } catch (error) {
      if (!rootContext.mounted) return;
      showCashToast(
        rootContext,
        resolveCashError(error),
        isError: true,
        overlay: overlay,
      );
    }
  }

  Future<void> _closeTurnFromDrawer(BuildContext context) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final repository = ref.read(cashRepositoryProvider);
    // Capturar el overlay ANTES de cerrar el drawer (el overlay raíz sigue
    // montado aunque el drawer se destruya tras el pop).
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // Capturar el controller ANTES de cerrar el drawer: el ref del drawer
    // queda invalidado al destruirse el drawer tras el pop.
    final controller = ref.read(activeCashSessionControllerProvider.notifier);
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;

    try {
      final summary = await repository.summary();
      if (!rootContext.mounted) return;
      final result = await showCloseShiftDialog(
        rootContext,
        expectedCash: summary.expectedCash,
        onCloseShift: (amount) => controller.close(amount),
      );
      if (!rootContext.mounted || result?.success != true) return;
      await controller.refresh();
      if (!rootContext.mounted) return;
      final printResult = result?.printResult;
      final message = printResult == null
          ? 'Turno cerrado'
          : printResult.success
          ? 'Turno cerrado e impreso'
          : 'Turno cerrado. ${printResult.message}';
      showCashToast(rootContext, message, overlay: overlay);
    } catch (error) {
      if (!rootContext.mounted) return;
      showCashToast(
        rootContext,
        resolveCashError(error),
        isError: true,
        overlay: overlay,
      );
    }
  }

  Future<void> _openTurnFromDrawer(BuildContext context) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    // Capturar el overlay ANTES de cerrar el drawer (el overlay raíz sigue
    // montado aunque el drawer se destruya tras el pop).
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // Capturar el controller ANTES de cerrar el drawer: el ref del drawer
    // queda invalidado al destruirse el drawer tras el pop.
    final controller = ref.read(activeCashSessionControllerProvider.notifier);
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;

    try {
      final opened = await showOpenCashDialog(
        rootContext,
        onOpenShift: (amount) => controller.open(amount),
      );
      if (!rootContext.mounted || opened != true) return;
      await controller.refresh();
      if (!rootContext.mounted) return;
      showCashToast(rootContext, 'Caja abierta', overlay: overlay);
    } catch (error) {
      if (!rootContext.mounted) return;
      showCashToast(
        rootContext,
        resolveCashError(error),
        isError: true,
        overlay: overlay,
      );
    }
  }

  Future<void> _handleItemTap(
    BuildContext context,
    AppNavigationItem item,
  ) async {
    if (!item.enabled) return;
    if (item.route == _drawerCloseTurnAction) {
      await _closeTurnFromDrawer(context);
      return;
    }
    if (item.route == _drawerOpenTurnAction) {
      await _openTurnFromDrawer(context);
      return;
    }
    final permission = RouteAccess.permissionForLocation(item.route);
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: permission,
      reason: 'Entrar a ${item.title}',
      routeLocation: item.route,
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

  Future<void> _handleLogout(BuildContext context) async {
    final auth = ref.read(authStateProvider.notifier);
    Navigator.pop(context);
    await auth.logout();
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
    // Estado autoritativo del turno (fuente de verdad = backend). El drawer
    // móvil observa el MISMO provider que el resto de la app: si el turno
    // cambia (realtime/poll/resumed/reconexión), el grupo "Turno" se
    // reconstruye sin necesidad de cerrar/reabrir el drawer.
    final cashSession = ref.watch(activeCashSessionControllerProvider);
    final cashUnverified = ref.watch(cashStateUnverifiedProvider);
    final hasOpenShift = cashSession.valueOrNull?.isOpen == true;
    // Estado confirmado contra el backend (no loading, no error, no caché
    // no sincronizada). Regla #28: un error de red NO es "turno cerrado".
    final cashConfirmed = cashSession.hasValue && !cashUnverified;
    final groups = _buildDrawerGroups(
      sections,
      mobileLayout: !isDesktop,
      role: role,
      hasOpenShift: hasOpenShift,
      cashConfirmed: cashConfirmed,
    );
    final location = safeCurrentLocation(context);
    final expandedGroupIndex = isDesktop
        ? (_openGroupIndex ?? -1)
        : _openGroupIndex;
    final drawerWidth = isDesktop ? 318.0 : mediaQuery.size.width * 0.80;
    final panelShadow = BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(6, 0),
    );

    return Drawer(
      width: drawerWidth,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDesktop ? AppColors.surface : const Color(0xFFF8FBFF),
          gradient: isDesktop
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF5FAFF),
                    Color(0xFFFFFFFF),
                    Color(0xFFF1F7FF),
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
                      isDesktop ? 12 : 4,
                      isDesktop ? 14 : 10,
                      isDesktop ? 10 : 2,
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
                                _DrawerAppLogo(
                                  width: isCompactMobile ? 58 : 66,
                                  height: isCompactMobile ? 48 : 56,
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
                              SizedBox(
                                height: 46,
                                width: 46,
                                child: IconButton(
                                  tooltip: 'Cerrar menú',
                                  onPressed: () => Navigator.pop(context),
                                  icon: AppIcon(
                                    AppIcons.close,
                                    size: 21,
                                    color: const Color(0xFF334155),
                                    semanticLabel: 'Cerrar menú',
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop
                            ? 10
                            : isCompactMobile
                            ? 14
                            : 16,
                        isDesktop ? 4 : 6,
                        isDesktop
                            ? 10
                            : isCompactMobile
                            ? 14
                            : 16,
                        8,
                      ),
                      children: [
                        for (var i = 0; i < groups.length; i++)
                          _DrawerMenuGroupTile(
                            group: groups[i],
                            index: i,
                            compact: isCompactMobile,
                            desktop: isDesktop,
                            expanded:
                                groups[i].hasSubmenu && expandedGroupIndex == i,
                            selected: groups[i].containsActiveRoute(location),
                            onHoverOpen: isDesktop && groups[i].openOnHover
                                ? () => _openGroup(i)
                                : null,
                            onHoverExit: isDesktop && groups[i].openOnHover
                                ? () => _closeGroup(i)
                                : null,
                            onTapHeader: () {
                              if (!groups[i].hasSubmenu) {
                                _handleItemTap(context, groups[i].items.first);
                                return;
                              }
                              _toggleGroup(i);
                            },
                            itemBuilder: (item) => _DrawerMenuItem(
                              icon: item.icon,
                              appIcon: item.appIcon,
                              title: item.title,
                              compact: isCompactMobile,
                              desktop: isDesktop,
                              enabled: item.enabled,
                              selected:
                                  item.enabled &&
                                  isNavigationRouteActive(location, item.route),
                              showIndicator: item.showIndicator,
                              onTap: () => _handleItemTap(context, item),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isDesktop)
                    const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop
                          ? 12
                          : isCompactMobile
                          ? 14
                          : 16,
                      isDesktop ? 8 : 6,
                      isDesktop
                          ? 12
                          : isCompactMobile
                          ? 14
                          : 16,
                      isDesktop ? 12 : 14,
                    ),
                    child: isDesktop
                        ? _DrawerCloudFooter(compact: isCompactMobile)
                        : _MobileDrawerAccountFooter(
                            compact: isCompactMobile,
                            location: location,
                            canManageUsers: hasPermission(
                              role,
                              AppPermission.manageUsers,
                            ),
                            onProfileTap: () => _handleItemTap(
                              context,
                              const AppNavigationItem(
                                icon: Icons.badge_outlined,
                                title: 'Perfil',
                                route: Routes.profile,
                              ),
                            ),
                            onUsersTap: () => _handleItemTap(
                              context,
                              const AppNavigationItem(
                                icon: Icons.manage_accounts_outlined,
                                title: 'Usuario',
                                route: Routes.users,
                              ),
                            ),
                            onSettingsTap: () => _handleItemTap(
                              context,
                              const AppNavigationItem(
                                icon: Icons.settings_outlined,
                                title: 'Configuración',
                                route: Routes.configuracion,
                              ),
                            ),
                            onLogoutTap: () => _handleLogout(context),
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
  required bool hasOpenShift,
  required bool cashConfirmed,
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

  void addInventoryGroup() {
    if (inventoryItems.isEmpty) return;
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
            title: 'Ajuste stock',
            route: Routes.catalogoStock,
          ),
          AppNavigationItem(
            icon: Icons.category_outlined,
            title: 'Categorías',
            route: Routes.catalogoCategorias,
          ),
          AppNavigationItem(
            icon: Icons.fact_check_outlined,
            title: 'Recuento',
            route: Routes.catalogoConteo,
          ),
        ],
        openOnHover: false,
      ),
    );
  }

  void addPurchasesGroup() {
    if (purchasesItem == null) return;
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

  void addAccountingGroup() {
    final items = <AppNavigationItem>[
      if (pick(Routes.contabilidadDepositos) case final item?) item,
      if (pick(Routes.contabilidadFacturaFiscal) case final item?) item,
      if (pick(Routes.contabilidadPagosPendientes) case final item?) item,
      if (pick(Routes.nomina) case final item?) item,
    ];
    if (items.isEmpty) return;
    groups.add(
      _DrawerMenuGroup(
        title: 'Contabilidad',
        icon: Icons.account_balance_outlined,
        items: items,
        openOnHover: false,
      ),
    );
  }

  if (mobileLayout) {
    // Grupo "Turno" reactivo al estado autoritativo del backend:
    //  - ABIERTO confirmado  → Turno actual + Cerrar turno + Historial.
    //  - CERRADO confirmado  → Abrir turno + Historial.
    //  - LOADING/ERROR/NO SINCRONIZADO → ítem neutro DESHABILITADO + Historial
    //    (no se presenta ninguna acción crítica como confirmada).
    final turnosItems = <AppNavigationItem>[
      if (!cashConfirmed)
        const AppNavigationItem(
          icon: Icons.cloud_off_outlined,
          title: 'Estado del turno no disponible',
          route: Routes.caja,
          enabled: false,
        ),
      if (hasOpenShift && cashConfirmed)
        if (hasPermission(role, AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.point_of_sale_outlined,
            title: 'Turno actual',
            route: Routes.caja,
          ),
      if (hasOpenShift && cashConfirmed)
        if (hasPermission(role, AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.lock_clock_outlined,
            title: 'Cerrar turno',
            route: _drawerCloseTurnAction,
          ),
      if (!hasOpenShift && cashConfirmed)
        if (hasPermission(role, AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.lock_open_outlined,
            title: 'Abrir turno',
            route: _drawerOpenTurnAction,
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
        icon: Icons.play_circle_outline_rounded,
        items: turnosItems,
        openOnHover: false,
        featured: true,
      ),
    );

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

    discard([
      Routes.apps,
      Routes.licencias,
      Routes.actualizaciones,
      Routes.configuracionEmpresa,
      Routes.configuracion,
    ]);

    addInventoryGroup();
    addPurchasesGroup();
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
    addAccountingGroup();

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
  addInventoryGroup();
  addPurchasesGroup();
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
  addAccountingGroup();
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
    this.featured = false,
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
  final bool openOnHover;
  final bool featured;

  bool get hasSubmenu => items.length > 1;

  bool containsActiveRoute(String location) {
    bool active(AppNavigationItem item) {
      if (!item.enabled) return false;
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
    required this.desktop,
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
  final bool desktop;
  final bool expanded;
  final bool selected;
  final VoidCallback onTapHeader;
  final VoidCallback? onHoverOpen;
  final VoidCallback? onHoverExit;
  final Widget Function(AppNavigationItem item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final hasSubmenu = group.hasSubmenu;
    final featured = group.featured && !desktop;
    final foreground = desktop
        ? AppColors.textPrimary
        : featured
        ? Colors.white
        : const Color(0xFF0F172A);
    final iconColor = selected && !desktop
        ? const Color(0xFF2563EB)
        : desktop
        ? foreground
        : featured
        ? Colors.white
        : const Color(0xFF172554);
    final headerBg = desktop
        ? (selected || expanded
              ? AppColors.primary.withValues(alpha: 0.09)
              : Colors.transparent)
        : featured
        ? Colors.transparent
        : (selected
              ? const Color(0xFFE8F1FF)
              : Colors.white.withValues(alpha: 0.76));
    final borderColor = desktop ? Colors.transparent : const Color(0xFFE8EEF5);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: onHoverOpen == null ? null : (_) => onHoverOpen!(),
      onExit: onHoverExit == null ? null : (_) => onHoverExit!(),
      child: Padding(
        padding: EdgeInsets.only(bottom: desktop ? (compact ? 4 : 5) : 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: desktop && expanded
                ? AppColors.surfaceMuted.withValues(alpha: 0.36)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(desktop ? 14 : 16),
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(desktop ? 15 : 14),
                  onTap: onTapHeader,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: desktop
                        ? (compact ? 46 : 50)
                        : featured
                        ? (compact ? 64 : 70)
                        : (compact ? 52 : 56),
                    padding: EdgeInsets.symmetric(
                      horizontal: desktop ? (compact ? 9 : 10) : 12,
                    ),
                    decoration: BoxDecoration(
                      color: headerBg,
                      gradient: featured
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2563EB), Color(0xFF0F766E)],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(
                        desktop
                            ? 13
                            : featured
                            ? 18
                            : 14,
                      ),
                      border: Border.all(
                        color: featured
                            ? Colors.white.withValues(alpha: 0.28)
                            : borderColor,
                        width: desktop ? 0 : 0.9,
                      ),
                      boxShadow: desktop
                          ? null
                          : [
                              BoxShadow(
                                color: featured
                                    ? const Color(
                                        0xFF2563EB,
                                      ).withValues(alpha: 0.24)
                                    : Colors.black.withValues(alpha: 0.025),
                                blurRadius: featured ? 18 : 6,
                                offset: Offset(0, featured ? 8 : 2),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: desktop ? (compact ? 32 : 34) : 40,
                          height: desktop ? (compact ? 32 : 34) : 40,
                          decoration: BoxDecoration(
                            color: desktop
                                ? foreground.withValues(alpha: 0.10)
                                : featured
                                ? Colors.white.withValues(alpha: 0.18)
                                : selected
                                ? const Color(0xFFE0ECFF)
                                : const Color(0xFFF2F6FC),
                            borderRadius: BorderRadius.circular(
                              desktop ? 10 : 11,
                            ),
                          ),
                          child: Icon(
                            group.icon,
                            color: iconColor,
                            size: desktop ? (compact ? 18 : 19) : 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  color: foreground,
                                  fontWeight: featured || selected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  fontSize: desktop
                                      ? (compact ? 13.8 : 14.6)
                                      : featured
                                      ? (compact ? 16 : 17)
                                      : (compact ? 15.2 : 15.8),
                                ),
                              ),
                              if (featured) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Abre y controla tu turno',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body.copyWith(
                                    color: Colors.white.withValues(alpha: 0.84),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (featured) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Inicio',
                              style: AppTextStyles.body.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                        Icon(
                          hasSubmenu
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          color: desktop
                              ? AppColors.textSecondary
                              : const Color(0xFF334155),
                          size: desktop ? (compact ? 20 : 22) : 21,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasSubmenu)
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? (compact ? 6 : 7) : 7,
                      desktop ? 2 : 5,
                      desktop ? (compact ? 6 : 7) : 7,
                      desktop ? (compact ? 5 : 6) : 6,
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
                  duration: const Duration(milliseconds: 200),
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
  final bool desktop;
  final bool selected;
  final bool showIndicator;
  final bool enabled;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    this.appIcon,
    required this.title,
    required this.compact,
    required this.desktop,
    required this.selected,
    this.showIndicator = false,
    this.enabled = true,
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
    if (!widget.enabled) return;
    _pressController.forward();
  }

  void _handlePointerUp() {
    if (!widget.enabled) return;
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final enabled = widget.enabled;
    final tileBg = enabled
        ? (widget.desktop
              ? (selected
                    ? AppColors.primary.withValues(alpha: 0.09)
                    : (_hovered
                          ? AppColors.surfaceMuted.withValues(alpha: 0.72)
                          : Colors.transparent))
              : (selected
                    ? const Color(0xFFE8F1FF)
                    : (_hovered
                          ? Colors.white.withValues(alpha: 0.72)
                          : Colors.transparent)))
        : Colors.transparent;
    final foreground = !enabled
        ? const Color(0xFFA7B4C4)
        : selected
        ? const Color(0xFF2563EB)
        : widget.desktop
        ? AppColors.textSecondary
        : const Color(0xFF334155);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.desktop ? 2 : 1.5),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
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
                onTap: widget.enabled
                    ? () {
                        _handlePointerUp();
                        widget.onTap();
                      }
                    : null,
                splashColor: AppColors.primary.withValues(alpha: 0.15),
                highlightColor: AppColors.primary.withValues(alpha: 0.08),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: widget.desktop
                      ? (widget.compact ? 44 : 48)
                      : (widget.compact ? 38 : 40),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.desktop
                        ? (widget.compact ? 10 : 12)
                        : 12,
                    vertical: widget.desktop ? 8 : 6,
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
                              ? const Color(0xFF2563EB)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      SizedBox(width: selected ? 9 : 12),
                      widget.appIcon == null
                          ? Icon(
                              widget.icon,
                              size: widget.desktop
                                  ? (widget.compact ? 19 : 20)
                                  : 18,
                              color: foreground,
                            )
                          : AppIcon(
                              widget.appIcon!,
                              size: widget.desktop
                                  ? (widget.compact ? 19 : 20)
                                  : 18,
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
                            fontSize: widget.desktop
                                ? (widget.compact ? 13.8 : 14.4)
                                : 13.4,
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
