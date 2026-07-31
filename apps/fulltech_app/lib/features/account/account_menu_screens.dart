import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../core/api/env.dart';
import '../../core/app_update/app_update_controller.dart';
import '../../core/app_update/app_update_models.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/local_file_bytes.dart';
import '../../core/utils/safe_url_launcher.dart';
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
        _AccessChannelTile(
          icon: Icons.android_rounded,
          title: 'App Android',
          status: 'Preparada para móviles y tablets',
          description:
              'Permite entrar a la cuenta de la empresa desde Android para consultar ventas, clientes, inventario y operaciones autorizadas.',
          actionLabel: 'Ver acceso',
          onPressed: () => safeOpenUrl(context, Uri.parse(Env.appBaseUrl)),
        ),
        _AccessChannelTile(
          icon: Icons.language_rounded,
          title: 'App web',
          status: 'Acceso desde navegador',
          description:
              'Abre la versión web para trabajar desde cualquier computador autorizado usando las mismas credenciales de la empresa.',
          actionLabel: 'Abrir web',
          onPressed: () => safeOpenUrl(context, Uri.parse(Env.appBaseUrl)),
        ),
        _AccessChannelTile(
          icon: Icons.desktop_windows_rounded,
          title: 'Windows POS',
          status: 'Punto de venta instalado',
          description:
              'Aplicación de escritorio para caja, facturación, impresión y trabajo diario del punto de venta.',
          actionLabel: 'Actualizaciones',
          onPressed: () => context.go(Routes.actualizaciones),
        ),
      ],
    );
  }
}

class AccountLicensesScreen extends ConsumerWidget {
  const AccountLicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final user = ref.watch(authStateProvider).user;

    return _AccountSidePanelScaffold(
      icon: Icons.verified_user_outlined,
      title: 'Licencias',
      subtitle: 'Estado de uso, empresa activa y alcance contratado.',
      children: [
        _InfoTile(
          icon: Icons.business_rounded,
          title: 'Empresa activa',
          value: company.maybeWhen(
            data: (settings) => settings.companyName.trim().isEmpty
                ? 'FullPOS Cloud'
                : settings.companyName.trim(),
            orElse: () => 'FullPOS Cloud',
          ),
        ),
        _InfoTile(
          icon: Icons.person_outline_rounded,
          title: 'Usuario actual',
          value: user?.email ?? 'Usuario conectado',
        ),
        const _LicensePlanCard(),
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
    final company = ref.watch(companySettingsProvider);

    return _SettingsHubScaffold(
      company: company,
      children: [
        _SettingsLaunchCard(
          icon: Icons.business_center_outlined,
          title: 'Empresa',
          description: company.maybeWhen(
            data: (settings) => settings.companyName.trim().isEmpty
                ? 'Datos fiscales, dirección y representante legal.'
                : settings.companyName.trim(),
            orElse: () => 'Datos fiscales, dirección y representante legal.',
          ),
          route: Routes.configuracionEmpresa,
        ),
        const _SettingsLaunchCard(
          icon: Icons.receipt_long_outlined,
          title: 'Documentos',
          description: 'Datos que aparecen en facturas, cotizaciones y PDFs.',
          route: Routes.configuracionDocumentos,
        ),
        const _SettingsLaunchCard(
          icon: Icons.print_outlined,
          title: 'Impresora',
          description: 'Tickets, copias, papel, logo y formato de impresión.',
          route: Routes.configuracionImpresora,
        ),
        const _SettingsLaunchCard(
          icon: Icons.cloud_sync_outlined,
          title: 'Backup',
          description: 'Descarga la información de la nube a respaldo local.',
          route: Routes.configuracionBackup,
        ),
      ],
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
                icon: Icons.receipt_long_outlined,
                title: 'Documentos',
                value: 'Datos de empresa aplicados a PDFs y contratos.',
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

class _SettingsHubScaffold extends StatelessWidget {
  const _SettingsHubScaffold({required this.company, required this.children});

  final AsyncValue<CompanySettings> company;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final showInlineTitle = MediaQuery.sizeOf(context).width < 900;
    final configuredName = company.maybeWhen(
      data: (settings) => settings.companyName.trim(),
      orElse: () => '',
    );
    final displayName = configuredName.isEmpty
        ? 'FullPOS Cloud'
        : configuredName;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showInlineTitle) ...[
                  Text('Configuración', style: _titleStyle(28)),
                  const SizedBox(height: 6),
                  Text(
                    'Centro de control para empresa, operación, seguridad y servicios.',
                    style: _bodyStyle(),
                  ),
                  const SizedBox(height: 18),
                ],
                _SettingsHeroPanel(
                  companyName: displayName,
                  configured: configuredName.isNotEmpty,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 720;
                      return GridView.count(
                        crossAxisCount: twoColumns ? 2 : 1,
                        childAspectRatio: twoColumns ? 5.15 : 5.4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: children,
                      );
                    },
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

class _SettingsHeroPanel extends StatelessWidget {
  const _SettingsHeroPanel({
    required this.companyName,
    required this.configured,
  });

  final String companyName;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          _TileIcon(icon: Icons.settings_rounded, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuración de FullPOS Cloud', style: _titleStyle(18)),
                const SizedBox(height: 2),
                Text(companyName, style: _strongBodyStyle()),
              ],
            ),
          ),
          _StatusPill(label: configured ? 'Empresa configurada' : 'Pendiente'),
        ],
      ),
    );
  }
}

