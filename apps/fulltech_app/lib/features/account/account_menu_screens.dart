import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../core/app_access/app_access_links.dart';
import '../../core/app_update/app_update_controller.dart';
import '../../core/app_update/app_update_models.dart';
import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/license/license_repository.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/local_file_bytes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../modules/cash/cash_turn_menu_button.dart';
import 'delete_account_dialog.dart';
import '../settings/data/cloud_backup_service.dart';
import '../settings/ui/printer_settings_page.dart';

class AccountAppsScreen extends StatelessWidget {
  const AccountAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountSidePanelScaffold(
      icon: Icons.apps_rounded,
      title: 'Apps',
      subtitle: 'Accesos para usar FullPOS Cloud en distintos dispositivos.',
      children: [
        for (final channel in AppAccessLinks.visibleChannels())
          _AccessChannelTile(
            icon: channel.icon,
            title: channel.title,
            status: channel.status,
            description: channel.description,
            actionLabel: channel.actionLabel,
            actionIcon: channel.actionIcon,
            onPressed: () => safeOpenUrl(context, channel.uri),
          ),
      ],
    );
  }
}

class AccountLicensesScreen extends ConsumerWidget {
  const AccountLicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final license = ref.watch(licenseStatusProvider);

    return _AccountSidePanelScaffold(
      icon: Icons.verified_user_outlined,
      title: 'Licencias',
      subtitle: 'Control de prueba, acceso y límites del sistema.',
      children: [
        license.when(
          data: (value) => _LicensePlanCard(
            license: value,
            responsible: _licenseResponsible(value, user?.email),
          ),
          loading: () => const _SurfacePanel(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) => _StatusBanner(
            icon: Icons.error_outline_rounded,
            title: 'No se pudo cargar la licencia',
            message: '$error',
            accent: AppColors.error,
          ),
        ),
      ],
    );
  }
}

class AccountUpdatesScreen extends ConsumerStatefulWidget {
  const AccountUpdatesScreen({super.key});

  @override
  ConsumerState<AccountUpdatesScreen> createState() =>
      _AccountUpdatesScreenState();
}

class _AccountUpdatesScreenState extends ConsumerState<AccountUpdatesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(appUpdateProvider.notifier).checkNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final installed = state.installedRelease;
    final update = state.updateInfo;
    final progress = state.downloadProgress;
    final hasUpdate = update?.update == true;
    final busy =
        state.phase == AppUpdatePhase.checking ||
        state.phase == AppUpdatePhase.downloadingUpdate ||
        state.phase == AppUpdatePhase.installingUpdate;
    final showInlineTitle = MediaQuery.sizeOf(context).width < 900;

    Future<void> handlePendingAction() async {
      if (hasUpdate && update?.hasDownloadUrl == true) {
        await safeOpenUrl(context, Uri.parse(update!.downloadUrl!));
        return;
      }
      if (hasUpdate) {
        await controller.retryBlockedUpdate();
        return;
      }
      await controller.checkNow(force: true);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
            children: [
              if (showInlineTitle) ...[
                Text('Actualizaciones', style: _titleStyle(28)),
                const SizedBox(height: 6),
                Text(
                  'Verifica la versión instalada y cualquier actualización pendiente.',
                  style: _bodyStyle(),
                ),
                const SizedBox(height: 22),
              ],
              _UpdatePanel(
                icon: Icons.verified_outlined,
                title: 'Actualización actual',
                accent: AppColors.secondary,
                rows: [
                  _DetailRow(
                    'Versión instalada',
                    installed == null
                        ? 'No detectada'
                        : '${installed.currentVersion}+${installed.currentBuild}',
                  ),
                  _DetailRow(
                    'Plataforma',
                    installed?.platform.displayName ?? 'No detectada',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _UpdatePanel(
                icon: _updateIcon(state.phase),
                title: 'Actualización pendiente',
                accent: _updateAccent(state.phase),
                message: state.message ?? _updateMessage(state),
                progress: progress,
                rows: [
                  _DetailRow(
                    'Estado',
                    hasUpdate ? 'Disponible' : _pendingUpdateLabel(state.phase),
                  ),
                  _DetailRow(
                    'Nueva versión',
                    hasUpdate
                        ? '${update?.latestVersion ?? 'Sin versión'}'
                              '${update?.latestBuild == null ? '' : '+${update!.latestBuild}'}'
                        : 'Sin actualización pendiente',
                  ),
                ],
                action: FilledButton.icon(
                  onPressed: busy ? null : handlePendingAction,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          hasUpdate
                              ? Icons.system_update_alt_rounded
                              : Icons.refresh_rounded,
                        ),
                  label: Text(
                    busy
                        ? _busyUpdateLabel(state.phase)
                        : hasUpdate
                        ? 'Actualizar ahora'
                        : 'Buscar actualización',
                  ),
                  style: _filledButtonStyle(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _SettingsHubScaffold(children: [_DeleteAccountLaunchCard()]);
  }
}

class _DeleteAccountLaunchCard extends ConsumerWidget {
  const _DeleteAccountLaunchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsActionCard(
      icon: Icons.delete_forever_outlined,
      title: 'Eliminar mi cuenta',
      description: 'Requiere contraseña y confirmación del servidor.',
      accent: AppColors.error,
      onTap: () => showDeleteAccountDialog(context, ref),
    );
  }
}

class AccountCompanySettingsScreen extends ConsumerWidget {
  const AccountCompanySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);

    return _SettingsDetailScaffold(
      title: 'Empresa',
      subtitle: 'Datos usados en facturas, cotizaciones, tickets y reportes.',
      action: OutlinedButton.icon(
        onPressed: () => ref.invalidate(companySettingsProvider),
        icon: const Icon(Icons.sync_rounded),
        label: const Text('Sincronizar'),
        style: _outlinedButtonStyle(),
      ),
      child: _SectionPanel(
        title: 'Datos de empresa',
        children: [
          company.maybeWhen(
            data: (settings) => _CompanySettingsEditor(settings: settings),
            orElse: () => const _ParagraphBlock(
              title: 'Configuración de empresa',
              text:
                  'Los datos de la empresa se sincronizan con el servidor para usarse en documentos internos y fiscales.',
            ),
          ),
        ],
      ),
    );
  }
}

class AccountPrinterSettingsScreen extends StatelessWidget {
  const AccountPrinterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsDetailScaffold(
      title: 'Impresora',
      subtitle:
          'Controla cómo se imprimen tickets, copias y datos del negocio.',
      child: _SectionPanel(
        title: 'Impresión y tickets',
        children: [PrinterSettingsPage(embedded: true)],
      ),
    );
  }
}

class AccountBackupSettingsScreen extends StatelessWidget {
  const AccountBackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsDetailScaffold(
      title: 'Backup',
      subtitle: 'Guarda una copia local de la información sincronizada.',
      child: _SectionPanel(
        title: 'Backup y recuperación',
        children: [_BackupSection()],
      ),
    );
  }
}

