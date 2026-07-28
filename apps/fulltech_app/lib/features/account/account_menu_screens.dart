import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/env.dart';
import '../../core/app_update/app_update_controller.dart';
import '../../core/app_update/app_update_models.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../settings/ui/printer_settings_page.dart';

class AccountAppsScreen extends StatelessWidget {
  const AccountAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountSidePanelScaffold(
      icon: Icons.apps_rounded,
      title: 'Apps',
      subtitle: 'Accesos para usar DaleVenta POS en distintos dispositivos.',
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
                ? 'DaleVenta POS'
                : settings.companyName.trim(),
            orElse: () => 'DaleVenta POS',
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

class AccountUpdatesScreen extends ConsumerWidget {
  const AccountUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final installed = state.installedRelease;
    final update = state.updateInfo;
    final checkedAt = state.checkedAt == null
        ? 'Sin verificación reciente'
        : DateFormat('dd/MM/yyyy HH:mm', 'es_DO').format(state.checkedAt!);

    return _AccountFullPageScaffold(
      icon: Icons.system_update_alt_rounded,
      title: 'Actualizaciones',
      subtitle:
          'Revisa la versión instalada, el canal de releases y el estado de actualización del sistema.',
      action: FilledButton.icon(
        onPressed: state.phase == AppUpdatePhase.checking
            ? null
            : () => controller.checkNow(force: true),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Buscar actualización'),
        style: _filledButtonStyle(),
      ),
      children: [
        _StatusBanner(
          icon: _updateIcon(state.phase),
          title: _updateTitle(state),
          message: state.message ?? _updateMessage(state),
          accent: _updateAccent(state.phase),
        ),
        _FullPageGrid(
          children: [
            _MetricPanel(
              icon: Icons.computer_rounded,
              label: 'Plataforma',
              value: installed?.platform.displayName ?? 'No detectada',
            ),
            _MetricPanel(
              icon: Icons.tag_rounded,
              label: 'Versión instalada',
              value: installed == null
                  ? 'Sin datos'
                  : '${installed.currentVersion}+${installed.currentBuild}',
            ),
            _MetricPanel(
              icon: Icons.new_releases_outlined,
              label: 'Última versión',
              value: update?.latestVersion ?? 'Sin release disponible',
            ),
            _MetricPanel(
              icon: Icons.schedule_rounded,
              label: 'Última revisión',
              value: checkedAt,
            ),
          ],
        ),
        _SectionPanel(
          title: 'Detalle del release',
          children: [
            _DetailRow(
              'Actualización disponible',
              update?.update == true ? 'Sí' : 'No',
            ),
            _DetailRow(
              'Actualización obligatoria',
              update?.required == true ? 'Sí' : 'No',
            ),
            _DetailRow(
              'Build publicado',
              update?.latestBuild?.toString() ?? 'Sin datos',
            ),
            _DetailRow(
              'Descarga',
              update?.hasDownloadUrl == true ? 'Configurada' : 'No configurada',
            ),
            if ((update?.releaseNotes ?? '').trim().isNotEmpty)
              _ParagraphBlock(
                title: 'Notas',
                text: update!.releaseNotes!.trim(),
              ),
          ],
        ),
      ],
    );
  }
}

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final user = ref.watch(authStateProvider).user;

