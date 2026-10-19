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
import '../company/company_settings_repository.dart';
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
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: footerBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.055),
                blurRadius: 16,
                offset: const Offset(0, 5),
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
          height: compact ? 38 : 42,
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
    // Snapshot declarativo: la configuración de empresa se observa UNA sola vez
    // aquí (build del drawer) y se pasa ya resuelta al constructor de
    // navegación, que es puro. Así `buildAppNavigationSections` nunca ejecuta
    // `ref.watch` dentro de un helper durante el build.
    final multiWarehouseEnabled =
        ref.watch(companySettingsProvider).valueOrNull?.multiWarehouseEnabled ??
        false;
    final sections = buildAppNavigationSections(
      currentUser,
      multiWarehouseEnabled: multiWarehouseEnabled,
    );
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
                    Color(0xFFF2F8FF),
                    Color(0xFFFAFDFF),
                    Color(0xFFEAF3FF),
                    Color(0xFFDDEBFF),
                  ],
                  stops: [0, 0.42, 0.76, 1],
                ),
          boxShadow: [panelShadow],
        ),
        child: Stack(
          children: [
            if (!isDesktop)
              const Positioned.fill(child: _MobileDrawerBackgroundTexture()),
            if (!isDesktop)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 118,
                child: const _MobileDrawerPremiumHeaderBackground(),
              ),
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
                        : Container(
                            height: isCompactMobile ? 78 : 84,
                            padding: EdgeInsets.only(
                              left: isCompactMobile ? 4 : 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'FullPOS',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.title.copyWith(
                                          color: Colors.white,
                                          fontSize: isCompactMobile ? 25 : 27,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        'Cloud',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.90,
                                          ),
                                          fontSize: isCompactMobile ? 12 : 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 42,
                                  width: 42,
                                  child: IconButton(
                                    tooltip: 'Cerrar menú',
                                    onPressed: () => Navigator.pop(context),
                                    icon: AppIcon(
                                      AppIcons.close,
                                      size: 20,
                                      color: Colors.white,
                                      semanticLabel: 'Cerrar menú',
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
  final catalogItem = pick(Routes.catalogo);
  final stockAdjustmentItem = pick(Routes.catalogoStock);
  final categoriesItem = pick(Routes.catalogoCategorias);
  final inventoryCountItem = pick(Routes.catalogoConteo);
  final kardexItem = pick(Routes.catalogoKardex);
  final warehousesItem = pick(Routes.configuracionAlmacenes);
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
    final items = <AppNavigationItem>[
      if (catalogItem != null)
        const AppNavigationItem(
          icon: Icons.table_rows_outlined,
          title: 'Productos',
          route: Routes.catalogo,
        ),
      if (stockAdjustmentItem != null)
        const AppNavigationItem(
          icon: Icons.tune_outlined,
          title: 'Ajuste stock',
          route: Routes.catalogoStock,
        ),
      if (categoriesItem != null)
        const AppNavigationItem(
          icon: Icons.category_outlined,
          title: 'Categorías',
          route: Routes.catalogoCategorias,
        ),
      if (inventoryCountItem != null)
        const AppNavigationItem(
          icon: Icons.fact_check_outlined,
          title: 'Recuento',
          route: Routes.catalogoConteo,
        ),
      if (kardexItem != null)
        const AppNavigationItem(
          icon: Icons.history_rounded,
          title: 'Kardex',
          route: Routes.catalogoKardex,
        ),
      if (warehousesItem != null)
        const AppNavigationItem(
          icon: Icons.warehouse_outlined,
          title: 'Almacenes',
          route: Routes.configuracionAlmacenes,
        ),
    ];
    if (items.isEmpty) return;
    groups.add(
      _DrawerMenuGroup(
        title: 'Inventario',
        icon: Icons.inventory_2_outlined,
        items: items,
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
        subtitle: !cashConfirmed
            ? 'Estado no disponible'
            : hasOpenShift
            ? 'Abierto y operando'
            : 'Cerrado, listo para abrir',
        statusColor: !cashConfirmed
            ? AppColors.warning
            : hasOpenShift
            ? AppColors.success
            : AppColors.primary,
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
    this.subtitle,
    this.statusColor,
  });

  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
  final bool openOnHover;
  final bool featured;
  final String? subtitle;
  final Color? statusColor;

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

class _MobileDrawerPremiumHeaderBackground extends StatelessWidget {
  const _MobileDrawerPremiumHeaderBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E6BFF), AppColors.primary, Color(0xFF1EA7F2)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: CustomPaint(painter: _MobileDrawerPremiumHeaderPainter()),
    );
  }
}

class _MobileDrawerBackgroundTexture extends StatelessWidget {
  const _MobileDrawerBackgroundTexture();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _MobileDrawerBackgroundTexturePainter()),
    );
  }
}

