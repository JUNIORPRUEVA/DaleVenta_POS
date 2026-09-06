import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_access/app_access_links.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import 'pwa_install_prompt.dart';

const _supportPhoneDisplay = '829-531-9442';
const _supportWhatsappIntl = '18295319442';

const _primary = Color(0xFF1957E6);
const _primaryDark = Color(0xFF123A75);
const _accent = Color(0xFF26B6A6);
const _ink = Color(0xFF0D1B2A);
const _muted = Color(0xFF5E7187);
const _line = Color(0xFFDCE8EF);
const _soft = Color(0xFFF3F7FA);
const _maxContentWidth = 1220.0;

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static final _topKey = GlobalKey();
  static final _featuresKey = GlobalKey();
  static final _demoKey = GlobalKey();
  static final _pricingKey = GlobalKey();
  static final _processKey = GlobalKey();
  static final _faqKey = GlobalKey();

  static Future<void> openGenericWhatsApp(BuildContext context) {
    return _openWhatsApp(
      context,
      'Hola, quiero información sobre FullPOS Cloud y sus planes.',
    );
  }

  static Future<void> _openPlanWhatsApp(BuildContext context, _PlanInfo plan) {
    return _openWhatsApp(context, _planWhatsAppMessage(plan));
  }

  static Future<void> _openWhatsApp(BuildContext context, String text) {
    return safeOpenWhatsApp(
      context,
      Uri.https('wa.me', '/$_supportWhatsappIntl', {'text': text}),
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
    );
  }

  static Future<void> openWindowsDownload(BuildContext context) {
    return safeOpenUrl(
      context,
      AppAccessLinks.windowsReleaseUri,
      copiedMessage: 'No se pudo abrir la descarga. Enlace copiado.',
    );
  }

  static Future<void> openAndroidDownload(BuildContext context) {
    return safeOpenUrl(
      context,
      AppAccessLinks.androidReleaseUri,
      copiedMessage: 'No se pudo abrir la descarga. Enlace copiado.',
    );
  }

  static Future<void> openIphoneDownload(BuildContext context) {
    return safeOpenUrl(
      context,
      AppAccessLinks.iosAppStoreUri,
      copiedMessage: 'No se pudo abrir App Store. Enlace copiado.',
    );
  }

  static Future<void> openPwa(BuildContext context) {
    return safeOpenUrl(
      context,
      AppAccessLinks.pwaUri,
      copiedMessage: 'No se pudo abrir la PWA. Enlace copiado.',
    );
  }

  static Future<void> installPwa(BuildContext context) async {
    final prompted = requestPwaInstallPrompt();
    if (prompted) return;
    return openPwa(context);
  }

  static void scrollTo(BuildContext context, GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 1180;
    final isNarrowPhone = MediaQuery.sizeOf(context).width < 560;
    final baseTheme = Theme.of(context);

    return Scaffold(
      backgroundColor: _soft,
      endDrawer: _LandingDrawer(onNav: (key) => scrollTo(context, key)),
      floatingActionButton: const _FloatingWhatsAppButton(),
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
                  child: _TopBar(
                    isMobile: isMobile,
                    onNav: (key) => scrollTo(context, key),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Align(
                    alignment: isNarrowPhone
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxContentWidth,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isNarrowPhone
                              ? 12
                              : isMobile
                              ? 18
                              : 38,
                          isMobile ? 20 : 38,
                          isNarrowPhone
                              ? 12
                              : isMobile
                              ? 18
                              : 38,
                          isMobile ? 28 : 40,
                        ),
                        child: Column(
                          key: _topKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _HeroSection(),
                            const SizedBox(height: 28),
                            _Anchor(
                              key: _featuresKey,
                              child: const _BenefitsSection(),
                            ),
                            const SizedBox(height: 34),
                            _Anchor(key: _demoKey, child: const _DemoSection()),
                            const SizedBox(height: 34),
                            _Anchor(
                              key: _processKey,
                              child: const _PurchaseProcessSection(),
                            ),
                            const SizedBox(height: 34),
                            _Anchor(
                              key: _pricingKey,
                              child: const _PricingSection(),
                            ),
                            const SizedBox(height: 34),
                            _Anchor(key: _faqKey, child: const _FaqSection()),
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
        ),
      ),
    );
  }
}

