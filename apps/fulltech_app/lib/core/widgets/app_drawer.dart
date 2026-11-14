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

/// Recordatorio de atajos en el pie del drawer.
///
/// Es informativo y est├í separado de las opciones de navegaci├│n: mantiene la
/// columna equilibrada sin a├ídir acciones nuevas.
class _DrawerShortcutHint extends StatelessWidget {
  const _DrawerShortcutHint({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget keyCap(String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFD5E3F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B2A3A).withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        value,
        style: AppTextStyles.body.copyWith(
          fontSize: compact ? 9.5 : 10,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );

    return Row(
      children: [
        Container(
          width: compact ? 26 : 28,
          height: compact ? 26 : 28,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.keyboard_outlined,
            size: 15,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Atajos de teclado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11.6 : 12.2,
            ),
          ),
        ),
        keyCap('Ctrl'),
        const SizedBox(width: 4),
        keyCap('K'),
      ],
    );
  }
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF1F6FD)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE7F5)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFD5E3F5)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const AppIcon(
              AppIcons.cloud,
              size: 19,
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
                    fontSize: compact ? 12.5 : 13.2,
                    letterSpacing: -0.15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.35),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Sincronizado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 10.2 : 10.8,
                      ),
                    ),
                  ],
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
                      icon: AppIcons.user,
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
                    icon: AppIcons.settings,
                    tooltip: 'Configuración',
                    selected: isNavigationRouteActive(
                      location,
                      Routes.configuracion,
                    ),
                    onTap: onSettingsTap,
                  ),
                  _MobileDrawerFooterIconButton(
                    compact: compact,
                    icon: AppIcons.logout,
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
                  icon: AppIcons.users,
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
  final AppIconData icon;
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
            child: AppIcon(
              icon,
              color: foreground,
              size: compact ? 20 : 21,
              semanticLabel: tooltip,
            ),
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
  final AppIconData icon;
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
              AppIcon(
                icon,
                color: foreground,
                size: compact ? 19 : 20,
                semanticLabel: label,
              ),
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

/// Wordmark del producto.
///
/// `Cloud` entra con un fundido + deslizamiento suave y lleva el acento azul
/// de la marca, de modo que la cabecera transmite movimiento sin distraer.
class _DrawerWordmark extends StatelessWidget {
  const _DrawerWordmark({
    required this.compact,
    this.onDark = false,
    this.inline = false,
  });

  final bool compact;
  final bool onDark;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final accent = onDark ? const Color(0xFF9CD2FF) : AppColors.primary;
    final cloud = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: Text(
        'Cloud',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.body.copyWith(
          color: accent,
          fontSize: inline ? (compact ? 17 : 18) : (compact ? 12.2 : 13),
          fontWeight: FontWeight.w900,
          letterSpacing: inline ? -0.2 : 0.7,
          height: 1.1,
        ),
      ),
    );

    // En la cabecera m├│vil se muestra al lado de "FullPOS": se deja flexible
    // para que nunca desborde en pantallas estrechas.
    if (inline) return Flexible(child: cloud);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FullPOS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.title.copyWith(
            fontSize: compact ? 16.5 : 17.5,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0E2340),
            letterSpacing: -0.3,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        cloud,
      ],
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
    // el overlay ra├¡z (sigue montado aunque el drawer se destruya), mientras
    // que el contexto del Navigator ra├¡z no puede resolverlo por s├¡ mismo.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // Capturar el controller ANTES de cerrar el drawer. Al hacer
    // `Navigator.pop(context)` el drawer se destruye, y usar `ref` (WidgetRef
    // del drawer) despu├®s lanzar├¡a:
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
    // Capturar el overlay ANTES de cerrar el drawer (el overlay ra├¡z sigue
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
      final detail = printResult == null
          ? 'Efectivo contado y cierre registrado correctamente.'
          : printResult.success
          ? 'Cierre registrado y ticket enviado a la impresora.'
          : 'Cierre registrado. ${printResult.message}';
      showCashToast(
        rootContext,
        'Turno cerrado',
        detail: detail,
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

  Future<void> _openTurnFromDrawer(BuildContext context) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    // Capturar el overlay ANTES de cerrar el drawer (el overlay ra├¡z sigue
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
      // Solo se anuncia el ├®xito cuando el estado autoritativo confirma el
      // turno abierto (ver cash_turn_menu_button._openCash).
      if (ref.read(activeCashSessionControllerProvider).valueOrNull == null) {
        showCashToast(
          rootContext,
          'La caja no quedó abierta en el servidor. Intenta de nuevo.',
          isError: true,
          overlay: overlay,
        );
        return;
      }
      showCashToast(
        rootContext,
        'Turno abierto',
        detail: 'La caja está lista para operar.',
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
    // Snapshot declarativo: la configuraci├│n de empresa se observa UNA sola vez
    // aqu├¡ (build del drawer) y se pasa ya resuelta al constructor de
    // navegaci├│n, que es puro. As├¡ `buildAppNavigationSections` nunca ejecuta
    // `ref.watch` dentro de un helper durante el build.
    final multiWarehouseEnabled =
        ref.watch(companySettingsProvider).valueOrNull?.multiWarehouseEnabled ??
        false;
    final wholesalePriceListsEnabled =
        ref
            .watch(companySettingsProvider)
            .valueOrNull
            ?.wholesalePriceListsEnabled ??
        false;
    // Interruptor e-CF de la EMPRESA, le├¡do de la MISMA configuraci├│n que el
    // Drawer ya observa: el men├║ no a├▒ade ninguna petici├│n de red. Mientras la
    // configuraci├│n no est├® confirmada vale `false`, as├¡ que un error de red
    // nunca deja el m├│dulo a la vista.
    final ecfEnabled =
        ref.watch(companySettingsProvider).valueOrNull?.ecfEnabled ?? false;
    // Piloto: la elegibilidad la confirma el backend y viaja en la MISMA
    // configuraci├│n que el Drawer ya observa, as├¡ que el men├║ no a├▒ade ninguna
    // petici├│n de red. Mientras no est├® confirmada vale `false`.
    final ecfPilotEligible =
        ref.watch(companySettingsProvider).valueOrNull?.ecfPilotEligible ??
        false;
    final sections = buildAppNavigationSections(
      currentUser,
      multiWarehouseEnabled: multiWarehouseEnabled,
      wholesalePriceListsEnabled: wholesalePriceListsEnabled,
      ecfEnabled: ecfEnabled,
      ecfPilotEligible: ecfPilotEligible,
    );
    // Estado autoritativo del turno (fuente de verdad = backend). El drawer
    // m├│vil observa el MISMO provider que el resto de la app: si el turno
    // cambia (realtime/poll/resumed/reconexi├│n), el grupo "Turno" se
    // reconstruye sin necesidad de cerrar/reabrir el drawer.
    final cashSession = ref.watch(activeCashSessionControllerProvider);
    final cashUnverified = ref.watch(cashStateUnverifiedProvider);
    final cashStaleShift = ref.watch(cashStateStaleShiftProvider);
    final hasOpenShift = cashSession.valueOrNull?.isOpen == true;
    // Estado confirmado contra el backend (no loading, no error, no cach├®
    // no sincronizada). Regla #28: un error de red NO es "turno cerrado".
    final cashConfirmed = cashSession.hasValue && !cashUnverified;
    final groups = _buildDrawerGroups(
      sections,
      mobileLayout: !isDesktop,
      role: role,
      hasOpenShift: hasOpenShift,
      cashConfirmed: cashConfirmed,
      cashStaleShift: cashStaleShift,
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
          color: isDesktop ? const Color(0xFFFBFCFE) : const Color(0xFFF8FBFF),
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
                              vertical: isCompactMobile ? 12 : 13,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Colors.white, Color(0xFFF2F7FF)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFD6E4F7),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.07,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _DrawerAppLogo(
                                  width: isCompactMobile ? 52 : 56,
                                  height: isCompactMobile ? 44 : 48,
                                ),
                                SizedBox(width: isCompactMobile ? 10 : 12),
                                Expanded(
                                  child: _DrawerWordmark(
                                    compact: isCompactMobile,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar menú',
                                  onPressed: () => Navigator.pop(context),
                                  icon: AppIcon(
                                    AppIcons.close,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                    semanticLabel: 'Cerrar menú',
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFFEFF4FB),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'FullPOS',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.title.copyWith(
                                              color: Colors.white,
                                              fontSize: isCompactMobile
                                                  ? 24
                                                  : 26,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          _DrawerWordmark(
                                            compact: isCompactMobile,
                                            onDark: true,
                                            inline: true,
                                          ),
                                        ],
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
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DrawerShortcutHint(compact: isCompactMobile),
                              const SizedBox(height: 8),
                              _DrawerCloudFooter(compact: isCompactMobile),
                            ],
                          )
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
  bool cashStaleShift = false,
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
  void addGroup(
    String title,
    AppIconData icon,
    List<String> routes, {
    String? assetIcon,
  }) {
    final items = <AppNavigationItem>[
      for (final route in routes)
        if (pick(route) case final item?) item,
    ];
    if (items.isEmpty) return;
    groups.add(
      _DrawerMenuGroup(
        title: title,
        icon: icon,
        assetIcon: assetIcon,
        items: items,
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
  final catalogItem = pick(Routes.catalogo);
  final stockAdjustmentItem = pick(Routes.catalogoStock);
  final categoriesItem = pick(Routes.catalogoCategorias);
  final inventoryCountItem = pick(Routes.catalogoConteo);
  final kardexItem = pick(Routes.catalogoKardex);
  final priceListsItem = pick(Routes.listasPrecios);
  final warehousesItem = pick(Routes.configuracionAlmacenes);
  // Los accesos de efectivo (registrar entrada, registrar salida e historial de
  // movimientos) ya NO forman parte de `sections`: viven en el selector
  // superior ┬½Turno┬╗ (CashTurnMenuButton) y en el grupo ┬½Turno┬╗ del drawer,
  // construidos directamente. As├¡ tampoco pueden reaparecer en los grupos
  // comod├¡n (┬½M├ís m├│dulos┬╗ / ┬½Otros┬╗), que se alimentan de lo que sobra.
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
      if (priceListsItem != null)
        const AppNavigationItem(
          icon: Icons.price_change_outlined,
          title: 'Listas precios',
          route: Routes.listasPrecios,
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
        icon: AppIcons.product,
        assetIcon: 'assets/iconos/menu-inventario.png',
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
        icon: AppIcons.purchase,
        assetIcon: 'assets/iconos/menu-compras.png',
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

  // El grupo ┬½Contabilidad┬╗ se retir├│ de la navegaci├│n (ver
  // `buildAppNavigationSections`). Sus rutas y pantallas siguen existiendo,
  // pero ya no se construye el grupo para ninguna plataforma.

  if (mobileLayout) {
    // Grupo "Turno" reactivo al estado autoritativo del backend:
    //  - ABIERTO confirmado  ÔåÆ Turno actual + Cerrar turno + Historial.
    //  - CERRADO confirmado  ÔåÆ Abrir turno + Historial.
    //  - LOADING/ERROR/NO SINCRONIZADO ÔåÆ ├¡tem neutro DESHABILITADO + Historial
    //    (no se presenta ninguna acci├│n cr├¡tica como confirmada).
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
      // Entradas y salidas manuales: SOLO con turno abierto confirmado por el
      // backend. `_handleItemTap` intercepta estas dos rutas y abre el di├ílogo
      // existente (`showCashMovementDialog`), nunca una pantalla nueva.
      if (hasOpenShift && cashConfirmed)
        if (hasPermission(role, AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.add_circle_outline_rounded,
            title: 'Registrar entrada',
            route: Routes.cajaRegistrarIngreso,
          ),
      if (hasOpenShift && cashConfirmed)
        if (hasPermission(role, AppPermission.viewSales))
          const AppNavigationItem(
            icon: Icons.remove_circle_outline_rounded,
            title: 'Registrar salida',
            route: Routes.cajaRegistrarSalida,
          ),
      if (hasPermission(role, AppPermission.viewSales))
        const AppNavigationItem(
          icon: Icons.receipt_long_outlined,
          title: 'Historial de movimientos',
          route: Routes.cajaMovimientos,
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
        icon: AppIcons.cashRegister,
        assetIcon: 'assets/iconos/menu-turno.png',
        items: turnosItems,
        openOnHover: false,
        featured: true,
        subtitle: cashStaleShift
            ? 'Turno de otro día — ciérralo'
            : !cashConfirmed
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
          icon: AppIcons.sales,
          assetIcon: 'assets/iconos/menu-ventas.png',
          items: ventasItems,
          openOnHover: false,
        ),
      );
    }
    if (clientItems.isNotEmpty) {
      groups.add(
        _DrawerMenuGroup(
          title: 'Cliente',
          icon: AppIcons.users,
          assetIcon: 'assets/iconos/menu-clientes.png',
          items: clientItems,
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
          icon: AppIcons.report,
          assetIcon: 'assets/iconos/menu-reportes.png',
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
    ]);

    addGroup('Facturación electrónica', AppIcons.receipt, [Routes.ecf]);
    return groups;
  }

  if (ventasItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Ventas',
        icon: AppIcons.sales,
        assetIcon: 'assets/iconos/menu-ventas.png',
        items: ventasItems,
        openOnHover: false,
      ),
    );
  }
  if (clientItems.isNotEmpty) {
    groups.add(
      _DrawerMenuGroup(
        title: 'Cliente',
        icon: AppIcons.users,
        assetIcon: 'assets/iconos/menu-clientes.png',
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
        icon: AppIcons.report,
        assetIcon: 'assets/iconos/menu-reportes.png',
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
  addGroup('Operaciones', AppIcons.business, [
    Routes.serviceOrders,
    Routes.mediaGallery,
    Routes.redTecnica,
  ]);

  addGroup('Facturación electrónica', AppIcons.receipt, [Routes.ecf]);
  return groups;
}

class _DrawerMenuGroup {
  const _DrawerMenuGroup({
    required this.title,
    required this.icon,
    required this.items,
    this.assetIcon,
    this.openOnHover = true,
    this.featured = false,
    this.subtitle,
    this.statusColor,
  });

  final String title;

  /// Icono propio del sistema (HugeIcons) para el m├│dulo.
  final AppIconData icon;

  /// PNG propio del m├│dulo (p. ej. `assets/iconos/menu-ventas.png`).
  /// Si el archivo no existe, se renderiza [icon] como respaldo.
  final String? assetIcon;

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

/// Glifo del m├│dulo en el encabezado del grupo.
///
/// Usa el PNG propio cuando existe; si el archivo todav├¡a no est├í en el
/// bundle, cae automaticamente al icono del sistema ([AppIcons]) sin romper
/// ni dejar huecos en la lista.
class _DrawerGroupGlyph extends StatelessWidget {
  const _DrawerGroupGlyph({
    required this.icon,
    required this.size,
    required this.color,
    this.assetIcon,
    this.semanticLabel,
    this.strokeWidth = 1.7,
  });

  final AppIconData icon;
  final String? assetIcon;
  final double size;
  final Color color;
  final String? semanticLabel;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final asset = assetIcon;
    if (asset == null || asset.isEmpty) {
      return AppIcon(
        icon,
        size: size,
        color: color,
        strokeWidth: strokeWidth,
        semanticLabel: semanticLabel,
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => AppIcon(
        icon,
        size: size,
        color: color,
        strokeWidth: strokeWidth,
        semanticLabel: semanticLabel,
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
    final highlighted = selected || expanded;
    final foreground = desktop
        ? (highlighted ? const Color(0xFF0B2E6F) : AppColors.textPrimary)
        : featured
        ? const Color(0xFF102A6B)
        : const Color(0xFF0F1F45);
    final iconColor = desktop
        ? (highlighted ? Colors.white : AppColors.primary)
        : featured
        ? Colors.white
        : const Color(0xFF155EEF);
    final headerBg = desktop
        ? (highlighted
              ? AppColors.primary.withValues(alpha: 0.07)
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
              ? (compact ? 2 : 3)
              : featured
              ? 12
              : 5,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: desktop && expanded ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(desktop ? 14 : 16),
            border: Border.all(
              color: desktop && expanded
                  ? AppColors.border
                  : Colors.transparent,
            ),
            boxShadow: desktop && expanded
                ? [
                    BoxShadow(
                      color: const Color(0xFF0B2A3A).withValues(alpha: 0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
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
                  mouseCursor: SystemMouseCursors.click,
                  onTap: onTapHeader,
                  hoverColor: AppColors.primary.withValues(alpha: 0.045),
                  splashColor: AppColors.primary.withValues(alpha: 0.08),
                  highlightColor: AppColors.primary.withValues(alpha: 0.05),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: desktop
                        ? (compact ? 42 : 46)
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
                        width: desktop ? (highlighted ? 1 : 0) : 0.9,
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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: desktop
                              ? (compact ? 34 : 36)
                              : featured
                              ? 30
                              : 36,
                          height: desktop
                              ? (compact ? 34 : 36)
                              : featured
                              ? 30
                              : 36,
                          decoration: BoxDecoration(
                            color: desktop
                                ? (highlighted
                                      ? AppColors.primary
                                      : AppColors.primary.withValues(
                                          alpha: 0.09,
                                        ))
                                : featured
                                ? AppColors.primary
                                : const Color(0xFFE0ECFF),
                            borderRadius: BorderRadius.circular(
                              featured ? 999 : 10,
                            ),
                            border: Border.all(
                              color: desktop
                                  ? (highlighted
                                        ? AppColors.primary
                                        : const Color(0xFFD5E3F7))
                                  : Colors.transparent,
                            ),
                            boxShadow: desktop && highlighted
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.26,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: _DrawerGroupGlyph(
                              icon: group.icon,
                              assetIcon: group.assetIcon,
                              size: desktop
                                  ? (compact ? 18 : 20)
                                  : featured
                                  ? 16
                                  : 19,
                              color: iconColor,
                              semanticLabel: group.title,
                              strokeWidth: compact ? 1.8 : 1.7,
                            ),
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
                                  fontWeight: highlighted || featured
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: desktop
                                      ? (compact ? 13.9 : 14.5)
                                      : featured
                                      ? (compact ? 14.4 : 15)
                                      : (compact ? 14.7 : 15.3),
                                  height: 1.15,
                                  letterSpacing: -0.2,
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
                        AnimatedRotation(
                          turns: hasSubmenu && expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            hasSubmenu
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.chevron_right_rounded,
                            color: desktop
                                ? (highlighted
                                      ? AppColors.primary
                                      : AppColors.textMuted)
                                : featured
                                ? AppColors.primary
                                : const Color(0xFF64748B),
                            size: desktop ? (compact ? 20 : 22) : 21,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasSubmenu)
                // Las entradas del submenú solo se construyen cuando el grupo
                // está desplegado. Con `AnimatedCrossFade` el hijo oculto se
                // seguía maquetando y quedaba en el árbol fuera del área
                // visible: no se veía, no se podía pulsar, y el menú no
                // desplazaba hasta él (las últimas opciones eran inalcanzables
                // en pantallas bajas o con escalado alto).
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
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
                        )
                      : const SizedBox(width: double.infinity),
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
                    ? AppColors.primary.withValues(alpha: 0.075)
                    : (_hovered
                          ? AppColors.primary.withValues(alpha: 0.045)
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
        ? AppColors.primary
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
                mouseCursor: widget.enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
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
                      ? (widget.compact ? 42 : 46)
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
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      SizedBox(width: selected ? 10 : 11),
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
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: widget.desktop
                                ? (widget.compact ? 13.6 : 14.2)
                                : 13.4,
                            height: 1.2,
                            letterSpacing: -0.1,
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