class _MobileDrawerBackgroundTexturePainter extends CustomPainter {
  const _MobileDrawerBackgroundTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final lowerGlow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x552E6BFF), Color(0x002E6BFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.72, size.height * 0.91),
              radius: size.width * 0.74,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.91),
      size.width * 0.74,
      lowerGlow,
    );

    final linePaint = Paint()
      ..color = const Color(0x1F3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final accentLinePaint = Paint()
      ..color = const Color(0x113B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    const gap = 34.0;
    for (double y = 96; y < size.height - 18; y += gap) {
      final path = Path()
        ..moveTo(-24, y)
        ..cubicTo(
          size.width * 0.18,
          y - 10,
          size.width * 0.48,
          y + 13,
          size.width + 24,
          y - 4,
        );
      canvas.drawPath(path, linePaint);
    }
    for (double y = 128; y < size.height - 26; y += gap * 1.7) {
      final path = Path()
        ..moveTo(-20, y)
        ..cubicTo(
          size.width * 0.26,
          y + 14,
          size.width * 0.58,
          y - 12,
          size.width + 20,
          y + 6,
        );
      canvas.drawPath(path, accentLinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MobileDrawerPremiumHeaderPainter extends CustomPainter {
  const _MobileDrawerPremiumHeaderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final diagonal = Path()
      ..moveTo(size.width * 0.48, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.82, size.height)
      ..lineTo(size.width * 0.34, size.height)
      ..close();
    canvas.drawPath(
      diagonal,
      Paint()..color = Colors.white.withValues(alpha: 0.055),
    );

    final highlight = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final highlightPath = Path()
      ..moveTo(size.width * 0.72, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.78)
      ..lineTo(size.width * 0.58, size.height)
      ..close();
    canvas.drawPath(highlightPath, highlight);

    final lowerShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF0B3AA8).withValues(alpha: 0.09),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, lowerShade);

    final bottomFade = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00F2F8FF), Color(0x9CF2F8FF)],
          ).createShader(
            Rect.fromLTWH(
              0,
              size.height * 0.72,
              size.width,
              size.height * 0.28,
            ),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28),
      bottomFade,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TurnStatusPulse extends StatelessWidget {
  const _TurnStatusPulse({required this.color, required this.compact});

  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 6.5 : 7.0;
    return TweenAnimationBuilder<double>(
      key: ValueKey(color),
      tween: Tween(begin: 0.55, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.32), blurRadius: 5),
          ],
        ),
      ),
    );
  }
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
        ? const Color(0xFF102A6B)
        : const Color(0xFF0F1F45);
    final iconColor = selected && !desktop
        ? const Color(0xFF2563EB)
        : desktop
        ? foreground
        : featured
        ? Colors.white
        : const Color(0xFF155EEF);
    final headerBg = desktop
        ? (selected || expanded
              ? AppColors.primary.withValues(alpha: 0.09)
              : Colors.transparent)
        : featured
        ? const Color(0xFFF1F7FF)
        : (selected ? const Color(0xFFE8F1FF) : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: onHoverOpen == null ? null : (_) => onHoverOpen!(),
      onExit: onHoverExit == null ? null : (_) => onHoverExit!(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: desktop
              ? (compact ? 4 : 5)
              : featured
              ? 12
              : 5,
        ),
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
                  borderRadius: BorderRadius.circular(
                    desktop
                        ? 15
                        : featured
                        ? 16
                        : 13,
                  ),
                  onTap: onTapHeader,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: desktop
                        ? (compact ? 46 : 50)
                        : featured
                        ? (compact ? 58 : 62)
                        : (compact ? 48 : 52),
                    padding: EdgeInsets.symmetric(
                      horizontal: desktop
                          ? (compact ? 9 : 10)
                          : featured
                          ? 13
                          : 10,
                    ),
                    decoration: BoxDecoration(
                      color: headerBg,
                      gradient: null,
                      borderRadius: BorderRadius.circular(
                        desktop
                            ? 13
                            : featured
                            ? 16
                            : 13,
                      ),
                      border: Border.all(
                        color: featured
                            ? const Color(0xFFE1ECFF)
                            : selected
                            ? AppColors.secondaryBorder
                            : Colors.transparent,
                        width: desktop ? 0 : 0.9,
                      ),
                      boxShadow: desktop
                          ? null
                          : featured
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.06,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: desktop
                              ? (compact ? 32 : 34)
                              : featured
                              ? 30
                              : 36,
                          height: desktop
                              ? (compact ? 32 : 34)
                              : featured
                              ? 30
                              : 36,
                          decoration: BoxDecoration(
                            color: desktop
                                ? foreground.withValues(alpha: 0.10)
                                : featured
                                ? AppColors.primary
                                : selected
                                ? const Color(0xFFE0ECFF)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              featured ? 999 : 11,
                            ),
                          ),
                          child: Icon(
                            group.icon,
                            color: iconColor,
                            size: desktop
                                ? (compact ? 18 : 19)
                                : featured
                                ? 17
                                : 20,
                          ),
                        ),
                        SizedBox(width: featured ? 11 : 10),
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
                                      : FontWeight.w700,
                                  fontSize: desktop
                                      ? (compact ? 13.8 : 14.6)
                                      : featured
                                      ? (compact ? 14.4 : 15)
                                      : (compact ? 14.7 : 15.3),
                                ),
                              ),
                              if (featured) ...[
                                const SizedBox(height: 2),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.18),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Row(
                                    key: ValueKey(
                                      group.subtitle ?? group.title,
                                    ),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _TurnStatusPulse(
                                        color:
                                            group.statusColor ??
                                            AppColors.primary,
                                        compact: compact,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          group.subtitle ?? 'Estado del turno',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.body.copyWith(
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: compact ? 10.4 : 10.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          hasSubmenu
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.chevron_right_rounded,
                          color: desktop
                              ? AppColors.textSecondary
                              : featured
                              ? AppColors.primary
                              : const Color(0xFF64748B),
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