class AccountParametersScreen extends StatelessWidget {
  const AccountParametersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsDetailScaffold(
      title: 'Parámetros',
      subtitle: 'Opciones generales para organizar la operación del sistema.',
      child: _SectionPanel(
        title: 'Parámetros importantes',
        children: [
          _SettingsOptionGrid(
            items: [
              _SettingsOptionData(
                icon: Icons.inventory_2_outlined,
                title: 'Inventario',
                value: 'Stock, productos, costos y sincronización.',
              ),
              _SettingsOptionData(
                icon: Icons.point_of_sale_outlined,
                title: 'Ventas',
                value: 'Facturación, créditos y reportes operativos.',
              ),
              _SettingsOptionData(
                icon: Icons.lock_outline_rounded,
                title: 'Seguridad',
                value: 'Acceso controlado por roles y permisos.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccountDocumentsSettingsScreen extends ConsumerWidget {
  const AccountDocumentsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    return _SettingsDetailScaffold(
      title: 'Documentos',
      subtitle:
          'Información usada en facturas, cotizaciones, tickets y cartas.',
      action: OutlinedButton.icon(
        onPressed: () => ref.invalidate(companySettingsProvider),
        icon: const Icon(Icons.sync_rounded),
        label: const Text('Sincronizar'),
        style: _outlinedButtonStyle(),
      ),
      child: _SectionPanel(
        title: 'Datos para documentos',
        children: [
          company.maybeWhen(
            data: (settings) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsOptionGrid(
                  items: [
                    _SettingsOptionData(
                      icon: Icons.storefront_rounded,
                      title: 'Empresa',
                      value: settings.companyName,
                    ),
                    _SettingsOptionData(
                      icon: Icons.badge_outlined,
                      title: 'RNC',
                      value: settings.rnc,
                    ),
                    _SettingsOptionData(
                      icon: Icons.location_on_outlined,
                      title: 'Dirección',
                      value: settings.address,
                    ),
                    _SettingsOptionData(
                      icon: Icons.person_outline_rounded,
                      title: 'Representante',
                      value: settings.legalRepresentativeName,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ParagraphBlock(
                  title: 'Pie de identidad',
                  text: settings.description.trim().isEmpty
                      ? 'Agrega una descripción comercial en Empresa para reforzar tus documentos.'
                      : settings.description.trim(),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => context.go(Routes.configuracionEmpresa),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar datos de empresa'),
                    style: _filledButtonStyle(),
                  ),
                ),
              ],
            ),
            orElse: () => const _ParagraphBlock(
              title: 'Documentos',
              text: 'Carga la configuración de empresa para revisar los datos.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHubScaffold extends ConsumerWidget {
  const _SettingsHubScaffold({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final user = ref.watch(authStateProvider).user;
    final backButton = IconButton(
      tooltip: 'Volver',
      onPressed: () => context.go(Routes.cotizaciones),
      icon: const Icon(Icons.arrow_back_rounded),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(
        title: 'Configuración',
        showLogo: false,
        showDepartmentLabel: false,
        leading: backButton,
        trailing: const SizedBox.shrink(),
        actions: mobile
            ? null
            : const [
                CashTurnMenuButton(),
                SizedBox(width: 8),
                _SettingsCompanyAccountMenu(),
              ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mobile ? 760 : 620),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 20 : 22,
              mobile ? 16 : 26,
              mobile ? 20 : 22,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: children.length,
                    padding: EdgeInsets.only(bottom: mobile ? 24 : 18),
                    separatorBuilder: (_, _) =>
                        SizedBox(height: mobile ? 10 : 8),
                    itemBuilder: (context, index) => children[index],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsDetailScaffold extends ConsumerWidget {
  const _SettingsDetailScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showInlineTitle = MediaQuery.sizeOf(context).width < 900;
    final compact = MediaQuery.sizeOf(context).width < 640;
    final user = ref.watch(authStateProvider).user;
    final backButton = IconButton(
      tooltip: 'Volver',
      onPressed: () => context.go(Routes.cotizaciones),
      icon: const Icon(Icons.arrow_back_rounded),
    );
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 22,
            compact ? 8 : 24,
            compact ? 14 : 22,
            28,
          ),
          children: [
            Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(subtitle, style: _bodyStyle())),
                if (action != null) ...[const SizedBox(width: 12), action!],
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(
        title: '',
        showLogo: false,
        showDepartmentLabel: false,
        leading: backButton,
        trailing: const SizedBox.shrink(),
        actions: null,
      ),
      body: showInlineTitle
          ? SafeArea(left: false, right: false, bottom: false, child: content)
          : content,
    );
  }
}

class _SettingsCompanyAccountMenu extends ConsumerWidget {
  const _SettingsCompanyAccountMenu();

  void _goAfterMenu(BuildContext context, String route) {
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (context.mounted) context.go(route);
    });
  }

  void _activate(BuildContext menuContext, BuildContext context, String route) {
    Navigator.of(menuContext).pop();
    _goAfterMenu(context, route);
  }

  void _logout(BuildContext menuContext, BuildContext context, WidgetRef ref) {
    Navigator.of(menuContext).pop();
    Future<void>.delayed(const Duration(milliseconds: 80), () async {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) context.go(Routes.login);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final companyName = company.maybeWhen(
      data: (settings) => _compactSettingsCompanyName(settings.companyName),
      orElse: () => 'Empresa',
    );
    final logoBase64 = company.maybeWhen(
      data: (settings) => settings.logoBase64?.trim(),
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PopupMenuButton<String>(
        tooltip: 'Empresa',
        offset: const Offset(0, 44),
        elevation: 8,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDDE7EE)),
        ),
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 340),
        itemBuilder: (menuContext) => [
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.person_outline_rounded,
              label: 'Perfil',
              onTap: () => _activate(menuContext, context, Routes.profile),
              helpText:
                  'Revisa y actualiza los datos del usuario actual y su foto de perfil.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.groups_2_outlined,
              label: 'Usuarios',
              onTap: () => _activate(menuContext, context, Routes.users),
              helpText:
                  'Administra usuarios, roles, permisos y accesos de la empresa.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.verified_user_outlined,
              label: 'Licencias',
              onTap: () => _activate(menuContext, context, Routes.licencias),
              helpText:
                  'Consulta el plan, uso de usuarios/productos y vigencia de la licencia.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.business_center_outlined,
              label: 'Empresa',
              onTap: () =>
                  _activate(menuContext, context, Routes.configuracionEmpresa),
              helpText:
                  'Configura datos fiscales, dirección, representante, logo y datos comerciales.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.print_outlined,
              label: 'Impresora',
              onTap: () => _activate(
                menuContext,
                context,
                Routes.configuracionImpresora,
              ),
              helpText:
                  'Ajusta impresora, copias, papel, formato y datos visibles del ticket.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.cloud_sync_outlined,
              label: 'Backup',
              onTap: () =>
                  _activate(menuContext, context, Routes.configuracionBackup),
              helpText:
                  'Descarga respaldo local y valida ZIPs de backup para recuperación asistida.',
            ),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesión',
              danger: true,
              onTap: () => _logout(menuContext, context, ref),
              helpText:
                  'Cierra la sesión actual en este equipo y vuelve al inicio.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _SettingsCompanyMenuRow(
              icon: Icons.delete_forever_outlined,
              label: 'Eliminar mi cuenta',
              danger: true,
              onTap: () {
                Navigator.of(menuContext).pop();
                Future<void>.delayed(const Duration(milliseconds: 80), () {
                  if (context.mounted) showDeleteAccountDialog(context, ref);
                });
              },
              helpText:
                  'Abre la configuración donde se solicita contraseña y confirmación antes de eliminar una cuenta.',
            ),
          ),
        ],
        child: _SettingsCompanyButton(
          label: companyName,
          logoBase64: logoBase64,
        ),
      ),
    );
  }
}

class _SettingsCompanyButton extends StatelessWidget {
  const _SettingsCompanyButton({required this.label, required this.logoBase64});

  final String label;
  final String? logoBase64;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1957E6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF7DA2FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1957E6).withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SettingsCompanyLogo(logoBase64: logoBase64),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _SettingsCompanyLogo extends StatelessWidget {
  const _SettingsCompanyLogo({required this.logoBase64});

  final String? logoBase64;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeSettingsLogo(logoBase64);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? const Icon(Icons.storefront_rounded, size: 15, color: Colors.white)
          : Image.memory(bytes, fit: BoxFit.cover),
    );
  }
}

class _SettingsCompanyMenuRow extends StatelessWidget {
  const _SettingsCompanyMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.helpText,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String helpText;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return _SettingsCompanyMenuAction(
      icon: icon,
      label: label,
      onTap: onTap,
      helpText: helpText,
      danger: danger,
    );
  }
}

class _SettingsCompanyMenuAction extends StatefulWidget {
  const _SettingsCompanyMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.helpText,
    required this.danger,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String helpText;
  final bool danger;

  @override
  State<_SettingsCompanyMenuAction> createState() =>
      _SettingsCompanyMenuActionState();
}

class _SettingsCompanyMenuActionState
    extends State<_SettingsCompanyMenuAction> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger
        ? const Color(0xFFDC2626)
        : const Color(0xFF1957E6);
    final color = widget.danger
        ? const Color(0xFFB91C1C)
        : const Color(0xFF183548);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: widget.danger
                            ? const Color(0xFFFFF1F1)
                            : const Color(0xFFF3F7FF),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: widget.danger
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFDDEAFF),
                        ),
                      ),
                      child: Icon(widget.icon, color: accent, size: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _showHelp ? 'Ocultar ayuda' : 'Ayuda',
                      onPressed: () => setState(() => _showHelp = !_showHelp),
                      icon: Icon(
                        _showHelp
                            ? Icons.help_rounded
                            : Icons.help_outline_rounded,
                      ),
                      iconSize: 17,
                      color: _showHelp
                          ? const Color(0xFF1957E6)
                          : const Color(0xFF7C8DA1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      splashRadius: 17,
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: widget.danger
                          ? const Color(0xFFF87171)
                          : const Color(0xFF9AA8B6),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFE),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFDDE7EE)),
                  ),
                  child: Text(
                    widget.helpText,
                    softWrap: true,
                    style: const TextStyle(
                      color: Color(0xFF52667C),
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                crossFadeState: _showHelp
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactSettingsCompanyName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'Empresa';
  if (normalized.length <= 18) return normalized;
  final firstSegment = normalized.split(' ').first.trim();
  if (firstSegment.length >= 3) return firstSegment;
  return normalized.substring(0, 18);
}

Uint8List? _decodeSettingsLogo(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

class _SettingsActionCard extends StatelessWidget {
  const _SettingsActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _titleStyle(15.5).copyWith(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({
    required this.icon,
    required this.title,
    required this.accent,
    required this.rows,
    this.message,
    this.progress,
    this.action,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final List<Widget> rows;
  final String? message;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TileIcon(icon: icon, color: accent, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _titleStyle(18)),
                    if ((message ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(message!.trim(), style: _bodyStyle()),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 8,
                backgroundColor: const Color(0xFFDDE7EE),
                color: accent,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...rows,
        ],
      ),
    );
  }
}

class _AccountSidePanelScaffold extends StatelessWidget {
  const _AccountSidePanelScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width < 620
        ? MediaQuery.sizeOf(context).width
        : 560.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(left: BorderSide(color: Color(0xFFD3E0E7))),
          ),
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                _PanelHeader(icon: icon, title: title, subtitle: subtitle),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) => children[index],
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: children.length,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 13),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDDE7EE))),
      ),
      child: Row(
        children: [
          _HeaderIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(18)),
                const SizedBox(height: 2),
                Text(subtitle, style: _bodyStyle()),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Volver',
            onPressed: () => AppNavigator.goBack(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _AccessChannelTile extends StatelessWidget {
  const _AccessChannelTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.description,
    this.actionLabel,
    this.actionIcon,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String status;
  final String description;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(15)),
                const SizedBox(height: 3),
                Text(status, style: _strongBodyStyle()),
                const SizedBox(height: 8),
                Text(description, style: _bodyStyle()),
                if (actionLabel != null && onPressed != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(
                      actionIcon ?? Icons.open_in_new_rounded,
                      size: 17,
                    ),
                    label: Text(actionLabel!),
                    style: _outlinedButtonStyle(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensePlanCard extends StatefulWidget {
  const _LicensePlanCard({required this.license, required this.responsible});

  final LicenseStatusModel license;
  final String responsible;

  @override
  State<_LicensePlanCard> createState() => _LicensePlanCardState();
}

class _LicensePlanCardState extends State<_LicensePlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final license = widget.license;
    final accent = _licenseAccent(license.status);
    final statusLabel = _licenseStatusLabel(license.status);
    final account = license.account;
    final businessName = _firstText([
      account?.businessName,
      license.companyName,
    ]);
    final rows = <_LicenseSummaryRow>[
      _LicenseSummaryRow('Responsable', widget.responsible),
      _LicenseSummaryRow('Plan', license.typeLabel),
      if (license.acquiredAt != null)
        _LicenseSummaryRow('Inicio', _dateLabel(license.acquiredAt)),
      if (license.periodEndsAt != null)
        _LicenseSummaryRow('Vence', _dateLabel(license.periodEndsAt)),
      if (license.daysRemaining != null)
        _LicenseSummaryRow('Tiempo restante', _licenseSubtitle(license)),
    ];
    final moreRows = <_LicenseSummaryRow>[
      _LicenseSummaryRow('RNC/Cédula', account?.taxId),
      _LicenseSummaryRow('Teléfono', account?.businessPhone),
      _LicenseSummaryRow('WhatsApp', account?.responsibleWhatsapp),
      _LicenseSummaryRow('Dirección', account?.businessAddress),
      _LicenseSummaryRow('Clave', license.licenseKey),
      _LicenseSummaryRow('Notas', license.notes),
      if (license.licenseBlockedAt != null)
        _LicenseSummaryRow(
          'Bloqueada el',
          _dateLabel(license.licenseBlockedAt),
        ),
    ].where((row) => row.value.trim().isNotEmpty).toList(growable: false);

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final heading = Row(
                children: [
                  _TileIcon(
                    icon: Icons.workspace_premium_outlined,
                    color: accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName.isEmpty ? 'Empresa' : businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _titleStyle(15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${license.planLabel} · $statusLabel · ${_licenseSubtitle(license)}',
                          style: _bodyStyle(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final pill = _StatusPill(
                label: _licenseStatusLabel(license.status),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 10), pill],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  pill,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (!license.isUsable)
            _StatusBanner(
              icon: Icons.lock_outline_rounded,
              title: 'Acceso bloqueado',
              message: license.blockReason ?? 'La licencia no está disponible.',
              accent: AppColors.error,
            )
          else if (license.status == 'TRIAL')
            _StatusBanner(
              icon: Icons.hourglass_top_rounded,
              title: 'Prueba gratis activa',
              message: 'Incluye 7 días de uso inicial con límites controlados.',
              accent: AppColors.warning,
            ),
          const SizedBox(height: 12),
          _LicenseCompactRows(rows: rows),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _UsageMeter(
                  icon: Icons.people_outline_rounded,
                  title: 'Usuarios',
                  used: license.users,
                  max: license.maxUsers,
                  accent: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UsageMeter(
                  icon: Icons.inventory_2_outlined,
                  title: 'Productos',
                  used: license.products,
                  max: license.maxProducts,
                  accent: const Color(0xFF1957E6),
                ),
              ),
            ],
          ),
          if (moreRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                label: Text(_expanded ? 'Ver menos' : 'Ver más'),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 14, color: Color(0xFFDDE7EE)),
              _LicenseCompactRows(rows: moreRows),
            ],
          ],
        ],
      ),
    );
  }
}

