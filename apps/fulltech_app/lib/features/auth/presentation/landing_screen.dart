import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_access/app_access_links.dart';
import '../../../core/auth/business_registration_policy.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import 'pwa_install_prompt.dart';

const _supportPhoneDisplay = '829-531-9442';
const _supportWhatsappIntl = '18295319442';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static Uri get _windowsDownloadUri => AppAccessLinks.windowsReleaseUri;
  static Uri get _androidDownloadUri => AppAccessLinks.androidReleaseUri;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final businessRegistrationDisabled =
        isBusinessRegistrationDisabledOnCurrentPlatform;
    final baseTheme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      endDrawer: const _LandingDrawer(),
      body: SafeArea(
        child: Theme(
          data: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Manrope'),
            primaryTextTheme: baseTheme.primaryTextTheme.apply(
              fontFamily: 'Manrope',
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Manrope'),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isMobile ? 18 : 38,
                          isMobile ? 16 : 26,
                          isMobile ? 18 : 38,
                          30,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopBar(
                              isMobile: isMobile,
                              businessRegistrationDisabled:
                                  businessRegistrationDisabled,
                            ),
                            SizedBox(height: isMobile ? 24 : 42),
                            _Hero(
                              isMobile: isMobile,
                              businessRegistrationDisabled:
                                  businessRegistrationDisabled,
                            ),
                            const SizedBox(height: 24),
                            const _ProofSection(),
                            const SizedBox(height: 24),
                            const _ModulesSection(),
                            const SizedBox(height: 24),
                            const _PlatformGuideSection(),
                            const SizedBox(height: 24),
                            const _PricingSection(),
                            const SizedBox(height: 24),
                            const _InstallPanel(),
                            if (isMobile) ...[
                              const SizedBox(height: 18),
                              const _HeroImage(),
                            ],
                            const SizedBox(height: 28),
                            const _BusinessSection(),
                            const SizedBox(height: 28),
                            const _MobileExperienceSection(),
                            const SizedBox(height: 28),
                            const _PlatformSecuritySection(),
                            const SizedBox(height: 28),
                            const _FinalCtaSection(),
                            const SizedBox(height: 22),
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
        ),
      ),
    );
  }

  static Future<void> openWhatsApp(BuildContext context) {
    return safeOpenWhatsApp(
      context,
      _supportWhatsAppUri(
        'Hola, quiero informacion sobre FullPOS Cloud y la oferta de licencia anual.',
      ),
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
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

Uri _supportWhatsAppUri(String text) {
  return Uri.https('wa.me', '/$_supportWhatsappIntl', {'text': text});
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isMobile,
    required this.businessRegistrationDisabled,
  });

  final bool isMobile;
  final bool businessRegistrationDisabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x160B2744),
                blurRadius: 22,
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
                  color: Color(0xFF0D1B2A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Sistema POS multi plataforma para vender y controlar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF5E7187),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (isMobile)
          Builder(
            builder: (context) => IconButton.filledTonal(
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          )
        else ...[
          TextButton(
            onPressed: () => _showInfoSheet(context),
            child: const Text('Plataformas'),
          ),
          TextButton(
            onPressed: () => LandingScreen.openWhatsApp(context),
            child: const Text(_supportPhoneDisplay),
          ),
          TextButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Iniciar sesion'),
          ),
          const SizedBox(width: 8),
          if (!businessRegistrationDisabled)
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

class _Hero extends StatelessWidget {
  const _Hero({
    required this.isMobile,
    required this.businessRegistrationDisabled,
  });

  final bool isMobile;
  final bool businessRegistrationDisabled;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill('Web/PWA'),
            _Pill('Windows'),
            _Pill('Android'),
            _Pill('iPhone'),
            _Pill('Multi empresa'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'POS en la nube para vender desde cualquier dispositivo',
          style: TextStyle(
            color: const Color(0xFF0B1728),
            fontSize: isMobile ? 38 : 58,
            height: 1.03,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'FullPOS Cloud une facturacion, inventario, caja, compras, clientes y reportes en una experiencia rapida para mostrador, telefono y navegador.',
          style: TextStyle(
            color: Color(0xFF3E536B),
            fontSize: 17,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        const _ValueBullets(),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (!businessRegistrationDisabled)
              FilledButton.icon(
                onPressed: () => LandingScreen.openWhatsApp(context),
                icon: const Icon(Icons.rocket_launch_rounded, size: 19),
                label: const Text('Comprar por WhatsApp'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 17,
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _requestInstall(context),
              icon: const Icon(Icons.add_to_home_screen_rounded, size: 19),
              label: const Text('Instalar PWA'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 17,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.go(Routes.login),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Iniciar sesion'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _HeroOfferStrip(),
      ],
    );

    const visual = _HeroImage();

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [text],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 8, child: text),
        const SizedBox(width: 36),
        const Expanded(flex: 9, child: visual),
      ],
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      tween: Tween(begin: 0.96, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 26),
          child: Transform.scale(
            scale: value,
            child: Opacity(opacity: value, child: child),
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7E5EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2310253E),
                  blurRadius: 42,
                  offset: Offset(0, 24),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: compact ? 1.12 : 1.38,
                    child: Image.asset(
                      'assets/image/landing-pos-cloud.png',
                      fit: compact ? BoxFit.scaleDown : BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: _GlassBadge(
                      icon: Icons.cloud_done_rounded,
                      label: 'Nube + POS',
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _GlassBadge(
                      icon: Icons.devices_rounded,
                      label: 'Web, Windows y movil',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0B1728),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF1D4ED8), size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF10233D),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroOfferStrip extends StatelessWidget {
  const _HeroOfferStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF4D38B)),
      ),
      child: const Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _OfferMini(icon: Icons.sell_rounded, text: 'RD\$ 1,000 mensual'),
          _OfferMini(
            icon: Icons.groups_2_rounded,
            text: '2 usuarios incluidos',
          ),
          _OfferMini(icon: Icons.inventory_2_rounded, text: '100 productos'),
          _OfferMini(
            icon: Icons.savings_rounded,
            text: 'Ahorra RD\$ 2,000 anual',
          ),
        ],
      ),
    );
  }
}