    return _AccountFullPageScaffold(
      icon: Icons.settings_outlined,
      title: 'Configuración',
      subtitle:
          'Centro de control para empresa, impresión, seguridad y parámetros operativos.',
      action: OutlinedButton.icon(
        onPressed: () => ref.invalidate(companySettingsProvider),
        icon: const Icon(Icons.sync_rounded),
        label: const Text('Sincronizar'),
        style: _outlinedButtonStyle(),
      ),
      children: [
        _FullPageGrid(
          children: [
            _MetricPanel(
              icon: Icons.business_rounded,
              label: 'Empresa',
              value: company.maybeWhen(
                data: (settings) => settings.companyName.trim().isEmpty
                    ? 'DaleVenta POS'
                    : settings.companyName.trim(),
                orElse: () => 'DaleVenta POS',
              ),
            ),
            _MetricPanel(
              icon: Icons.mail_outline_rounded,
              label: 'Cuenta',
              value: user?.email ?? 'Sin usuario',
            ),
            _MetricPanel(
              icon: Icons.security_rounded,
              label: 'Rol',
              value: user?.role ?? 'Sin rol',
            ),
            _MetricPanel(
              icon: Icons.cloud_done_outlined,
              label: 'Backend',
              value: Env.apiBaseUrl,
            ),
          ],
        ),
        _SectionPanel(
          title: 'Empresa y documentos',
          children: [
            company.maybeWhen(
              data: (settings) => _CompanySettingsEditor(settings: settings),
              orElse: () => const _ParagraphBlock(
                title: 'Configuración de empresa',
                text:
                    'Los datos de la empresa se sincronizan con el servidor para usarse en facturas, cotizaciones y documentos internos.',
              ),
            ),
          ],
        ),
        _SectionPanel(
          title: 'Parámetros importantes',
          children: [
            _SettingsOptionGrid(
              items: const [
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
                  value: 'Empresa aplicada a PDFs, tickets y contratos.',
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
        const _SectionPanel(
          title: 'Impresión y tickets',
          children: [PrinterSettingsPage(embedded: true)],
        ),
        const _SectionPanel(
          title: 'Backup y recuperación',
          children: [_BackupSection()],
        ),
      ],
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
      backgroundColor: const Color(0xFFEFF5F8),
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

class _AccountFullPageScaffold extends StatelessWidget {
  const _AccountFullPageScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF5F8),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFD3E0E7))),
              ),
              child: Row(
                children: [
                  _HeaderIcon(icon: icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: _titleStyle(20)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: _bodyStyle()),
                      ],
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(18),
                itemBuilder: (context, index) => children[index],
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemCount: children.length,
              ),
            ),
          ],
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

class _FullPageGrid extends StatelessWidget {
  const _FullPageGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 4 ? 2.35 : 2.8,
          children: children,
        );
      },
    );
  }
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1957E6), size: 19),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _bodyStyle(),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(14),
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

class _CompanySettingsEditor extends StatelessWidget {
  const _CompanySettingsEditor({required this.settings});

  final CompanySettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsOptionGrid(
          items: [
            _SettingsOptionData(
              icon: Icons.storefront_rounded,
              title: 'Nombre comercial',
              value: settings.companyName,
            ),
            _SettingsOptionData(
              icon: Icons.badge_outlined,
              title: 'RNC',
              value: settings.rnc,
            ),
            _SettingsOptionData(
              icon: Icons.phone_outlined,
              title: 'Teléfono',
              value: settings.phone,
            ),
            _SettingsOptionData(
              icon: Icons.schedule_rounded,
              title: 'Horario',
              value: settings.businessHours,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ParagraphBlock(
          title: 'Dirección fiscal y comercial',
          text: settings.address.trim().isEmpty
              ? 'No hay dirección configurada para documentos.'
              : settings.address.trim(),
        ),
      ],
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
                    Icon(item.icon, color: const Color(0xFF1957E6), size: 18),
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

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _DetailRow('Storage de archivos', 'Cloudflare R2 configurado'),
        _DetailRow('Alcance', 'Imágenes, documentos y recursos por empresa'),
        _DetailRow('Separación', 'Datos aislados por empresa activa'),
        _DetailRow('Recuperación', 'Lista para restauración operativa'),
      ],
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
    this.color = const Color(0xFF1957E6),
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
          color: Color(0xFF1957E6),
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
    foregroundColor: const Color(0xFF1957E6),
    side: const BorderSide(color: Color(0xFF9DB9F8)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
  );
}

ButtonStyle _filledButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: const Color(0xFF1957E6),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
  );
}

TextStyle _titleStyle(double size) {
  return TextStyle(
    color: const Color(0xFF0F172A),
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

String _updateTitle(AppUpdateState state) {
  return switch (state.phase) {
    AppUpdatePhase.checking => 'Buscando actualización',
    AppUpdatePhase.upToDate => 'Sistema actualizado',
    AppUpdatePhase.optionalUpdate => 'Actualización disponible',
    AppUpdatePhase.requiredUpdate => 'Actualización obligatoria',
    AppUpdatePhase.downloadingUpdate => 'Descargando actualización',
    AppUpdatePhase.installingUpdate => 'Instalando actualización',
    AppUpdatePhase.disabled => 'Releases no configurados',
    AppUpdatePhase.unsupported => 'Plataforma no administrada',
    AppUpdatePhase.error => 'No se pudo verificar',
    AppUpdatePhase.idle => 'Listo para verificar',
  };
}

String _updateMessage(AppUpdateState state) {
  final update = state.updateInfo;
  if (update?.update == true) {
    return 'Hay una versión nueva disponible para este dispositivo.';
  }
  return 'Puedes verificar manualmente si existe una versión nueva para este equipo.';
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
    _ => const Color(0xFF1957E6),
  };
}