class _LicenseSummaryRow {
  const _LicenseSummaryRow(this.label, String? value) : value = value ?? '';

  final String label;
  final String value;
}

class _LicenseCompactRows extends StatelessWidget {
  const _LicenseCompactRows({required this.rows});

  final List<_LicenseSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows
        .where((row) => row.value.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleRows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final row in visibleRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(row.label, style: _bodyStyle())),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    row.value.trim(),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _strongBodyStyle(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _licenseResponsible(LicenseStatusModel license, String? fallbackEmail) {
  return _firstText([
    license.account?.legalRepresentativeName,
    license.account?.responsibleName,
    license.account?.responsibleEmail,
    fallbackEmail,
  ]);
}

String _firstText(Iterable<String?> values) {
  for (final value in values) {
    final clean = value?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
  }
  return '';
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({
    required this.icon,
    required this.title,
    required this.used,
    required this.max,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final int used;
  final int max;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: _strongBodyStyle())),
              Text('$used / $max', style: _strongBodyStyle()),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: ratio,
              backgroundColor: const Color(0xFFE6EEF5),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}

Color _licenseAccent(String status) {
  return switch (status) {
    'ACTIVE' => AppColors.success,
    'TRIAL' => AppColors.warning,
    'BLOCKED' || 'EXPIRED' => AppColors.error,
    _ => AppColors.secondary,
  };
}

String _licenseStatusLabel(String status) {
  return switch (status) {
    'ACTIVE' => 'Activa',
    'TRIAL' => 'Prueba',
    'BLOCKED' => 'Bloqueada',
    'EXPIRED' => 'Expirada',
    _ => status,
  };
}

String _licenseSubtitle(LicenseStatusModel license) {
  if (license.daysRemaining == null) return 'Licencia sin fecha de cierre';
  if (license.daysRemaining! < 0) return 'Periodo vencido';
  if (license.daysRemaining == 0) return 'Vence hoy';
  return 'Quedan ${license.daysRemaining} días';
}

String _dateLabel(DateTime? value) {
  if (value == null) return 'Sin expiración configurada';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileIcon(icon: icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(16)),
                const SizedBox(height: 5),
                Text(message, style: _bodyStyle()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _titleStyle(16)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
    if (mobile) return content;
    return _SurfacePanel(child: content);
  }
}

class _CompanySettingsEditor extends ConsumerStatefulWidget {
  const _CompanySettingsEditor({required this.settings});

  final CompanySettings settings;

  @override
  ConsumerState<_CompanySettingsEditor> createState() =>
      _CompanySettingsEditorState();
}

class _CompanySettingsEditorState
    extends ConsumerState<_CompanySettingsEditor> {
  late final TextEditingController _name;
  late final TextEditingController _rnc;
  late final TextEditingController _phone;
  late final TextEditingController _phonePreferential;
  late final TextEditingController _address;
  late final TextEditingController _description;
  late final TextEditingController _businessHours;
  late final TextEditingController _website;
  late final TextEditingController _instagram;
  late final TextEditingController _facebook;
  late final TextEditingController _gpsLocation;
  late final TextEditingController _legalName;
  late final TextEditingController _legalCedula;
  late final TextEditingController _legalRole;
  late final TextEditingController _legalNationality;
  late final TextEditingController _legalCivilStatus;
  late final TextEditingController _bankAlias;
  late final TextEditingController _bankType;
  late final TextEditingController _bankNumber;
  late final TextEditingController _bankName;
  String? _logoBase64;
  Uint8List? _logoBytes;
  bool _saving = false;
  bool _showAdvancedCompany = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _rnc = TextEditingController();
    _phone = TextEditingController();
    _phonePreferential = TextEditingController();
    _address = TextEditingController();
    _description = TextEditingController();
    _businessHours = TextEditingController();
    _website = TextEditingController();
    _instagram = TextEditingController();
    _facebook = TextEditingController();
    _gpsLocation = TextEditingController();
    _legalName = TextEditingController();
    _legalCedula = TextEditingController();
    _legalRole = TextEditingController();
    _legalNationality = TextEditingController();
    _legalCivilStatus = TextEditingController();
    _bankAlias = TextEditingController();
    _bankType = TextEditingController();
    _bankNumber = TextEditingController();
    _bankName = TextEditingController();
    _syncControllers(widget.settings);
  }

  @override
  void didUpdateWidget(covariant _CompanySettingsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && oldWidget.settings != widget.settings) {
      _syncControllers(widget.settings);
    }
  }