class _OfferMini extends StatelessWidget {
  const _OfferMini({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF9A5A00), size: 18),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5C3B00),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _InstallPanel extends StatelessWidget {
  const _InstallPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22102033),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 980
              ? 4
              : constraints.maxWidth > 660
              ? 2
              : 1;
          final gap = 12.0;
          final cardWidth =
              (constraints.maxWidth - (gap * (columns - 1))) / columns;
          final actions = [
            _InstallAction(
              icon: Icons.language_rounded,
              title: 'Web / PWA',
              copy: 'Usalo desde Chrome, Edge o Safari.',
              label: 'Instalar',
              isPrimary: true,
              onTap: () => _requestInstall(context),
            ),
            _InstallAction(
              icon: Icons.desktop_windows_rounded,
              title: 'Windows',
              copy: 'Caja, mostrador e impresion.',
              label: 'Descargar',
              onTap: () => LandingScreen.openWindowsDownload(context),
            ),
            _InstallAction(
              icon: Icons.android_rounded,
              title: 'Android',
              copy: 'Telefono o tablet del equipo.',
              label: 'Descargar',
              onTap: () => LandingScreen.openAndroidDownload(context),
            ),
            _InstallAction(
              icon: Icons.phone_iphone_rounded,
              title: 'iPhone',
              copy: 'Acceso desde Safari como PWA.',
              label: 'Ver PWA',
              onTap: () => _requestInstall(context),
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(width: cardWidth, child: action),
            ],
          );
        },
      ),
    );
  }
}

class _InstallAction extends StatelessWidget {
  const _InstallAction({
    required this.icon,
    required this.title,
    required this.copy,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String title;
  final String copy;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 360;
        final iconBox = Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        );
        final textBlock = Column(
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
              copy,
              maxLines: stacked ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD7E3EF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

        return Container(
          constraints: BoxConstraints(minHeight: stacked ? 150 : 104),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isPrimary
                ? const Color(0xFF1D4ED8)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        iconBox,
                        const SizedBox(width: 12),
                        Expanded(child: textBlock),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: onTap, child: Text(label)),
                  ],
                )
              : Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: textBlock),
                    const SizedBox(width: 8),
                    FilledButton.tonal(onPressed: onTap, child: Text(label)),
                  ],
                ),
        );
      },
    );
  }
}