class _SettingsDetailScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final showInlineTitle = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => context.go(Routes.configuracion),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFDDE7EE)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: showInlineTitle
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: _titleStyle(24)),
                              const SizedBox(height: 3),
                              Text(subtitle, style: _bodyStyle()),
                            ],
                          )
                        : Text(subtitle, style: _bodyStyle()),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLaunchCard extends StatelessWidget {
  const _SettingsLaunchCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.go(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDE7EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _titleStyle(15)),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF60758A),
                size: 20,
              ),
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
            onPressed: () => Navigator.of(context).maybePop(),
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
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String status;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: Text(actionLabel),
                  style: _outlinedButtonStyle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Row(
        children: [
          _TileIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _bodyStyle()),
                const SizedBox(height: 3),
                Text(value, style: _titleStyle(15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensePlanCard extends StatelessWidget {
  const _LicensePlanCard();

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TileIcon(icon: Icons.workspace_premium_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Plan profesional POS', style: _titleStyle(15)),
              ),
              const _StatusPill(label: 'Activo'),
            ],
          ),
          const SizedBox(height: 12),
          const _DetailRow('Empresas preparadas', 'Multiempresa'),
          const _DetailRow('Usuarios', 'Según permisos de la empresa'),
          const _DetailRow(
            'Módulos incluidos',
            'Ventas, clientes, inventario y caja',
          ),
          const _DetailRow(
            'Soporte',
            'Operación y actualizaciones del sistema',
          ),
        ],
      ),
    );
  }
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
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _titleStyle(16)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
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
        _ParagraphBlock(
          title: 'Dirección fiscal y comercial',
          text: widget.settings.address.trim().isEmpty
              ? 'No hay dirección configurada para documentos.'
              : widget.settings.address.trim(),
        ),
        const SizedBox(height: 14),
        _ParagraphBlock(
          title: 'Datos fiscales y comerciales',
          text:
              'Esta información se usa como identidad central de la empresa en documentos y pantallas.',
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 14),
        _ParagraphBlock(
          title: 'Representante legal',
          text:
              'Datos usados en contratos, cartas y documentos administrativos.',
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 14),
        _ParagraphBlock(
          title: 'Cuenta bancaria principal',
          text:
              'Se usará como referencia para documentos, depósitos y comunicación con clientes.',
        ),
        const SizedBox(height: 10),
        _FormWrap(
          children: [
            _field(_bankAlias, 'Alias de cuenta', Icons.label_outline_rounded),
            _field(_bankType, 'Tipo de cuenta', Icons.account_balance_outlined),
            _field(_bankNumber, 'Número de cuenta', Icons.credit_card_outlined),
            _field(_bankName, 'Banco', Icons.account_balance_rounded),
          ],
        ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
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
          ),
          const SizedBox(width: 14),
          Expanded(
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
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(logoBytes == null ? 'Subir logo' : 'Cambiar'),
            style: _outlinedButtonStyle(),
          ),
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
        final compact = constraints.maxWidth < 760;
        return GridView.count(
          crossAxisCount: compact ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: compact ? 2.15 : 2.25,
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el backup: $error')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DetailRow('Origen', 'Datos de nube y configuración local'),
        const _DetailRow('Destino', 'Documentos / FullPOS Cloud / backups'),
        const _DetailRow('Formato', 'Carpeta JSON + archivo ZIP'),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _createBackup,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(_running ? 'Descargando' : 'Crear backup local'),
              style: _filledButtonStyle(),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Restaurar a nube'),
              style: _outlinedButtonStyle(),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
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