  void _syncControllers(CompanySettings settings) {
    _name.text = settings.companyName;
    _rnc.text = settings.rnc;
    _phone.text = settings.phone;
    _phonePreferential.text = settings.phonePreferential;
    _address.text = settings.address;
    _description.text = settings.description;
    _businessHours.text = settings.businessHours;
    _website.text = settings.websiteUrl;
    _instagram.text = settings.instagramUrl;
    _facebook.text = settings.facebookUrl;
    _gpsLocation.text = settings.gpsLocationUrl;
    _legalName.text = settings.legalRepresentativeName;
    _legalCedula.text = settings.legalRepresentativeCedula;
    _legalRole.text = settings.legalRepresentativeRole;
    _legalNationality.text = settings.legalRepresentativeNationality;
    _legalCivilStatus.text = settings.legalRepresentativeCivilStatus;
    final firstBank = settings.bankAccounts.isEmpty
        ? const BankAccountEntry()
        : settings.bankAccounts.first;
    _bankAlias.text = firstBank.name;
    _bankType.text = firstBank.type;
    _bankNumber.text = firstBank.accountNumber;
    _bankName.text = firstBank.bankName;
    _logoBase64 = _normalizeLogoBase64(settings.logoBase64);
    _logoBytes = _decodeLogoBytes(_logoBase64);
  }

