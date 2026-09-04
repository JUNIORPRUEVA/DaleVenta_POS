import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';

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
  static final _platformsKey = GlobalKey();
  static final _pricingKey = GlobalKey();
  static final _processKey = GlobalKey();
  static final _supportKey = GlobalKey();
  static final _faqKey = GlobalKey();
  static final _showcaseKey = GlobalKey();

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
    final isMobile = MediaQuery.sizeOf(context).width < 820;
    final isNarrowPhone = MediaQuery.sizeOf(context).width < 560;
    final baseTheme = Theme.of(context);

    return Scaffold(
      backgroundColor: _soft,
      endDrawer: _LandingDrawer(onNav: (key) => scrollTo(context, key)),
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
                      child: SizedBox(
                        width: isNarrowPhone ? 370 : null,
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
                              const SizedBox(height: 18),
                              const _TrustStrip(),
                              const SizedBox(height: 34),
                              _Anchor(
                                key: _featuresKey,
                                child: const _BenefitsSection(),
                              ),
                              const SizedBox(height: 34),
                              _Anchor(
                                key: _showcaseKey,
                                child: const _ShowcaseSection(),
                              ),
                              const SizedBox(height: 34),
                              _Anchor(
                                key: _platformsKey,
                                child: const _PlatformsSection(),
                              ),
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
                              _Anchor(
                                key: _supportKey,
                                child: const _SupportSection(),
                              ),
                              const SizedBox(height: 34),
                              _Anchor(key: _faqKey, child: const _FaqSection()),
                              const SizedBox(height: 34),
                              const _FinalCtaSection(),
                              const SizedBox(height: 24),
                              const _Footer(),
                            ],
                          ),
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
                    'Plataformas',
                    onTap: () => onNav(LandingScreen._platformsKey),
                  ),
                  _NavButton(
                    'Planes',
                    onTap: () => onNav(LandingScreen._pricingKey),
                  ),
                  _NavButton(
                    'Cómo funciona',
                    onTap: () => onNav(LandingScreen._processKey),
                  ),
                  _NavButton(
                    'Soporte',
                    onTap: () => onNav(LandingScreen._supportKey),
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
                  FilledButton(
                    onPressed: () => onNav(LandingScreen._pricingKey),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('Ver planes'),
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
            _DrawerAction('Plataformas', Icons.devices_rounded, () {
              go(LandingScreen._platformsKey);
            }),
            _DrawerAction('Planes', Icons.payments_rounded, () {
              go(LandingScreen._pricingKey);
            }),
            _DrawerAction('Cómo funciona', Icons.route_rounded, () {
              go(LandingScreen._processKey);
            }),
            _DrawerAction('Soporte', Icons.support_agent_rounded, () {
              go(LandingScreen._supportKey);
            }),
            _DrawerAction('FAQ', Icons.help_outline_rounded, () {
              go(LandingScreen._faqKey);
            }),
            const Divider(height: 28),
            _DrawerAction('Iniciar sesión', Icons.login_rounded, () {
              Navigator.of(context).maybePop();
              context.go(Routes.login);
            }),
            _DrawerAction('Ver planes', Icons.arrow_downward_rounded, () {
              go(LandingScreen._pricingKey);
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
        final titleSize = compact ? 34.0 : 52.0;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _Badge(
                icon: Icons.point_of_sale_rounded,
                label: 'Sistema POS multiplataforma para negocios',
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
            const SizedBox(height: 16),
            const Text(
              'FullPOS Cloud reúne ventas, inventario, caja, clientes y reportes en una sola plataforma para Windows, Android, iPhone y Web.',
              style: TextStyle(
                color: Color(0xFF31465C),
                fontSize: 16.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => LandingScreen.scrollTo(
                      context,
                      LandingScreen._pricingKey,
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 19),
                    label: const Text('Ver planes y precios'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => LandingScreen.scrollTo(
                      context,
                      LandingScreen._showcaseKey,
                    ),
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 19,
                    ),
                    label: const Text('Ver FullPOS en acción'),
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
                    onPressed: () => LandingScreen.scrollTo(
                      context,
                      LandingScreen._pricingKey,
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 19),
                    label: const Text('Ver planes y precios'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => LandingScreen.scrollTo(
                      context,
                      LandingScreen._showcaseKey,
                    ),
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 19,
                    ),
                    label: const Text('Ver FullPOS en acción'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            const _TrustPoints(),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: 22),
              const _ProductImageCard(
                image: 'assets/image/landing-pos-cloud.webp',
                label: 'FullPOS Cloud en escritorio y móvil',
                aspectRatio: 1.82,
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
                image: 'assets/image/landing-pos-cloud.webp',
                label: 'FullPOS Cloud en escritorio y móvil',
                aspectRatio: 1.82,
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
      'Instalación remota incluida después de activar tu licencia',
      'Soporte remoto por WhatsApp',
      'Contratación mínima de 3 meses',
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

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.desktop_windows_rounded, 'Windows'),
      (Icons.android_rounded, 'Android'),
      (Icons.phone_iphone_rounded, 'iPhone'),
      (Icons.language_rounded, 'Web/PWA'),
      (Icons.support_agent_rounded, 'Instalación remota'),
      (Icons.chat_rounded, 'Soporte por WhatsApp'),
      (Icons.location_on_rounded, 'República Dominicana'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0B2744),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items) _MiniPill(icon: item.$1, label: item.$2),
        ],
      ),
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

class _ShowcaseSection extends StatelessWidget {
  const _ShowcaseSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'Producto real',
      title: 'FullPOS Cloud en acción',
      copy:
          'Una misma plataforma para vender y administrar tu negocio desde diferentes dispositivos.',
      child: Column(
        children: const [
          _ShowcaseRow(
            image: 'assets/image/landing-pos-cloud.webp',
            title: 'Tu operación conectada en una sola vista',
            copy:
                'Usa FullPOS Cloud para ventas, clientes, inventario y reportes desde web, escritorio o móvil, según el dispositivo que tengas disponible.',
            points: [
              'Interfaz real del producto',
              'Diseñado para trabajo diario',
              'Acceso desde distintos dispositivos',
            ],
            imageOnRight: false,
            aspectRatio: 1.82,
          ),
          SizedBox(height: 18),
          _ShowcaseRow(
            image: 'assets/image/landing-mobile-sale.webp',
            title: 'Ventas y gestión también desde móvil',
            copy:
                'El equipo puede operar y consultar información autorizada desde Android, iPhone o navegador, manteniendo el control del negocio.',
            points: [
              'Ventas y clientes',
              'Cotizaciones y compras',
              'Permisos por usuario',
            ],
            imageOnRight: true,
            aspectRatio: 1.5,
          ),
        ],
      ),
    );
  }
}

class _PlatformsSection extends StatelessWidget {
  const _PlatformsSection();

  @override
  Widget build(BuildContext context) {
    const platforms = [
      _PlatformInfo(
        Icons.desktop_windows_rounded,
        'Windows',
        'Para caja, mostrador, facturación e impresión térmica.',
      ),
      _PlatformInfo(
        Icons.android_rounded,
        'Android',
        'Para teléfonos y tablets del equipo autorizado.',
      ),
      _PlatformInfo(
        Icons.phone_iphone_rounded,
        'iPhone',
        'Acceso desde Safari como PWA para trabajar con tu cuenta.',
      ),
      _PlatformInfo(
        Icons.language_rounded,
        'Web/PWA',
        'Uso desde navegador compatible y opción de instalación web.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Multiplataforma',
      title: 'FullPOS donde lo necesites',
      copy:
          'Trabaja desde Windows, Android, iPhone y Web/PWA con la misma operación conectada.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final labels = GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: platforms.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth > 560 ? 2 : 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 142,
            ),
            itemBuilder: (context, index) => _PlatformCard(platforms[index]),
          );
          const visual = _ProductImageCard(
            image: 'assets/image/landing-pos-cloud.webp',
            label: 'FullPOS Cloud en Windows, Android, iPhone y Web',
            aspectRatio: 1.82,
            contain: true,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [visual, const SizedBox(height: 16), labels],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(flex: 6, child: visual),
              const SizedBox(width: 22),
              Expanded(flex: 5, child: labels),
            ],
          );
        },
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
        'Elige tu plan',
        'Selecciona el plan que mejor se adapte a tu negocio.',
      ),
      _StepInfo(
        'Escríbenos por WhatsApp',
        'Confirmamos contigo el plan, período y datos necesarios.',
      ),
      _StepInfo(
        'Realiza la transferencia',
        'Actualmente aceptamos pagos únicamente mediante transferencia bancaria.',
      ),
      _StepInfo(
        'Validamos tu pago',
        'Confirmamos la recepción del pago antes de activar la licencia.',
      ),
      _StepInfo(
        'Activamos tu licencia',
        'Preparamos el acceso correspondiente a tu plan.',
      ),
      _StepInfo(
        'Instalación y configuración remota',
        'Coordinamos contigo la instalación/configuración remota cuando corresponda.',
      ),
      _StepInfo(
        'Empieza a utilizar FullPOS',
        'Nuestro equipo te ayuda con la configuración inicial.',
      ),
      _StepInfo(
        'Renueva al finalizar',
        'Al finalizar el período adquirido, renuevas tu licencia para continuar.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Compra clara',
      title: 'Cómo adquirir FullPOS Cloud',
      copy:
          'El proceso está pensado para que sepas qué pagas, cuándo se activa tu licencia y cómo recibes la ayuda inicial.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          if (compact) {
            return Column(
              children: [
                for (var index = 0; index < steps.length; index++)
                  _TimelineStep(
                    number: index + 1,
                    step: steps[index],
                    isLast: index == steps.length - 1,
                    compact: true,
                  ),
              ],
            );
          }
          return Wrap(
            spacing: 0,
            runSpacing: 14,
            children: [
              for (var index = 0; index < steps.length; index++)
                SizedBox(
                  width: constraints.maxWidth / 4,
                  child: _TimelineStep(
                    number: index + 1,
                    step: steps[index],
                    isLast: index % 4 == 3 || index == steps.length - 1,
                    compact: false,
                  ),
                ),
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
          const SizedBox(height: 18),
          const _CommonBenefits(),
        ],
      ),
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1728),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F3452)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240B1728),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Badge(
                icon: Icons.support_agent_rounded,
                label: 'Soporte remoto',
                dark: true,
              ),
              SizedBox(height: 14),
              Text(
                'No te dejamos solo con el sistema',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Después de activar tu licencia, nuestro equipo te ayuda remotamente con la instalación y configuración inicial correspondiente.',
                style: TextStyle(
                  color: Color(0xFFD7E3EF),
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'También cuentas con soporte remoto vía WhatsApp para asistencia relacionada con FullPOS Cloud.',
                style: TextStyle(
                  color: Color(0xFFD7E3EF),
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final action = FilledButton.icon(
            onPressed: () => LandingScreen.openGenericWhatsApp(context),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Hablar por WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 18), action],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 24),
              action,
            ],
          );
        },
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
        '¿Qué es FullPOS Cloud?',
        'FullPOS Cloud es un sistema POS en la nube para administrar ventas, inventario, caja, clientes, cotizaciones, créditos, compras y reportes desde una misma plataforma.',
      ),
      (
        '¿En qué dispositivos puedo usar FullPOS Cloud?',
        'Puedes usar FullPOS Cloud en Windows, Android, iPhone y Web/PWA, de acuerdo con la plataforma y el acceso configurado para tu negocio.',
      ),
      (
        '¿Cuál es el período mínimo de licencia?',
        'La contratación mínima es de 3 meses.',
      ),
      (
        '¿Puedo pagar solamente un mes?',
        'No. Las licencias se adquieren por períodos mínimos de 3 meses.',
      ),
      (
        '¿Cómo puedo pagar?',
        'Actualmente aceptamos únicamente transferencia bancaria.',
      ),
      (
        '¿Debo pagar antes de la instalación?',
        'Sí. Una vez confirmado el pago de tu licencia, coordinamos contigo la instalación y configuración remota correspondiente.',
      ),
      (
        '¿La instalación está incluida?',
        'Sí. Después de confirmar y activar tu licencia, FullTech te ayuda remotamente con la instalación y configuración inicial correspondiente.',
      ),
      (
        '¿Cómo funciona el soporte?',
        'El soporte se ofrece de forma remota vía WhatsApp.',
      ),
      (
        '¿Qué sucede cuando vence mi licencia?',
        'Al finalizar el período adquirido, debes renovar tu licencia para continuar utilizando el servicio correspondiente.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Preguntas frecuentes',
      title: 'Respuestas claras antes de adquirir FullPOS Cloud',
      copy:
          'Estas son las dudas principales sobre contratación, pago, instalación remota y soporte.',
      child: Column(
        children: [
          for (final faq in faqs) _FaqTile(question: faq.$1, answer: faq.$2),
        ],
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
        color: const Color(0xFFF4FAFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBE3FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121957E6),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Empieza a controlar mejor tu negocio con FullPOS Cloud',
                style: TextStyle(
                  color: _ink,
                  fontSize: 28,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Elige el plan que mejor se adapte a tu negocio y escríbenos. Te explicaremos el proceso de pago y, una vez activada tu licencia, te ayudaremos remotamente con la instalación y configuración.',
                style: TextStyle(
                  color: Color(0xFF43566D),
                  fontSize: 15,
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
                onPressed: () =>
                    LandingScreen.scrollTo(context, LandingScreen._pricingKey),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Ver planes'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
              OutlinedButton.icon(
                onPressed: () => LandingScreen.openGenericWhatsApp(context),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Hablar por WhatsApp'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 18), actions],
            );
          }

          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 24),
              actions,
            ],
          );
        },
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
                'Plataformas',
                onTap: () => LandingScreen.scrollTo(
                  context,
                  LandingScreen._platformsKey,
                ),
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
  });

  final String image;
  final String label;
  final double aspectRatio;
  final bool contain;

  @override
  Widget build(BuildContext context) {
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Image.asset(
            image,
            fit: contain ? BoxFit.contain : BoxFit.cover,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

class _ShowcaseRow extends StatelessWidget {
  const _ShowcaseRow({
    required this.image,
    required this.title,
    required this.copy,
    required this.points,
    required this.imageOnRight,
    required this.aspectRatio,
  });

  final String image;
  final String title;
  final String copy;
  final List<String> points;
  final bool imageOnRight;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final text = _InfoPanel(title: title, copy: copy, points: points);
    final visual = _ProductImageCard(
      image: image,
      label: title,
      aspectRatio: aspectRatio,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [visual, const SizedBox(height: 14), text],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: imageOnRight ? 5 : 6,
              child: imageOnRight ? text : visual,
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: imageOnRight ? 6 : 5,
              child: imageOnRight ? visual : text,
            ),
          ],
        );
      },
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.copy,
    required this.points,
  });

  final String title;
  final String copy;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 22,
              height: 1.18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            copy,
            style: const TextStyle(
              color: Color(0xFF60748C),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          for (final point in points) ...[
            _InlineCheck(text: point),
            if (point != points.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, this.dark = false});

  final IconData icon;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.16)
              : const Color(0xFFCBE3FF),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: [
          Icon(icon, color: dark ? Colors.white : _primary, size: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : _primaryDark,
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

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 4,
        children: [
          Icon(icon, color: _primary, size: 17),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF20344C),
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

class _PlatformInfo {
  const _PlatformInfo(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard(this.info);

  final _PlatformInfo info;

  @override
  Widget build(BuildContext context) {
    return _FeatureCard(
      icon: info.icon,
      title: info.title,
      copy: info.copy,
      accent: const Color(0xFF0F8C7D),
      background: const Color(0xFFE8F8F5),
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
    required this.description,
    required this.total,
    required this.monthlyEquivalent,
    required this.features,
    this.highlight = false,
  });

  final String name;
  final String description;
  final String total;
  final String monthlyEquivalent;
  final List<String> features;
  final bool highlight;
}

const _plans = [
  _PlanInfo(
    name: 'Básico',
    description:
        'Para pequeños negocios que quieren comenzar a organizar sus ventas y operaciones.',
    total: 'RD\$3,000',
    monthlyEquivalent: 'RD\$1,000',
    features: ['100 productos', '2 usuarios', '1 almacén', '1 caja / terminal'],
  ),
  _PlanInfo(
    name: 'Negocio',
    description:
        'Para negocios en crecimiento que necesitan más capacidad y control.',
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
    description: 'Para negocios con mayor inventario, equipo y operación.',
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
          const SizedBox(height: 8),
          Text(
            plan.description,
            style: const TextStyle(
              color: Color(0xFF60748C),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 8),
          const _DisclosureText('Contratación mínima de 3 meses.'),
          const SizedBox(height: 6),
          const _DisclosureText(
            'Pago anticipado mediante transferencia bancaria.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => LandingScreen._openPlanWhatsApp(context, plan),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: Text('Elegir ${plan.name} por WhatsApp'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: highlighted ? _primary : _primaryDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'La instalación y configuración remota se realizan después de confirmar el pago de tu licencia.',
            style: TextStyle(
              color: Color(0xFF43566D),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclosureText extends StatelessWidget {
  const _DisclosureText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _ink,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CommonBenefits extends StatelessWidget {
  const _CommonBenefits();

  @override
  Widget build(BuildContext context) {
    const benefits = [
      'Ventas / facturación',
      'Inventario',
      'Clientes',
      'Cotizaciones',
      'Créditos',
      'Caja y turnos',
      'Reportes',
      'Código de barras',
      'Impresión térmica',
      'Windows',
      'Android',
      'iPhone',
      'Web/PWA',
      'Instalación remota',
      'Configuración inicial remota',
      'Soporte remoto vía WhatsApp',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Beneficios incluidos en los planes',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final benefit in benefits)
                _MiniPill(icon: Icons.check_rounded, label: benefit),
            ],
          ),
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
