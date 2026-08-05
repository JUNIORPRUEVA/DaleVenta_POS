import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import 'pwa_install_prompt.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static Uri get _windowsDownloadUri =>
      Uri.base.resolve('downloads/fullpos-cloud-windows.exe');
  static Uri get _androidDownloadUri =>
      Uri.base.resolve('downloads/fullpos-cloud-android.apk');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 820;
    final contentPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 18 : 44,
      vertical: isCompact ? 18 : 28,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFC),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: contentPadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LandingTopBar(isCompact: isCompact),
                        SizedBox(height: isCompact ? 22 : 46),
                        _HeroSection(isCompact: isCompact),
                        const SizedBox(height: 34),
                        const _ModuleGrid(),
                        const SizedBox(height: 34),
                        const _DownloadSection(),
                        const SizedBox(height: 24),
                        const _Footer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> openWindowsDownload(BuildContext context) {
    return safeOpenUrl(
      context,
      _windowsDownloadUri,
      copiedMessage: 'No se pudo abrir la descarga. Link copiado.',
    );
  }

  static Future<void> openAndroidDownload(BuildContext context) {
    return safeOpenUrl(
      context,
      _androidDownloadUri,
      copiedMessage: 'No se pudo abrir la descarga. Link copiado.',
    );
  }
}

class _LandingTopBar extends StatelessWidget {
  const _LandingTopBar({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x170B4A6F),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/image/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FullPOS Cloud',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF102033),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Sistema de facturacion y gestion comercial',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF62748C),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (!isCompact) ...[
          TextButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Iniciar sesion'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => context.go(Routes.register),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Crear mi cuenta'),
          ),
        ],
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final heroText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F7F4),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFB9E7DD)),
          ),
          child: const Text(
            'PWA, Windows y Android en un solo ecosistema',
            style: TextStyle(
              color: Color(0xFF0E766E),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'FullPOS Cloud',
          style: TextStyle(
            color: const Color(0xFF0E1B2A),
            fontSize: isCompact ? 38 : 58,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Controla ventas, inventario, compras, clientes, caja y contabilidad desde una experiencia moderna preparada para mostrador, oficina y movilidad.',
          style: TextStyle(
            color: Color(0xFF44566C),
            fontSize: 17,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => context.go(Routes.register),
              icon: const Icon(Icons.rocket_launch_rounded, size: 19),
              label: const Text('Crear mi cuenta'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.login),
              icon: const Icon(Icons.login_rounded, size: 19),
              label: const Text('Iniciar sesion'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final preview = const _ProductPreview();

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heroText, const SizedBox(height: 26), preview],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 10, child: heroText),
        const SizedBox(width: 42),
        Expanded(flex: 9, child: preview),
      ],
    );
  }
}

class _ProductPreview extends StatelessWidget {
  const _ProductPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A113B5A),
            blurRadius: 38,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StatusDot(color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Panel comercial activo',
                  style: TextStyle(
                    color: Color(0xFF0F2237),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.more_horiz_rounded, color: Color(0xFF7A8FA6)),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _MetricTile(label: 'Ventas hoy', value: 'RD\$ 42,850'),
              _MetricTile(label: 'Tickets', value: '128'),
              _MetricTile(label: 'Stock bajo', value: '17'),
            ],
          ),
          const SizedBox(height: 18),
          const _PreviewRow(
            icon: Icons.point_of_sale_rounded,
            label: 'Facturacion',
            value: 'Caja rapida y tickets',
            color: Color(0xFF2563EB),
          ),
          const _PreviewRow(
            icon: Icons.inventory_2_rounded,
            label: 'Inventario',
            value: 'Catalogo, ajuste y conteo',
            color: Color(0xFF0E9F6E),
          ),
          const _PreviewRow(
            icon: Icons.receipt_long_rounded,
            label: 'Contabilidad',
            value: 'Cierres, pagos y fiscal',
            color: Color(0xFF7C3AED),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7F94),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF102033),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2EAF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF102033),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF8EA0B3),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid();

  @override
  Widget build(BuildContext context) {
    final modules = [
      _ModuleItem(
        icon: Icons.point_of_sale_rounded,
        title: 'Ventas y caja',
        description:
            'Facturacion agil, tickets abiertos, turnos y movimientos.',
        color: Color(0xFF2563EB),
      ),
      _ModuleItem(
        icon: Icons.inventory_2_rounded,
        title: 'Inventario',
        description: 'Catalogo, categorias, ajustes de stock y conteo fisico.',
        color: Color(0xFF0F766E),
      ),
      _ModuleItem(
        icon: Icons.shopping_cart_checkout_rounded,
        title: 'Compras',
        description: 'Nueva compra, listado, suplidores, facturas y sugeridos.',
        color: Color(0xFF0EA5E9),
      ),
      _ModuleItem(
        icon: Icons.account_balance_rounded,
        title: 'Contabilidad',
        description: 'Cierres, depositos, NCF, pagos pendientes y nomina.',
        color: Color(0xFF7C3AED),
      ),
      _ModuleItem(
        icon: Icons.groups_rounded,
        title: 'Clientes',
        description:
            'Historial, creditos, ubicaciones y seguimiento comercial.',
        color: Color(0xFF16A34A),
      ),
      _ModuleItem(
        icon: Icons.analytics_rounded,
        title: 'Reportes',
        description:
            'Indicadores para tomar decisiones desde cualquier equipo.',
        color: Color(0xFFEA580C),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 980
            ? 3
            : constraints.maxWidth > 620
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 150,
          ),
          itemBuilder: (context, index) => _ModuleCard(item: modules[index]),
        );
      },
    );
  }
}

class _ModuleItem {
  const _ModuleItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.item});

  final _ModuleItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            item.title,
            style: const TextStyle(
              color: Color(0xFF102033),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF102033),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22102033),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Elige como quieres usar FullPOS Cloud',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Instala la PWA en el navegador o descarga las versiones nativas para Windows y Android.',
            style: TextStyle(
              color: Color(0xFFC8D4DF),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 840
                  ? 3
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 3.3 : 2.2,
                children: [
                  _DownloadCard(
                    icon: Icons.desktop_windows_rounded,
                    title: 'Windows',
                    description:
                        'Instalador para equipos de mostrador y oficina.',
                    label: 'Descargar Windows',
                    onPressed: () => LandingScreen.openWindowsDownload(context),
                  ),
                  _DownloadCard(
                    icon: Icons.android_rounded,
                    title: 'Android APK',
                    description:
                        'App movil para trabajar desde telefono o tablet.',
                    label: 'Descargar APK',
                    onPressed: () => LandingScreen.openAndroidDownload(context),
                  ),
                  _DownloadCard(
                    icon: Icons.install_desktop_rounded,
                    title: 'PWA',
                    description:
                        'Instala desde el navegador sin descargar paquetes.',
                    label: 'Instalar PWA',
                    onPressed: () {
                      final shown = requestPwaInstallPrompt();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            shown
                                ? 'Abriendo opcion de instalacion PWA.'
                                : 'Usa el menu del navegador para instalar esta PWA.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 430;
        final button = FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(label),
        );

        final textBlock = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFC8D4DF),
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

        final leading = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 23),
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [leading, const SizedBox(width: 14), textBlock],
                    ),
                    const SizedBox(height: 12),
                    button,
                  ],
                )
              : Row(
                  children: [
                    leading,
                    const SizedBox(width: 14),
                    textBlock,
                    const SizedBox(width: 10),
                    button,
                  ],
                ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text(
        '© 2026 FullPOS Cloud - Plataforma comercial para negocios modernos.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF66788D),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