  String? _normalizeLogoBase64(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  Uint8List? _decodeLogoBytes(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final payload = raw.contains(',') ? raw.split(',').last : raw;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? await _readFileFromPath(file.path);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _showMessage('No se pudo leer el logo seleccionado.');
      return;
    }
    final normalizedBytes = _prepareCompanyLogoBytes(bytes);
    if (normalizedBytes == null || normalizedBytes.isEmpty) {
      _showMessage('El archivo seleccionado no parece ser una imagen válida.');
      return;
    }
    setState(() {
      _logoBytes = normalizedBytes;
      _logoBase64 = base64Encode(normalizedBytes);
    });
    _showMessage('Logo ajustado y listo para guardar.');
  }

  Uint8List? _prepareCompanyLogoBytes(List<int> sourceBytes) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(sourceBytes));
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final cropSize = oriented.width < oriented.height
          ? oriented.width
          : oriented.height;
      final cropped = img.copyCrop(
        oriented,
        x: ((oriented.width - cropSize) / 2).round(),
        y: ((oriented.height - cropSize) / 2).round(),
        width: cropSize,
        height: cropSize,
      );
      final resized = img.copyResize(
        cropped,
        width: 256,
        height: 256,
        interpolation: img.Interpolation.cubic,
      );

      var output = Uint8List.fromList(img.encodePng(resized, level: 6));
      if (output.length > 512 * 1024) {
        output = Uint8List.fromList(img.encodeJpg(resized, quality: 86));
      }
      if (output.length > 512 * 1024) {
        final compact = img.copyResize(
          resized,
          width: 192,
          height: 192,
          interpolation: img.Interpolation.cubic,
        );
        output = Uint8List.fromList(img.encodeJpg(compact, quality: 82));
      }
      return output;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> _readFileFromPath(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    final bytes = await readLocalFileBytes(path);
    return bytes.isEmpty ? null : bytes;
  }

  void _removeLogo() {
    setState(() {
      _logoBase64 = null;
      _logoBytes = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _name.dispose();
    _rnc.dispose();
    _phone.dispose();
    _phonePreferential.dispose();
    _address.dispose();
    _description.dispose();
    _businessHours.dispose();
    _website.dispose();
    _instagram.dispose();
    _facebook.dispose();
    _gpsLocation.dispose();
    _legalName.dispose();
    _legalCedula.dispose();
    _legalRole.dispose();
    _legalNationality.dispose();
    _legalCivilStatus.dispose();
    _bankAlias.dispose();
    _bankType.dispose();
    _bankNumber.dispose();
    _bankName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final authorized = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.manageSettings,
      reason: 'Guardar información de la empresa',
      forceAdminAuthorization: true,
    );
    if (!authorized || !mounted) return;

    setState(() => _saving = true);
    try {
      final queued = await ref
          .read(companySettingsRepositoryProvider)
          .saveSettingsOrQueue(
            widget.settings.copyWith(
              companyName: _name.text.trim(),
              rnc: _rnc.text.trim(),
              phone: _phone.text.trim(),
              phonePreferential: _phonePreferential.text.trim(),
              address: _address.text.trim(),
              description: _description.text.trim(),
              businessHours: _businessHours.text.trim(),
              websiteUrl: _website.text.trim(),
              instagramUrl: _instagram.text.trim(),
              facebookUrl: _facebook.text.trim(),
              gpsLocationUrl: _gpsLocation.text.trim(),
              legalRepresentativeName: _legalName.text.trim(),
              legalRepresentativeCedula: _legalCedula.text.trim(),
              legalRepresentativeRole: _legalRole.text.trim(),
              legalRepresentativeNationality: _legalNationality.text.trim(),
              legalRepresentativeCivilStatus: _legalCivilStatus.text.trim(),
              logoBase64: _logoBase64,
              clearLogo: _logoBase64 == null,
              bankAccounts: [
                if (_bankAlias.text.trim().isNotEmpty ||
                    _bankType.text.trim().isNotEmpty ||
                    _bankNumber.text.trim().isNotEmpty ||
                    _bankName.text.trim().isNotEmpty)
                  BankAccountEntry(
                    name: _bankAlias.text.trim(),
                    type: _bankType.text.trim(),
                    accountNumber: _bankNumber.text.trim(),
                    bankName: _bankName.text.trim(),
                  ),
              ],
            ),
          );
      ref.invalidate(companySettingsProvider);
      ref.invalidate(licenseStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Empresa guardada localmente y pendiente de sincronizar.'
                : 'Datos de empresa guardados.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsOptionGrid(
          items: [
            _SettingsOptionData(
              icon: Icons.storefront_rounded,
              title: 'Nombre comercial',
              value: widget.settings.companyName,
            ),
            _SettingsOptionData(
              icon: Icons.badge_outlined,
              title: 'RNC',
              value: widget.settings.rnc,
            ),
            _SettingsOptionData(
              icon: Icons.phone_outlined,
              title: 'Teléfono',
              value: widget.settings.phone,
            ),
            _SettingsOptionData(
              icon: Icons.schedule_rounded,
              title: 'Horario',
              value: widget.settings.businessHours,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CompanyLogoUploader(
          logoBytes: _logoBytes,
          companyName: _name.text.trim(),
          onPick: _pickLogo,
          onRemove: _logoBytes == null ? null : _removeLogo,
        ),
        const SizedBox(height: 12),
        Text('Datos principales', style: _titleStyle(15)),
        const SizedBox(height: 8),
        _FormWrap(
          children: [
            _field(_name, 'Nombre comercial', Icons.storefront_outlined),
            _field(_rnc, 'RNC / identificación fiscal', Icons.badge_outlined),
            _field(_phone, 'Teléfono principal', Icons.phone_outlined),
            _field(
              _phonePreferential,
              'Teléfono preferencial',
              Icons.phone_in_talk_outlined,
            ),
            _field(
              _address,
              'Dirección de la empresa',
              Icons.location_on_outlined,
              maxLines: 2,
            ),
            _field(_businessHours, 'Horario', Icons.schedule_outlined),
            _field(
              _description,
              'Descripción comercial',
              Icons.notes_outlined,
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _showAdvancedCompany = !_showAdvancedCompany),
            icon: Icon(
              _showAdvancedCompany
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            label: Text(_showAdvancedCompany ? 'Ver menos' : 'Ver más'),
          ),
        ),
        if (_showAdvancedCompany) ...[
          const Divider(height: 16, color: Color(0xFFDDE7EE)),
          Text('Canales y ubicación', style: _titleStyle(15)),
          const SizedBox(height: 8),
          _FormWrap(
            children: [
              _field(_website, 'Sitio web', Icons.language_outlined),
              _field(_instagram, 'Instagram', Icons.alternate_email_rounded),
              _field(_facebook, 'Facebook', Icons.facebook_outlined),
              _field(
                _gpsLocation,
                'Ubicación GPS / Google Maps',
                Icons.map_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Representante legal', style: _titleStyle(15)),
          const SizedBox(height: 8),
          _FormWrap(
            children: [
              _field(
                _legalName,
                'Representante legal',
                Icons.person_outline_rounded,
              ),
              _field(
                _legalCedula,
                'Cédula representante',
                Icons.credit_card_outlined,
              ),
              _field(_legalRole, 'Cargo', Icons.work_outline_rounded),
              _field(_legalNationality, 'Nacionalidad', Icons.flag_outlined),
              _field(
                _legalCivilStatus,
                'Estado civil',
                Icons.assignment_ind_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Cuenta bancaria principal', style: _titleStyle(15)),
          const SizedBox(height: 8),
          _FormWrap(
            children: [
              _field(
                _bankAlias,
                'Alias de cuenta',
                Icons.label_outline_rounded,
              ),
              _field(
                _bankType,
                'Tipo de cuenta',
                Icons.account_balance_outlined,
              ),
              _field(
                _bankNumber,
                'Número de cuenta',
                Icons.credit_card_outlined,
              ),
              _field(_bankName, 'Banco', Icons.account_balance_rounded),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando' : 'Guardar empresa'),
            style: _filledButtonStyle(),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18),
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _CompanyLogoUploader extends StatelessWidget {
  const _CompanyLogoUploader({
    required this.logoBytes,
    required this.companyName,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? logoBytes;
  final String companyName;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final displayName = companyName.trim().isEmpty
        ? 'Empresa'
        : companyName.trim();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth < 420;
          final stackActions = constraints.maxWidth < 560;
          final image = Container(
            width: mobile ? 62 : 68,
            height: mobile ? 62 : 68,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCFE0FF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: logoBytes == null
                ? const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.secondary,
                    size: 30,
                  )
                : Image.memory(logoBytes!, fit: BoxFit.cover),
          );
          final text = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logo de la empresa', style: _strongBodyStyle()),
                const SizedBox(height: 4),
                Text(
                  'Se mostrará en el topbar, documentos y áreas de identidad de $displayName.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _bodyStyle(),
                ),
              ],
            ),
          );
          final pickButton = OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(logoBytes == null ? 'Subir logo' : 'Cambiar'),
            style: _outlinedButtonStyle(),
          );
          final actions = Row(
            mainAxisSize: stackActions ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (stackActions) Expanded(child: pickButton) else pickButton,
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Quitar logo',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.error,
                ),
              ],
            ],
          );
          if (stackActions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [image, const SizedBox(width: 12), text]),
                const SizedBox(height: 10),
                actions,
              ],
            );
          }
          return Row(
            children: [
              image,
              const SizedBox(width: 14),
              text,
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SettingsOptionData {
  const _SettingsOptionData({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
}

class _SettingsOptionGrid extends StatelessWidget {
  const _SettingsOptionGrid({required this.items});

  final List<_SettingsOptionData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 430
            ? 1
            : constraints.maxWidth < 760
            ? 2
            : 4;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: crossAxisCount == 1
              ? 92
              : crossAxisCount == 2
              ? 108
              : 112,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFDDE7EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, color: AppColors.secondary, size: 18),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _strongBodyStyle(),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.value.trim().isEmpty
                          ? 'No configurado'
                          : item.value.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _running = false;
  CloudBackupResult? _result;
  CloudBackupInspection? _inspection;
  String? _lastZipPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLastBackup());
  }

  Future<void> _loadLastBackup() async {
    final path = await ref.read(cloudBackupServiceProvider).lastBackupZipPath();
    if (!mounted) return;
    setState(() => _lastZipPath = path);
  }

  Future<void> _createBackup() async {
    setState(() => _running = true);
    try {
      final result = await ref
          .read(cloudBackupServiceProvider)
          .createCloudBackup();
      if (!mounted) return;
      setState(() => _result = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailures
                ? 'Backup creado con algunos módulos pendientes.'
                : 'Backup local creado correctamente.',
          ),
        ),
      );
      await _loadLastBackup();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el backup: $error')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _inspectBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final inspection = await ref
          .read(cloudBackupServiceProvider)
          .inspectBackupZip(path);
      if (!mounted) return;
      setState(() => _inspection = inspection);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup validado correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo validar el backup: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final shownZipPath = result?.zipPath ?? _lastZipPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StatusBanner(
          icon: Icons.security_update_good_outlined,
          title: 'Respaldo local de la empresa',
          message:
              'Descarga un ZIP con la información sincronizada. En PC se crea automáticamente cada 2 días.',
          accent: Color(0xFF2563EB),
        ),
        const SizedBox(height: 12),
        const _DetailRow(
          'Origen',
          'Nube, empresa, impresora y módulos activos',
        ),
        const _DetailRow('Destino', 'Carpeta local FullPOS Cloud / backups'),
        if (shownZipPath != null) _DetailRow('Último ZIP', shownZipPath),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 390;
            final create = FilledButton.icon(
              onPressed: _running ? null : _createBackup,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(
                _running ? 'Creando backup' : 'Descargar backup ahora',
                overflow: TextOverflow.ellipsis,
              ),
              style: _filledButtonStyle(),
            );
            final restore = OutlinedButton.icon(
              onPressed: _running ? null : _inspectBackup,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text(
                'Validar backup',
                overflow: TextOverflow.ellipsis,
              ),
              style: _outlinedButtonStyle(),
            );
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [create, const SizedBox(height: 8), restore],
              );
            }
            return Row(
              children: [
                Expanded(child: create),
                const SizedBox(width: 10),
                Expanded(child: restore),
              ],
            );
          },
        ),
        if (result != null) ...[
          const SizedBox(height: 14),
          _StatusBanner(
            icon: result.hasFailures
                ? Icons.warning_amber_rounded
                : Icons.verified_outlined,
            title: result.hasFailures
                ? 'Backup creado con observaciones'
                : 'Backup listo para recuperación',
            message:
                '${result.modules.length} módulos guardados. ZIP: ${result.zipPath}',
            accent: result.hasFailures
                ? const Color(0xFFE08A00)
                : const Color(0xFF178A5C),
          ),
          if (result.failedModules.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final entry in result.failedModules.entries)
              _DetailRow(entry.key, entry.value),
          ],
        ],
        if (_inspection != null) ...[
          const SizedBox(height: 14),
          _StatusBanner(
            icon: Icons.fact_check_outlined,
            title: 'Backup válido para recuperación',
            message:
                '${_inspection!.modules.length} módulos encontrados. Archivo: ${_inspection!.path}',
            accent: const Color(0xFF178A5C),
          ),
        ],
      ],
    );
  }
}

