import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_access/app_access_links.dart';
import '../../../core/auth/business_registration_policy.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import 'pwa_install_prompt.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static Uri get _windowsDownloadUri => AppAccessLinks.windowsReleaseUri;
  static Uri get _androidDownloadUri => AppAccessLinks.androidReleaseUri;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final businessRegistrationDisabled =
        isBusinessRegistrationDisabledOnCurrentPlatform;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      endDrawer: const _LandingDrawer(),
      body: SafeArea(
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
                        SizedBox(height: isMobile ? 24 : 44),
                        _Hero(
                          isMobile: isMobile,
                          businessRegistrationDisabled:
                              businessRegistrationDisabled,
                        ),
                        const SizedBox(height: 18),
                        const _InstallPanel(),
                        if (isMobile) ...[
                          const SizedBox(height: 18),
                          const _HeroImage(),
                        ],
                        const SizedBox(height: 28),
                        const _ProofSection(),
                        const SizedBox(height: 28),
                        const _BusinessSection(),
                        const SizedBox(height: 28),
                        const _MobileExperienceSection(),
                        const SizedBox(height: 28),
                        const _PlatformSecuritySection(),
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
                'POS en la nube para colmados, farmacias y tiendas',
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
            child: const Text('Beneficios'),
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
            _Pill('PWA web'),
            _Pill('Windows'),
            _Pill('Android'),
            _Pill('Datos seguros'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'FullPOS Cloud',
          style: TextStyle(
            color: const Color(0xFF0B1728),
            fontSize: isMobile ? 42 : 66,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Factura, cobra y controla tu negocio completo desde la nube. Ideal para colmados, farmacias, minimarkets y tiendas que necesitan vender rapido sin perder control del inventario.',
          style: TextStyle(
            color: Color(0xFF3E536B),
            fontSize: 17,
            height: 1.5,
            fontWeight: FontWeight.w600,
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
                onPressed: () => context.go(Routes.register),
                icon: const Icon(Icons.rocket_launch_rounded, size: 19),
                label: const Text('Crear mi cuenta'),
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
              child: AspectRatio(
                aspectRatio: compact ? 1.12 : 1.38,
                child: Image.asset(
                  'assets/image/landing-pos-cloud.png',
                  fit: compact ? BoxFit.scaleDown : BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
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
          final columns = constraints.maxWidth > 900
              ? 3
              : constraints.maxWidth > 620
              ? 2
              : 1;
          final gap = 12.0;
          final cardWidth =
              (constraints.maxWidth - (gap * (columns - 1))) / columns;
          final actions = [
            _InstallAction(
              icon: Icons.add_to_home_screen_rounded,
              title: 'Instalar PWA',
              copy: 'Abre como app desde Chrome o Edge.',
              label: 'Instalar',
              isPrimary: true,
              onTap: () => _requestInstall(context),
            ),
            _InstallAction(
              icon: Icons.desktop_windows_rounded,
              title: 'Windows',
              copy: 'Para caja y mostrador.',
              label: 'Descargar',
              onTap: () => LandingScreen.openWindowsDownload(context),
            ),
            _InstallAction(
              icon: Icons.android_rounded,
              title: 'Android APK',
              copy: 'Para telefono o tablet.',
              label: 'Descargar',
              onTap: () => LandingScreen.openAndroidDownload(context),
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
        'Venta rapida',
        'Catalogo visual, tickets y cobro en pocos toques.',
      ),
      _ProofItem(
        Icons.inventory_2_rounded,
        'Inventario claro',
        'Stock bajo, categorias, ajustes y conteo.',
      ),
      _ProofItem(
        Icons.receipt_long_rounded,
        'Control completo',
        'Compras, clientes, reportes y contabilidad conectados.',
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

class _BusinessSection extends StatelessWidget {
  const _BusinessSection();

  @override
  Widget build(BuildContext context) {
    return const _SplitSection(
      eyebrow: 'Hecho para vender mas ordenado',
      title: 'Colmados, farmacias y tiendas pueden operar sin complicarse',
      copy:
          'FullPOS Cloud ayuda a tu equipo a facturar rapido, evitar ventas sin stock, revisar ganancias y mantener cada movimiento del negocio bajo control.',
      points: [
        'Facturacion y cotizaciones',
        'Inventario por categorias',
        'Compras y suplidores',
        'Reportes para decidir mejor',
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
      eyebrow: 'Experiencia clara para tu equipo',
      title: 'Un menu limpio para entrar rapido a cada modulo',
      copy:
          'Ventas, caja, clientes, inventario, compras, reportes y contabilidad quedan organizados para que el usuario encuentre lo que necesita sin perder tiempo.',
      points: [
        'Menu por modulos',
        'Acceso rapido desde movil',
        'Diseño preparado para PWA',
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
            eyebrow: 'Sistema en la nube',
            title: 'Tus datos disponibles y protegidos',
            copy:
                'El negocio puede trabajar desde web, Windows o Android con informacion centralizada, usuarios controlados y actualizaciones de PWA sin instalaciones pesadas.',
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
                _SecurityItem(Icons.devices_rounded, 'Multi-plataforma'),
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
      (Icons.inventory_rounded, 'Controla stock'),
      (Icons.account_balance_rounded, 'Cierra el dia'),
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
      '© 2026 FullPOS Cloud - Facturacion, inventario y gestion comercial en la nube.',
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
              'FullPOS Cloud resume tu operacion diaria',
              style: TextStyle(
                color: Color(0xFF0D1B2A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Facturacion, inventario, compras, clientes, caja, reportes y contabilidad trabajan juntos para que el negocio venda mas ordenado desde cualquier dispositivo.',
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