class _ProofSection extends StatelessWidget {
  const _ProofSection();

  @override
  Widget build(BuildContext context) {
    final items = [
      _ProofItem(
        Icons.point_of_sale_rounded,
        'Facturacion rapida',
        'Catalogo visual, tickets, cotizaciones y cobro en pocos toques.',
      ),
      _ProofItem(
        Icons.inventory_2_rounded,
        'Inventario conectado',
        'Stock bajo, categorias, ajustes, conteo y compras relacionadas.',
      ),
      _ProofItem(
        Icons.analytics_rounded,
        'Reportes para decidir',
        'Ventas, utilidad, categorias, metodos de pago y movimientos claros.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 860
            ? 3
            : constraints.maxWidth > 560
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          itemBuilder: (context, index) => _ProofCard(item: items[index]),
        );
      },
    );
  }
}

class _ProofItem {
  const _ProofItem(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.item});

  final _ProofItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: const Color(0xFF2563EB), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0D1B2A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.copy,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF60748C),
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
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

class _ModulesSection extends StatelessWidget {
  const _ModulesSection();

  @override
  Widget build(BuildContext context) {
    const items = [
      _ModuleItem(
        Icons.point_of_sale_rounded,
        'Facturacion POS',
        'Ventas rapidas, tickets, impuestos, cobro y flujo de mostrador.',
      ),
      _ModuleItem(
        Icons.request_quote_rounded,
        'Cotizaciones',
        'Presupuestos, historial, clientes y documentos listos para compartir.',
      ),
      _ModuleItem(
        Icons.inventory_2_rounded,
        'Inventario',
        'Productos, categorias, costos, precios, stock bajo y conteos.',
      ),
      _ModuleItem(
        Icons.shopping_bag_rounded,
        'Compras',
        'Ordenes, suplidores, facturas de compra y productos por reponer.',
      ),
      _ModuleItem(
        Icons.account_balance_wallet_rounded,
        'Caja',
        'Turnos, ingresos, gastos, movimientos y cierre diario del efectivo.',
      ),
      _ModuleItem(
        Icons.people_alt_rounded,
        'Clientes',
        'Registro de clientes, historial comercial y datos de contacto.',
      ),
      _ModuleItem(
        Icons.analytics_rounded,
        'Reportes',
        'Ventas, utilidad, ticket promedio, categorias y metodos de pago.',
      ),
      _ModuleItem(
        Icons.account_balance_rounded,
        'Contabilidad',
        'Cierres, depositos, pagos pendientes y control administrativo.',
      ),
      _ModuleItem(
        Icons.admin_panel_settings_rounded,
        'Usuarios y permisos',
        'Accesos por rol para que cada empleado vea solo lo necesario.',
      ),
      _ModuleItem(
        Icons.cloud_sync_rounded,
        'Trabajo en la nube',
        'Datos disponibles para equipos autorizados desde distintos equipos.',
      ),
      _ModuleItem(
        Icons.print_rounded,
        'Impresion y documentos',
        'Tickets, PDFs, comprobantes y documentos comerciales del negocio.',
      ),
      _ModuleItem(
        Icons.workspace_premium_rounded,
        'Licencias y soporte',
        'Control de acceso, renovacion y soporte directo por WhatsApp.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Sistema POS completo',
      title: 'Todo lo que necesita tu punto de venta en una sola pagina',
      copy:
          'FullPOS Cloud cubre el ciclo diario del negocio: vender, cobrar, comprar, controlar inventario, revisar utilidad y administrar usuarios.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 980
              ? 4
              : constraints.maxWidth > 680
              ? 3
              : constraints.maxWidth > 460
              ? 2
              : 1;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 176,
            ),
            itemBuilder: (context, index) => _ModuleCard(item: items[index]),
          );
        },
      ),
    );
  }
}