class _FormWrap extends StatelessWidget {
  const _FormWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _strongBodyStyle()),
        const SizedBox(height: 6),
        Text(text, style: _bodyStyle()),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = (value ?? '').trim().isEmpty
        ? 'No configurado'
        : value!.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 340;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _bodyStyle()),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _strongBodyStyle(),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: Text(label, style: _bodyStyle())),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        text,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _strongBodyStyle(),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: child,
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => _TileIcon(icon: icon, size: 40);
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({
    required this.icon,
    this.color = AppColors.secondary,
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Icon(icon, size: size * 0.48, color: color),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.secondary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

ButtonStyle _outlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.secondary,
    side: const BorderSide(color: Color(0xFF9DB9F8)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
  );
}

ButtonStyle _filledButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.secondary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
  );
}

TextStyle _titleStyle(double size) {
  return TextStyle(
    color: AppColors.textPrimary,
    fontSize: size,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
}

TextStyle _bodyStyle() {
  return const TextStyle(
    color: Color(0xFF52667C),
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
}

TextStyle _strongBodyStyle() {
  return const TextStyle(
    color: Color(0xFF183548),
    fontSize: 13,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
}

String _updateMessage(AppUpdateState state) {
  final update = state.updateInfo;
  if (update?.update == true) {
    return 'Hay una versión nueva disponible para este dispositivo.';
  }
  return 'Puedes verificar manualmente si existe una versión nueva para este equipo.';
}

String _pendingUpdateLabel(AppUpdatePhase phase) {
  return switch (phase) {
    AppUpdatePhase.upToDate => 'No disponible',
    AppUpdatePhase.disabled => 'No configurado',
    AppUpdatePhase.unsupported => 'No administrada',
    AppUpdatePhase.error => 'No verificada',
    AppUpdatePhase.idle => 'Pendiente de verificación',
    _ => 'Verificando',
  };
}

String _busyUpdateLabel(AppUpdatePhase phase) {
  return switch (phase) {
    AppUpdatePhase.downloadingUpdate => 'Descargando',
    AppUpdatePhase.installingUpdate => 'Instalando',
    _ => 'Buscando',
  };
}

IconData _updateIcon(AppUpdatePhase phase) {
  return switch (phase) {
    AppUpdatePhase.upToDate => Icons.verified_rounded,
    AppUpdatePhase.error => Icons.error_outline_rounded,
    AppUpdatePhase.requiredUpdate => Icons.priority_high_rounded,
    AppUpdatePhase.optionalUpdate => Icons.new_releases_outlined,
    AppUpdatePhase.downloadingUpdate ||
    AppUpdatePhase.installingUpdate ||
    AppUpdatePhase.checking => Icons.sync_rounded,
    _ => Icons.system_update_alt_rounded,
  };
}

Color _updateAccent(AppUpdatePhase phase) {
  return switch (phase) {
    AppUpdatePhase.error ||
    AppUpdatePhase.requiredUpdate => const Color(0xFFDC2626),
    AppUpdatePhase.upToDate => const Color(0xFF16A34A),
    _ => AppColors.secondary,
  };
}