String _planWhatsAppMessage(_PlanInfo plan) {
  return '''
Hola, me interesa adquirir FullPOS Cloud.

Plan: ${plan.name}
Período inicial: 3 meses
Total: ${plan.total}
Equivalente: ${plan.monthlyEquivalent}/mes

Quiero recibir las instrucciones para realizar la transferencia bancaria.''';
}

class _Anchor extends StatelessWidget {
  const _Anchor({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isMobile, required this.onNav});

  final bool isMobile;
  final ValueChanged<GlobalKey> onNav;

  @override
  Widget build(BuildContext context) {
    final isNarrowPhone = MediaQuery.sizeOf(context).width < 560;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Align(
        alignment: isNarrowPhone ? Alignment.centerLeft : Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isNarrowPhone ? 370 : _maxContentWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrowPhone
                  ? 12
                  : isMobile
                  ? 18
                  : 38,
              vertical: isMobile ? 10 : 12,
            ),
            child: Row(
              children: [
                if (isMobile)
                  const Expanded(child: _BrandMark())
                else
                  const _BrandMark(),
                if (!isMobile) const Spacer(),
                if (isMobile)
                  Builder(
                    builder: (context) => IconButton.filledTonal(
                      tooltip: 'Menu',
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  )
                else ...[
                  _NavButton(
                    'Funciones',
                    onTap: () => onNav(LandingScreen._featuresKey),
                  ),
                  _NavButton(
                    'Empieza',
                    onTap: () => onNav(LandingScreen._demoKey),
                  ),
                  _NavButton(
                    'Planes',
                    onTap: () => onNav(LandingScreen._pricingKey),
                  ),
                  _NavButton(
                    'Cómo funciona',
                    onTap: () => onNav(LandingScreen._processKey),
                  ),
                  _NavButton('FAQ', onTap: () => onNav(LandingScreen._faqKey)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => context.go(Routes.login),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF43566D),
                      minimumSize: const Size(0, 42),
                    ),
                    child: const Text('Iniciar sesión'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.register),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    label: const Text('Crear cuenta gratis'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x160B2744),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/image/logo-web.webp', fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FullPOS Cloud',
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'FULLTECH SRL',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF43566D),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 40),
      ),
      child: Text(label),
    );
  }
}

class _LandingDrawer extends StatelessWidget {
  const _LandingDrawer({required this.onNav});

  final ValueChanged<GlobalKey> onNav;