class _PlatformGuideSection extends StatelessWidget {
  const _PlatformGuideSection();

  @override
  Widget build(BuildContext context) {
    const items = [
      _PlatformItem(
        Icons.language_rounded,
        'Web / PWA',
        'Abre el sistema en el navegador e instalalo como app desde Chrome, Edge o Safari.',
      ),
      _PlatformItem(
        Icons.desktop_windows_rounded,
        'Windows',
        'Descarga el instalador para caja, mostrador, facturacion e impresion.',
      ),
      _PlatformItem(
        Icons.android_rounded,
        'Android',
        'Usa la app en telefonos y tablets para vender, consultar y operar con tu equipo.',
      ),
      _PlatformItem(
        Icons.phone_iphone_rounded,
        'iPhone',
        'Instala la PWA desde Safari y trabaja con la misma cuenta y datos del negocio.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Web, movil y escritorio',
      title: 'Un sistema potente multi plataforma',
      copy:
          'Puedes trabajar en la nube desde la web, instalar la PWA, usar Windows en el punto de venta y operar desde Android o iPhone cuando necesites movilidad.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 860
              ? 4
              : constraints.maxWidth > 560
              ? 2
              : 1;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 172,
            ),
            itemBuilder: (context, index) => _PlatformCard(item: items[index]),
          );
        },
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.eyebrow,
    required this.title,
    required this.copy,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String copy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(eyebrow: eyebrow, title: title, copy: copy),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ModuleItem {
  const _ModuleItem(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _PlatformItem {
  const _PlatformItem(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.item});

  final _ModuleItem item;

  @override
  Widget build(BuildContext context) {
    return _FeatureTile(
      icon: item.icon,
      title: item.title,
      copy: item.copy,
      accent: const Color(0xFF1D4ED8),
      background: const Color(0xFFEAF2FF),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.item});

  final _PlatformItem item;

  @override
  Widget build(BuildContext context) {
    return _FeatureTile(
      icon: item.icon,
      title: item.title,
      copy: item.copy,
      accent: const Color(0xFF0F8C7D),
      background: const Color(0xFFE8F8F5),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.copy,
    required this.accent,
    required this.background,
  });

  final IconData icon;
  final String title;
  final String copy;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0D1B2A),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF60748C),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingSection extends StatelessWidget {
  const _PricingSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100B2744),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final plan = _PlanCard(compact: compact);
          final copy = _PricingCopy(compact: compact);

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 16), plan],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 6, child: copy),
              const SizedBox(width: 22),
              Expanded(flex: 4, child: plan),
            ],
          );
        },
      ),
    );
  }
}

class _PricingCopy extends StatelessWidget {
  const _PricingCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          eyebrow: 'Oferta de lanzamiento',
          title: 'Plan basico para negocios que quieren empezar ordenados',
          copy:
              'Incluye dos usuarios y hasta 100 productos. Para equipos mas grandes, inventarios avanzados o necesidades especiales, escribenos y preparamos un plan a la medida.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _CheckChip(label: '2 usuarios'),
            _CheckChip(label: '100 productos'),
            _CheckChip(label: 'Web, PWA, Android, iPhone y Windows'),
            _CheckChip(label: 'Soporte por WhatsApp'),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => LandingScreen.openWhatsApp(context),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Escribir al WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.login),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Ya tengo cuenta'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1728),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF20344C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF16A394).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF58D7CA)),
            ),
            child: const Text(
              'Plan basico',
              style: TextStyle(
                color: Color(0xFFA7FFF6),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'RD\$ 1,000',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'mensuales',
            style: TextStyle(
              color: Color(0xFFC9D7E8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          const _PlanDivider(),
          const SizedBox(height: 16),
          const _PlanRow('Licencia anual', 'RD\$ 10,000'),
          const SizedBox(height: 8),
          const _PlanRow('Descuento anual', 'RD\$ 2,000'),
          const SizedBox(height: 8),
          const _PlanRow('Incluye', '2 usuarios + 100 productos'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => LandingScreen.openWhatsApp(context),
              icon: const Icon(Icons.local_offer_rounded, size: 18),
              label: const Text('Quiero la oferta'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Planes avanzados disponibles por cotizacion.',
            style: TextStyle(
              color: Color(0xFFAEBFD2),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDivider extends StatelessWidget {
  const _PlanDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Colors.white.withValues(alpha: 0.12));
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFAEBFD2),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection();

  @override
  Widget build(BuildContext context) {
    return const _SplitSection(
      eyebrow: 'Operaciones completas',
      title: 'Todo el negocio organizado desde una sola plataforma',
      copy:
          'FullPOS Cloud esta preparado para negocios que necesitan velocidad en caja, control de inventario, clientes, cotizaciones, compras y reportes sin perder orden.',
      points: [
        'Facturacion y cotizaciones',
        'Inventario por categorias',
        'Compras y suplidores',
        'Reportes de ventas y utilidad',
      ],
      image: 'assets/image/landing-mobile-sale.png',
      imageOnRight: true,
    );
  }
}

class _MobileExperienceSection extends StatelessWidget {
  const _MobileExperienceSection();

  @override
  Widget build(BuildContext context) {
    return const _SplitSection(
      eyebrow: 'Experiencia multi plataforma',
      title: 'Una interfaz clara para web, movil y escritorio',
      copy:
          'Trabaja desde Windows en el mostrador, Android en el telefono, iPhone desde Safari y web/PWA en el navegador. Cada usuario entra solo a lo que necesita.',
      points: [
        'Menu por modulos',
        'Acceso rapido desde movil y escritorio',
        'Diseño preparado para PWA web',
        'Sesiones y permisos de usuario',
      ],
      image: 'assets/image/landing-mobile-drawer.png',
      imageOnRight: false,
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.eyebrow,
    required this.title,
    required this.copy,
    required this.points,
    required this.image,
    required this.imageOnRight,
  });

  final String eyebrow;
  final String title;
  final String copy;
  final List<String> points;
  final String image;
  final bool imageOnRight;

  @override
  Widget build(BuildContext context) {
    final text = _InfoText(
      eyebrow: eyebrow,
      title: title,
      copy: copy,
      points: points,
    );
    final visual = _TallImage(image: image);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [text, const SizedBox(height: 16), visual],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: imageOnRight ? 7 : 5,
              child: imageOnRight ? text : visual,
            ),
            const SizedBox(width: 22),
            Expanded(
              flex: imageOnRight ? 5 : 7,
              child: imageOnRight ? visual : text,
            ),
          ],
        );
      },
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText({
    required this.eyebrow,
    required this.title,
    required this.copy,
    required this.points,
  });

  final String eyebrow;
  final String title;
  final String copy;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(eyebrow: eyebrow, title: title, copy: copy),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final point in points) _CheckChip(label: point)],
          ),
        ],
      ),
    );
  }
}