  @override
  Widget build(BuildContext context) {
    void go(GlobalKey key) {
      Navigator.of(context).maybePop();
      WidgetsBinding.instance.addPostFrameCallback((_) => onNav(key));
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _BrandMark(),
            const SizedBox(height: 18),
            _DrawerAction('Funciones', Icons.grid_view_rounded, () {
              go(LandingScreen._featuresKey);
            }),
            _DrawerAction('Empieza tu prueba', Icons.rocket_launch_rounded, () {
              go(LandingScreen._demoKey);
            }),
            _DrawerAction('Planes', Icons.payments_rounded, () {
              go(LandingScreen._pricingKey);
            }),
            _DrawerAction('Cómo funciona', Icons.route_rounded, () {
              go(LandingScreen._processKey);
            }),
            _DrawerAction('FAQ', Icons.help_outline_rounded, () {
              go(LandingScreen._faqKey);
            }),
            const Divider(height: 28),
            _DrawerAction('Iniciar sesión', Icons.login_rounded, () {
              Navigator.of(context).maybePop();
              context.go(Routes.login);
            }),
            _DrawerAction('Crear cuenta', Icons.person_add_alt_1_rounded, () {
              Navigator.of(context).maybePop();
              context.go(Routes.register);
            }, emphasized: true),
          ],
        ),
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  const _DrawerAction(
    this.label,
    this.icon,
    this.onTap, {
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: emphasized ? _primary : const Color(0xFF43566D),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: emphasized ? _primaryDark : _ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final veryCompact = constraints.maxWidth < 380;
        final titleSize = veryCompact
            ? 29.0
            : compact
            ? 32.0
            : 52.0;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _Badge(
                icon: Icons.rocket_launch_rounded,
                label: 'Prueba gratis por 7 días',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Vende y controla tu negocio desde cualquier dispositivo',
              style: TextStyle(
                color: _ink,
                fontSize: titleSize,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            const Text(
              'Crea tu cuenta una vez y usa FullPOS en Windows, Android, iPhone o Web.',
              style: TextStyle(
                color: Color(0xFF31465C),
                fontSize: 16,
                height: 1.42,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 18 : 22),
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.register),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                    label: const Text('Crear cuenta y probar gratis'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.go(Routes.login),
                    icon: const Icon(Icons.login_rounded, size: 19),
                    label: const Text('Ya tengo cuenta'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.register),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                    label: const Text('Crear cuenta y probar gratis'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(Routes.login),
                    icon: const Icon(Icons.login_rounded, size: 19),
                    label: const Text('Ya tengo cuenta'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ],
              ),
            SizedBox(height: compact ? 14 : 18),
            const _TrustPoints(),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: 16),
              const _ProductImageCard(
                image: 'assets/image/fullpos-windows-ios-android.webp',
                label: 'FullPOS Cloud en escritorio y móvil',
                aspectRatio: 1.82,
                contain: true,
                framed: false,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 8, child: text),
            const SizedBox(width: 36),
            const Expanded(
              flex: 9,
              child: _ProductImageCard(
                image: 'assets/image/fullpos-windows-ios-android.webp',
                label: 'FullPOS Cloud en escritorio y móvil',
                aspectRatio: 1.82,
                contain: true,
                framed: false,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrustPoints extends StatelessWidget {
  const _TrustPoints();

  @override
  Widget build(BuildContext context) {
    const items = [
      'Windows, Android, iPhone y Web',
      'Prueba gratis por 7 días',
      'Soporte vía WhatsApp',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items) ...[
          _InlineCheck(text: item),
          if (item != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BenefitsSection extends StatelessWidget {
  const _BenefitsSection();

  @override
  Widget build(BuildContext context) {
    const benefits = [
      _BenefitInfo(
        Icons.flash_on_rounded,
        'Vende rápido',
        'Agiliza el mostrador con facturación POS, búsqueda de productos, cobro y tickets listos para entregar.',
      ),
      _BenefitInfo(
        Icons.inventory_2_rounded,
        'Controla tu inventario',
        'Mantén productos, categorías, existencias, almacenes y movimientos organizados en una sola operación.',
      ),
      _BenefitInfo(
        Icons.account_balance_wallet_rounded,
        'Maneja caja y operaciones',
        'Administra turnos, ingresos, gastos, créditos, cotizaciones y compras con más orden diario.',
      ),
      _BenefitInfo(
        Icons.analytics_rounded,
        'Conoce cómo va tu negocio',
        'Consulta reportes de ventas, utilidad, métodos de pago y resultados para tomar mejores decisiones.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Funciones principales',
      title: 'Un POS para vender, controlar y decidir mejor',
      copy:
          'FullPOS Cloud reúne las herramientas esenciales para operar tu negocio con menos desorden y más visibilidad.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 900
              ? 4
              : constraints.maxWidth > 560
              ? 2
              : 1;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: benefits.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 190,
            ),
            itemBuilder: (context, index) => _BenefitCard(benefits[index]),
          );
        },
      ),
    );
  }
}

class _DemoSection extends StatelessWidget {
  const _DemoSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'Prueba gratis',
      title: 'Usa FullPOS donde quieras',
      copy:
          'Después de crear tu cuenta, inicia sesión con los mismos datos en tus dispositivos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              final cards = [
                _DownloadOptionCard(
                  icon: Icons.desktop_windows_rounded,
                  title: 'Windows',
                  description:
                      'También puedes crear tu cuenta desde FullPOS para Windows.',
                  actionLabel: 'Descargar para Windows',
                  onPressed: () => LandingScreen.openWindowsDownload(context),
                ),
                _DownloadOptionCard(
                  icon: Icons.android_rounded,
                  title: 'Android',
                  description:
                      'Crea primero tu cuenta desde la Web o Windows y luego inicia sesión.',
                  actionLabel: 'Descargar para Android',
                  onPressed: () => LandingScreen.openAndroidDownload(context),
                ),
                _DownloadOptionCard(
                  icon: Icons.phone_iphone_rounded,
                  title: 'iPhone',
                  description:
                      'Crea primero tu cuenta desde la Web o Windows y luego inicia sesión.',
                  actionLabel: 'Descargar para iPhone',
                  onPressed: () => LandingScreen.openIphoneDownload(context),
                ),
                _DownloadOptionCard(
                  icon: Icons.language_rounded,
                  title: 'Web / PWA',
                  description:
                      'Crea tu cuenta o usa FullPOS en el navegador como PWA.',
                  actionLabel: 'Crear cuenta',
                  onPressed: () => context.go(Routes.register),
                  secondaryActionLabel: 'Usar FullPOS en la Web',
                  onSecondaryPressed: () => LandingScreen.installPwa(context),
                  actionIcon: Icons.person_add_alt_1_rounded,
                ),
              ];
              return GridView.builder(
                itemCount: cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: columns == 1 ? 220 : 210,
                ),
                itemBuilder: (context, index) => cards[index],
              );
            },
          ),
          const SizedBox(height: 16),
          const _ProductImageCard(
            image: 'assets/image/fullpos-ios-android.webp',
            label: 'FullPOS Cloud en iPhone y Android',
            aspectRatio: 1.9,
            contain: true,
          ),
          const SizedBox(height: 12),
          const Text(
            '¿Vas a usar FullPOS en Android o iPhone? Crea primero tu cuenta desde la Web o Windows y luego inicia sesión en la app con los mismos datos.',
            style: TextStyle(
              color: Color(0xFF43566D),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DownloadOptionCard extends StatelessWidget {
  const _DownloadOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    this.secondaryActionLabel,
    this.onSecondaryPressed,
    this.actionIcon = Icons.open_in_new_rounded,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryPressed;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                color: Color(0xFF60748C),
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          if (secondaryActionLabel != null && onSecondaryPressed != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onSecondaryPressed,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(secondaryActionLabel!),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PurchaseProcessSection extends StatelessWidget {
  const _PurchaseProcessSection();

  @override
  Widget build(BuildContext context) {
    const steps = [
      _StepInfo(
        'Crea tu cuenta',
        'Regístrate gratis desde la Web o FullPOS para Windows.',
      ),
      _StepInfo(
        'Prueba FullPOS por 7 días',
        'Inicia sesión con la misma cuenta en Windows, Android, iPhone o Web y conoce FullPOS durante tu prueba.',
      ),
      _StepInfo(
        'Activa tu licencia',
        'Cuando quieras continuar, escríbenos por WhatsApp y activamos tu licencia después de confirmar el pago.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Cómo funciona',
      title: 'Crea tu cuenta, prueba y activa sin complicarte',
      copy:
          'Crea tu cuenta una sola vez y usa los mismos datos para iniciar sesión en tus dispositivos.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final whatsappButton = FilledButton.icon(
            onPressed: () => LandingScreen._openWhatsApp(
              context,
              'Hola, quiero activar mi licencia de FullPOS Cloud.',
            ),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Activar por WhatsApp'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < steps.length; index++)
                  _TimelineStep(
                    number: index + 1,
                    step: steps[index],
                    isLast: index == steps.length - 1,
                    compact: true,
                  ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: whatsappButton),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 0,
                runSpacing: 14,
                children: [
                  for (var index = 0; index < steps.length; index++)
                    SizedBox(
                      width: constraints.maxWidth / 3,
                      child: _TimelineStep(
                        number: index + 1,
                        step: steps[index],
                        isLast: index == steps.length - 1,
                        compact: false,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              whatsappButton,
            ],
          );
        },
      ),
    );
  }
}

class _PricingSection extends StatelessWidget {
  const _PricingSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'Planes y precios',
      title: 'Elige el plan que mejor se adapte a tu operación',
      copy:
          'La contratación mínima es de 3 meses. El pago se realiza por adelantado mediante transferencia bancaria.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 860;
              final cards = [for (final plan in _plans) _PlanCard(plan: plan)];
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final card in cards) ...[
                      card,
                      if (card != cards.last) const SizedBox(height: 14),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final card in cards) ...[
                      Expanded(child: card),
                      if (card != cards.last) const SizedBox(width: 14),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const _PricingTerms(),
        ],
      ),
    );
  }
}

class _PricingTerms extends StatelessWidget {
  const _PricingTerms();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: const Text(
        'Todos los planes incluyen ventas, inventario, caja, clientes, cotizaciones, reportes y soporte vía WhatsApp. La contratación mínima es de 3 meses y el pago es anticipado por transferencia bancaria.',
        style: TextStyle(
          color: Color(0xFF31465C),
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  @override
  Widget build(BuildContext context) {
    const faqs = [
      (
        '¿Cómo empiezo mi prueba gratis?',
        'Crea tu cuenta de FullPOS Cloud y comienza tu prueba gratis por 7 días sin contactar a soporte primero.',
      ),
      (
        '¿Dónde creo mi cuenta?',
        'Puedes crear tu cuenta desde la Web o desde FullPOS para Windows.',
      ),
      (
        '¿Cuánto dura la prueba?',
        'FullPOS Cloud incluye una prueba gratis de 7 días.',
      ),
      (
        '¿Puedo usar la misma cuenta en varios dispositivos?',
        'Sí. Crea tu cuenta una sola vez y usa los mismos datos para iniciar sesión en tus dispositivos.',
      ),
      (
        '¿Cómo uso FullPOS en Android o iPhone?',
        'Si vas a usar FullPOS en Android o iPhone, crea primero tu cuenta desde la Web o Windows y luego inicia sesión en la app con los mismos datos.',
      ),
      (
        '¿Cómo activo mi licencia después de la prueba?',
        'Durante la prueba o al finalizarla puedes escribirnos por WhatsApp para elegir tu plan y activar tu licencia después de confirmar el pago.',
      ),
      (
        '¿Cómo puedo pagar?',
        'Actualmente aceptamos transferencia bancaria. La contratación mínima es de 3 meses.',
      ),
      (
        '¿Cómo solicito asistencia?',
        'Si tienes dudas durante la prueba o necesitas activar tu licencia, escríbenos por WhatsApp.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Preguntas frecuentes',
      title: 'Respuestas rápidas para empezar',
      copy: 'Lo esencial sobre descarga, prueba, pago, activación y soporte.',
      child: Column(
        children: [
          for (final faq in faqs) _FaqTile(question: faq.$1, answer: faq.$2),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final links = Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _FooterLink(
                'Inicio',
                onTap: () =>
                    LandingScreen.scrollTo(context, LandingScreen._topKey),
              ),
              _FooterLink(
                'Funciones',
                onTap: () =>
                    LandingScreen.scrollTo(context, LandingScreen._featuresKey),
              ),
              _FooterLink(
                'Empieza',
                onTap: () =>
                    LandingScreen.scrollTo(context, LandingScreen._demoKey),
              ),
              _FooterLink(
                'Planes',
                onTap: () =>
                    LandingScreen.scrollTo(context, LandingScreen._pricingKey),
              ),
              _FooterRouteLink('Soporte', '/support'),
              _FooterRouteLink('Contacto', '/contact'),
              _FooterRouteLink('Términos', '/terms'),
              _FooterRouteLink('Privacidad', '/privacy'),
              _FooterRouteLink('Eliminación de cuenta', '/account-deletion'),
            ],
          );
          final brand = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _BrandMark(),
              SizedBox(height: 10),
              Text(
                'Sistema POS en la nube para ventas, inventario, caja, clientes y reportes.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'WhatsApp: $_supportPhoneDisplay',
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                const SizedBox(height: 14),
                links,
                const SizedBox(height: 14),
                const Text(
                  '© 2026 FULLTECH SRL. Todos los derechos reservados.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: brand),
              Expanded(flex: 2, child: links),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingWhatsAppButton extends StatelessWidget {
  const _FloatingWhatsAppButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FloatingActionButton.small(
        heroTag: 'landing-whatsapp',
        tooltip: 'Escríbenos por WhatsApp',
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: () => LandingScreen._openWhatsApp(
          context,
          'Hola, necesito asistencia con FullPOS Cloud.',
        ),
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _muted,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _FooterRouteLink extends StatelessWidget {
  const _FooterRouteLink(this.label, this.path);

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return _FooterLink(
      label,
      onTap: () => safeOpenUrl(context, Uri(path: path)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(eyebrow: eyebrow, title: title, copy: copy),
          const SizedBox(height: 20),
          child,
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
            color: _primary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 28,
                height: 1.16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Text(
              copy,
              style: const TextStyle(
                color: Color(0xFF60748C),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductImageCard extends StatelessWidget {
  const _ProductImageCard({
    required this.image,
    required this.label,
    required this.aspectRatio,
    this.contain = false,
    this.framed = true,
  });

  final String image;
  final String label;
  final double aspectRatio;
  final bool contain;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.asset(
          image,
          fit: contain ? BoxFit.contain : BoxFit.cover,
          semanticLabel: label,
        ),
      ),
    );

    if (!framed) {
      return SizedBox(width: double.infinity, child: imageWidget);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD7E5EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1810253E),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: imageWidget,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
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
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: [
          Icon(icon, color: _primary, size: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineCheck extends StatelessWidget {
  const _InlineCheck({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          decoration: const BoxDecoration(
            color: Color(0xFFEAF8F5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF0F8C7D),
            size: 16,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF31465C),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _BenefitInfo {
  const _BenefitInfo(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard(this.info);

  final _BenefitInfo info;

  @override
  Widget build(BuildContext context) {
    return _FeatureCard(
      icon: info.icon,
      title: info.title,
      copy: info.copy,
      accent: _primary,
      background: const Color(0xFFEAF2FF),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accent, size: 23),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Text(
              copy,
              style: const TextStyle(
                color: Color(0xFF60748C),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepInfo {
  const _StepInfo(this.title, this.copy);

  final String title;
  final String copy;
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.number,
    required this.step,
    required this.isLast,
    required this.compact,
  });

  final int number;
  final _StepInfo step;
  final bool isLast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final marker = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1957E6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step.title,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          step.copy,
          style: const TextStyle(
            color: Color(0xFF60748C),
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (compact) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                marker,
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: _line,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                child: content,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              marker,
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: _line,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
}

class _PlanInfo {
  const _PlanInfo({
    required this.name,
    required this.total,
    required this.monthlyEquivalent,
    required this.features,
    this.highlight = false,
  });

  final String name;
  final String total;
  final String monthlyEquivalent;
  final List<String> features;
  final bool highlight;
}

const _plans = [
  _PlanInfo(
    name: 'Básico',
    total: 'RD\$3,000',
    monthlyEquivalent: 'RD\$1,000',
    features: ['100 productos', '2 usuarios', '1 almacén', '1 caja / terminal'],
  ),
  _PlanInfo(
    name: 'Negocio',
    total: 'RD\$4,500',
    monthlyEquivalent: 'RD\$1,500',
    features: [
      '400 productos',
      '3 usuarios',
      '2 almacenes',
      '2 cajas / terminales',
    ],
    highlight: true,
  ),
  _PlanInfo(
    name: 'Pro',
    total: 'RD\$7,500',
    monthlyEquivalent: 'RD\$2,500',
    features: [
      '1,000 productos',
      '5 usuarios',
      '3 almacenes',
      '3 cajas / terminales',
    ],
  ),
];

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final _PlanInfo plan;

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.highlight;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFF4FAFF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? _primary : _line,
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x181957E6),
                  blurRadius: 26,
                  offset: Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (highlighted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'MÁS ELEGIDO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            plan.total,
            style: const TextStyle(
              color: _ink,
              fontSize: 36,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '/ 3 meses',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${plan.monthlyEquivalent}/mes equivalente',
            style: const TextStyle(
              color: _primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          for (final feature in plan.features) ...[
            _InlineCheck(text: feature),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => LandingScreen._openPlanWhatsApp(context, plan),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: Text('Activar ${plan.name}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: highlighted ? _primary : _primaryDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: _primary,
        collapsedIconColor: _primary,
        title: Text(
          question,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                color: Color(0xFF60748C),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