class _TallImage extends StatelessWidget {
  const _TallImage({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B2440),
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Image.asset(image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PlatformSecuritySection extends StatelessWidget {
  const _PlatformSecuritySection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'Nube, permisos y continuidad',
            title: 'Un POS potente para crecer sin cambiar de sistema',
            copy:
                'La informacion queda centralizada por empresa y disponible para el equipo autorizado. Ideal para empezar con el plan basico y escalar a un plan avanzado cuando el negocio lo pida.',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 860
                  ? 4
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              final items = [
                _SecurityItem(Icons.cloud_done_rounded, 'Nube centralizada'),
                _SecurityItem(Icons.lock_rounded, 'Acceso protegido'),
                _SecurityItem(Icons.sync_rounded, 'Actualizaciones simples'),
                _SecurityItem(
                  Icons.devices_rounded,
                  'Windows, Android, iPhone y web',
                ),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 74,
                ),
                itemBuilder: (context, index) =>
                    _SecurityMiniCard(item: items[index]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SecurityItem {
  const _SecurityItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _SecurityMiniCard extends StatelessWidget {
  const _SecurityMiniCard({required this.item});

  final _SecurityItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: const Color(0xFF0F8C7D), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0D1B2A),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFCBE3FF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF075EB8),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ValueBullets extends StatelessWidget {
  const _ValueBullets();

  @override
  Widget build(BuildContext context) {
    const bullets = [
      (Icons.speed_rounded, 'Vende rapido'),
      (Icons.devices_rounded, 'Multi plataforma'),
      (Icons.account_balance_rounded, 'Control diario'),
    ];

    Widget bullet((IconData, String) item, bool stacked) {
      return Container(
        width: stacked ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDCE8EF)),
        ),
        child: Row(
          mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(item.$1, color: const Color(0xFF2563EB), size: 18),
            const SizedBox(width: 8),
            if (stacked)
              Expanded(
                child: Text(
                  item.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF20344C),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            else
              Text(
                item.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF20344C),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in bullets) ...[
                bullet(item, true),
                if (item != bullets.last) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final item in bullets) bullet(item, false)],
        );
      },
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: Color(0xFF0F8C7D), size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF163A3A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.copy,
  });

  final String eyebrow;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: Color(0xFF2563EB),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0D1B2A),
            fontSize: 25,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          copy,
          style: const TextStyle(
            color: Color(0xFF60748C),
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LandingDrawer extends StatelessWidget {
  const _LandingDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Image.asset('assets/image/logo.png', width: 42, height: 42),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'FullPOS Cloud',
                    style: TextStyle(
                      color: Color(0xFF0D1B2A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!isBusinessRegistrationDisabledOnCurrentPlatform)
              _DrawerAction(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Crear mi cuenta',
                onTap: () => context.go(Routes.register),
              ),
            _DrawerAction(
              icon: Icons.chat_rounded,
              label: 'WhatsApp $_supportPhoneDisplay',
              onTap: () => LandingScreen.openWhatsApp(context),
            ),
            _DrawerAction(
              icon: Icons.login_rounded,
              label: 'Iniciar sesion',
              onTap: () => context.go(Routes.login),
            ),
            _DrawerAction(
              icon: Icons.add_to_home_screen_rounded,
              label: 'Instalar PWA',
              onTap: () => _requestInstall(context),
            ),
            _DrawerAction(
              icon: Icons.desktop_windows_rounded,
              label: 'Descargar Windows',
              onTap: () => LandingScreen.openWindowsDownload(context),
            ),
            _DrawerAction(
              icon: Icons.android_rounded,
              label: 'Descargar Android APK',
              onTap: () => LandingScreen.openAndroidDownload(context),
            ),
            const Divider(height: 28),
            _DrawerAction(
              icon: Icons.info_outline_rounded,
              label: 'Ver beneficios',
              onTap: () => _showInfoSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinalCtaSection extends StatelessWidget {
  const _FinalCtaSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1728),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3554)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Empieza con FullPOS Cloud hoy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Plan basico desde RD\$ 1,000 mensual. Instalable como PWA, disponible para Windows, Android e iPhone, con soporte directo por WhatsApp.',
                style: TextStyle(
                  color: Color(0xFFC9D7E8),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: () => LandingScreen.openWhatsApp(context),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('WhatsApp $_supportPhoneDisplay'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.login),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Iniciar sesion'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 16), actions],
            );
          }

          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 22),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2563EB)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      onTap: () {
        Navigator.of(context).maybePop();
        onTap();
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '© 2026 FullPOS Cloud - POS multi plataforma para facturacion, inventario y gestion comercial.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(0xFF66788D),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

void _requestInstall(BuildContext context) {
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
}

void _showInfoSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FullPOS Cloud conecta tu operacion diaria',
              style: TextStyle(
                color: Color(0xFF0D1B2A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Facturacion, inventario, compras, clientes, caja, reportes y contabilidad trabajan juntos desde web/PWA, Windows, Android e iPhone. Plan basico desde RD\$ 1,000 mensual. WhatsApp: $_supportPhoneDisplay.',
              style: TextStyle(
                color: Color(0xFF60748C),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    },
  );
}
