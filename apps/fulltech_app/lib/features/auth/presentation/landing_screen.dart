import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/marketing_analytics.dart';
import '../../../core/app_access/app_access_links.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import 'pwa_install_prompt.dart';

const _supportPhoneDisplay = '829-531-9442';
const _supportWhatsappIntl = '18295319442';

const _primary = Color(0xFF1957E6);
const _primaryDark = Color(0xFF123A75);
const _whatsapp = Color(0xFF0F8C7D);
const _ink = Color(0xFF0D1B2A);
const _muted = Color(0xFF5E7187);
const _line = Color(0xFFDCE8EF);
const _soft = Color(0xFFF3F7FA);
const _maxContentWidth = 1220.0;
const _phoneBreakpoint = 900.0;

// Reserved space at the end of the mobile scroll so the sticky registration CTA
// never covers the footer content.
const _stickyCtaReservedSpace = 96.0;

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  static final _topKey = GlobalKey();
  static final _featuresKey = GlobalKey();
  static final _demoKey = GlobalKey();
  static final _pricingKey = GlobalKey();
  static final _processKey = GlobalKey();
  static final _faqKey = GlobalKey();

  static const primaryCtaLabel = 'Regístrate gratis ahora';
  static const compactCtaLabel = 'Regístrate gratis';

  /// Phone-only sticky registration CTA (used by widget tests as well).
  static const stickyCtaKey = ValueKey('landing-sticky-cta');

  static Future<void> openGenericWhatsApp(BuildContext context) {
    return _openWhatsApp(
      context,
      'Hola, quiero información sobre FullPOS Cloud y sus planes.',
      ctaName: 'WhatsApp información',
    );
  }

  static Future<void> _openPlanWhatsApp(BuildContext context, _PlanInfo plan) {
    return _openWhatsApp(
      context,
      _planWhatsAppMessage(plan),
      ctaName: 'Activar plan ${plan.name} - WhatsApp',
    );
  }

  static Future<void> _openWhatsApp(
    BuildContext context,
    String text, {
    required String ctaName,
  }) {
    MarketingAnalytics.trackWhatsAppClicked(
      sourcePage: 'landing',
      ctaName: ctaName,
    );
    return safeOpenWhatsApp(
      context,
      Uri.https('wa.me', '/$_supportWhatsappIntl', {'text': text}),
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
    );
  }

  static void openRegistration(BuildContext context, String ctaName) {
    MarketingAnalytics.trackCreateAccountClick(
      sourcePage: 'landing',
      ctaName: ctaName,
    );
    context.go(Routes.register);
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
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _scrollController = ScrollController();
  final _heroCtaKey = GlobalKey();
  Timer? _pwaBannerWatch;
  double? _heroCtaDocumentBottom;
  bool _heroCtaOutOfView = false;
  bool _pwaBannerVisible = false;

  @override
  void initState() {
    super.initState();
    MarketingAnalytics.trackLandingViewed();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeroCta();
      _handleScroll();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBannerWatch();
  }

  @override
  void dispose() {
    _pwaBannerWatch?.cancel();
    _pwaBannerWatch = null;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// True only while the phone sticky registration CTA is on screen.
  bool get _stickyCtaVisible =>
      _heroCtaOutOfView && !_pwaBannerVisible && _isPhoneLayout(context);

  static bool _isPhoneLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _phoneBreakpoint;

  void _handleScroll() {
    if (!mounted) return;
    if (_heroCtaDocumentBottom == null) _measureHeroCta();
    final bottom = _heroCtaDocumentBottom;
    if (bottom == null || !_scrollController.hasClients) return;
    final outOfView = _scrollController.offset > bottom;
    if (outOfView == _heroCtaOutOfView) return;
    setState(() => _heroCtaOutOfView = outOfView);
    _syncBannerWatch();
  }

  /// The hero CTA bottom is measured once, in document space, while the scroll
  /// is still at the top: reading the render box on every scroll event is
  /// unreliable because the listener runs before the viewport re-applies the
  /// scroll transform.
  void _measureHeroCta() {
    final ctaContext = _heroCtaKey.currentContext;
    if (ctaContext == null) return;
    final box = ctaContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if (scrollOffset != 0) return;
    final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
    if (bottom > 0) _heroCtaDocumentBottom = bottom;
  }

  /// The PWA install banner is a DOM overlay outside the Flutter canvas. It is
  /// not shown automatically on the landing route, but it can appear when the
  /// visitor taps "Usar FullPOS en la Web"; while it is visible the sticky CTA
  /// stays hidden so only one floating action competes for the bottom edge.
  void _syncBannerWatch() {
    final needed = kIsWeb && _heroCtaOutOfView && _isPhoneLayout(context);
    if (!needed) {
      _pwaBannerWatch?.cancel();
      _pwaBannerWatch = null;
      return;
    }
    _pwaBannerWatch ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshPwaBannerVisibility(),
    );
  }

  void _refreshPwaBannerVisibility() {
    final visible = pwaInstallBannerVisible();
    if (visible == _pwaBannerVisible || !mounted) return;
    setState(() => _pwaBannerVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 1180;
    final isNarrowPhone = MediaQuery.sizeOf(context).width < 560;
    final isPhone = _isPhoneLayout(context);
    final baseTheme = Theme.of(context);

    return Scaffold(
      backgroundColor: _soft,
      endDrawer: _LandingDrawer(
        onNav: (key) => LandingScreen.scrollTo(context, key),
      ),
      floatingActionButton: _stickyCtaVisible
          ? null
          : const _FloatingWhatsAppButton(),
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
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _TopBar(
                        isMobile: isMobile,
                        onNav: (key) => LandingScreen.scrollTo(context, key),
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
                              key: LandingScreen._topKey,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _HeroSection(
                                  heroCtaKey: _heroCtaKey,
                                  animateCta: !_heroCtaOutOfView,
                                ),
                                if (isPhone) ...[
                                  const SizedBox(height: 18),
                                  const _MobileSignupNote(),
                                ],
                                const SizedBox(height: 28),
                                _Anchor(
                                  key: LandingScreen._featuresKey,
                                  child: const _BenefitsSection(),
                                ),
                                const SizedBox(height: 34),
                                _Anchor(
                                  key: LandingScreen._demoKey,
                                  child: const _DemoSection(),
                                ),
                                const SizedBox(height: 34),
                                _Anchor(
                                  key: LandingScreen._processKey,
                                  child: const _PurchaseProcessSection(),
                                ),
                                const SizedBox(height: 34),
                                const _TrustSection(),
                                const SizedBox(height: 34),
                                _Anchor(
                                  key: LandingScreen._pricingKey,
                                  child: const _PricingSection(),
                                ),
                                const SizedBox(height: 34),
                                _Anchor(
                                  key: LandingScreen._faqKey,
                                  child: const _FaqSection(),
                                ),
                                const SizedBox(height: 24),
                                const _Footer(),
                                if (isPhone)
                                  const SizedBox(
                                    height: _stickyCtaReservedSpace,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isPhone && _stickyCtaVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _StickyRegistrationCta(
                      key: LandingScreen.stickyCtaKey,
                      onRegister: () => LandingScreen.openRegistration(
                        context,
                        'Regístrate gratis - CTA fijo móvil',
                      ),
                      onWhatsApp: () => LandingScreen._openWhatsApp(
                        context,
                        'Hola, necesito asistencia con FullPOS Cloud.',
                        ctaName: 'WhatsApp CTA fijo móvil',
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

/// Phone-only reassurance block: the audit confirmed the account can be created
/// from a mobile browser, so the landing states it explicitly.
class _MobileSignupNote extends StatelessWidget {
  const _MobileSignupNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.smartphone_rounded,
                  color: _primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '¿Estás desde tu celular?',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Puedes crear tu cuenta ahora desde este navegador, sin instalar nada.',
            style: TextStyle(
              color: Color(0xFF31465C),
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Después usa la misma cuenta para acceder a FullPOS desde tus dispositivos compatibles.',
            style: TextStyle(
              color: Color(0xFF60748C),
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => LandingScreen.openRegistration(
                context,
                'Regístrate gratis ahora - bloque celular',
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(LandingScreen.primaryCtaLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone-only sticky registration CTA. Mounted only while the hero CTA is out
/// of view, so at most one floating action is ever on screen.
class _StickyRegistrationCta extends StatelessWidget {
  const _StickyRegistrationCta({
    super.key,
    required this.onRegister,
    required this.onWhatsApp,
  });

  final VoidCallback onRegister;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F0B2744),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onRegister,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(LandingScreen.compactCtaLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Escríbenos por WhatsApp',
            child: SizedBox(
              width: 48,
              height: 48,
              child: OutlinedButton(
                onPressed: onWhatsApp,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: _whatsapp,
                  side: const BorderSide(color: _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Icon(Icons.chat_rounded, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle periodic attention animation for the primary registration CTA.
///
/// - Only transforms (no layout shift, no reflow).
/// - Runs once every [_interval] for [_shakeDuration], then fully rests.
/// - Disabled when the platform requests reduced motion.
class _AttentionPulse extends StatefulWidget {
  const _AttentionPulse({required this.child, this.enabled = true});

  static const interval = Duration(seconds: 8);
  static const shakeDuration = Duration(milliseconds: 560);

  final Widget child;
  final bool enabled;

  @override
  State<_AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<_AttentionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _AttentionPulse.shakeDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!widget.enabled || reduceMotion) {
      _stop();
      return;
    }
    _timer ??= Timer.periodic(_AttentionPulse.interval, (_) => _play());
  }

  @override
  void didUpdateWidget(covariant _AttentionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.dispose();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_controller.isAnimating) _controller.stop();
    if (_controller.value != 0) _controller.value = 0;
  }

  void _play() {
    if (!mounted || _controller.isAnimating) return;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enableHover = !reduceMotion;
    return MouseRegion(
      onEnter: (_) {
        if (enableHover) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final progress = _controller.value;
          final wave = math.sin(progress * math.pi);
          final shake = math.sin(progress * math.pi * 6) * 4.2 * wave;
          final scale = 1 + (_hovered ? 0.018 : 0) + (0.02 * wave);
          return Transform.translate(
            offset: Offset(shake, 0),
            child: Transform.scale(scale: scale, child: child),
          );
        },
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
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 1180;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Inner decisions use the real layout width so the header never
        // overflows when the box is narrower than the media query reports.
        final layoutWidth = constraints.maxWidth;
        final isNarrowPhone = layoutWidth < 560;
        // Below 460px the wordmark is dropped so "Regístrate gratis" keeps its
        // full label inside the header.
        final showWordmark = !phone || layoutWidth >= 460;
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
                      : phone
                      ? 18
                      : 38,
                  vertical: phone ? 10 : 12,
                ),
                child: Row(
                  children: [
                    _BrandMark(showWordmark: showWordmark),
                    if (phone) ...[
                      const Spacer(),
                      Flexible(
                        child: FilledButton(
                          onPressed: () => LandingScreen.openRegistration(
                            context,
                            'Regístrate gratis - header móvil',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrowPhone ? 10 : 14,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: const Text(
                            LandingScreen.compactCtaLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) => IconButton.filledTonal(
                          tooltip: 'Menu',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            fixedSize: const Size(44, 44),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                          icon: const Icon(Icons.menu_rounded),
                        ),
                      ),
                    ] else ...[
                      const Spacer(),
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
                      _NavButton(
                        'FAQ',
                        onTap: () => onNav(LandingScreen._faqKey),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => context.go(Routes.login),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF43566D),
                          minimumSize: const Size(0, 44),
                        ),
                        child: const Text('Iniciar sesión'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => LandingScreen.openRegistration(
                          context,
                          'Regístrate gratis - header',
                        ),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 18,
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        label: const Text(LandingScreen.compactCtaLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.showWordmark = true});

  final bool showWordmark;

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
          child: Image.asset(
            'assets/image/logo-web.webp',
            fit: BoxFit.contain,
            semanticLabel: showWordmark ? null : 'FullPOS Cloud',
          ),
        ),
        if (showWordmark) ...[
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
            _DrawerAction(
              LandingScreen.compactCtaLabel,
              Icons.person_add_alt_1_rounded,
              () {
                Navigator.of(context).maybePop();
                LandingScreen.openRegistration(
                  context,
                  'Regístrate gratis - menú',
                );
              },
              emphasized: true,
            ),
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
  const _HeroSection({required this.heroCtaKey, required this.animateCta});

  final GlobalKey heroCtaKey;
  final bool animateCta;

  static const _title =
      'Controla tus ventas, inventario y caja desde un solo lugar';
  static const _subtitle =
      'FullPOS Cloud te ayuda a manejar ventas, inventario, clientes, créditos y reportes desde tu computadora o celular.';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final veryCompact = constraints.maxWidth < 380;
        final titleSize = veryCompact
            ? 27.0
            : compact
            ? 30.0
            : 50.0;
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
            const SizedBox(height: 14),
            Text(
              _title,
              style: TextStyle(
                color: _ink,
                fontSize: titleSize,
                height: 1.06,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            const Text(
              _subtitle,
              style: TextStyle(
                color: Color(0xFF31465C),
                fontSize: 15.5,
                height: 1.42,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 16 : 20),
            Align(
              alignment: Alignment.centerLeft,
              child: _AttentionPulse(
                enabled: animateCta,
                child: FilledButton.icon(
                  key: heroCtaKey,
                  onPressed: () => LandingScreen.openRegistration(
                    context,
                    'Regístrate gratis ahora - hero',
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                  label: const Text(LandingScreen.primaryCtaLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    textStyle: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Prueba FullPOS gratis por 7 días',
              style: TextStyle(
                color: _primaryDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Crea tu cuenta en pocos minutos.',
              style: TextStyle(
                color: Color(0xFF60748C),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.login),
              icon: const Icon(Icons.login_rounded, size: 19),
              label: const Text('Ya tengo cuenta'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
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
        'Vende más rápido',
        'Facturación POS con búsqueda de productos, cobro y ticket listo para entregar.',
      ),
      _BenefitInfo(
        Icons.inventory_2_rounded,
        'Conoce tu inventario en tiempo real',
        'Productos, existencias, almacenes y movimientos al día.',
      ),
      _BenefitInfo(
        Icons.account_balance_wallet_rounded,
        'Controla tu caja',
        'Turnos, ingresos, gastos y arqueo del día con más orden.',
      ),
      _BenefitInfo(
        Icons.storefront_rounded,
        'Administra clientes y créditos',
        'Historial de compras, saldos y cobros pendientes en un solo lugar.',
      ),
      _BenefitInfo(
        Icons.insights_rounded,
        'Visualiza reportes claros',
        'Ventas, utilidad y métodos de pago para decidir con datos.',
      ),
      _BenefitInfo(
        Icons.cloud_done_rounded,
        'Consulta tus ventas desde cualquier lugar',
        'Usa la misma cuenta en Windows, Android, iPhone o Web.',
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
              ? 3
              : constraints.maxWidth > 560
              ? 2
              : 1;
          // Cards hold title + copy, so the row height follows the text scale.
          final textScale = MediaQuery.textScalerOf(
            context,
          ).scale(1).clamp(1.0, 2.0);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: benefits.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 210 * textScale,
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
                  actionLabel: LandingScreen.compactCtaLabel,
                  onPressed: () => LandingScreen.openRegistration(
                    context,
                    'Regístrate gratis - web pwa',
                  ),
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
        'Crea tu cuenta gratis',
        'Regístrate en pocos minutos desde este navegador o desde FullPOS para Windows.',
      ),
      _StepInfo(
        'Configura tu negocio',
        'Carga tus productos, precios y datos del negocio para empezar a operar.',
      ),
      _StepInfo(
        'Prueba FullPOS durante 7 días',
        'Inicia sesión con la misma cuenta en tus dispositivos compatibles durante la prueba gratis.',
      ),
      _StepInfo(
        'Si te funciona, activa el plan que necesites',
        'Escríbenos por WhatsApp y activamos tu licencia después de confirmar el pago.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Cómo funciona',
      title: 'Empieza en pocos minutos',
      copy:
          'Crea tu cuenta una sola vez y usa los mismos datos para iniciar sesión en tus dispositivos.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final whatsappButton = OutlinedButton.icon(
            onPressed: () => LandingScreen._openWhatsApp(
              context,
              'Hola, quiero activar mi licencia de FullPOS Cloud.',
              ctaName: 'Activar por WhatsApp - cómo funciona',
            ),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Hablar por WhatsApp'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
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
          final columns = constraints.maxWidth >= 1040 ? 4 : 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 0,
                runSpacing: 14,
                children: [
                  for (var index = 0; index < steps.length; index++)
                    SizedBox(
                      width: constraints.maxWidth / columns,
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

/// Sober trust section. Only verifiable facts: legal name, real channels,
/// real platforms and the real 7-day trial.
class _TrustSection extends StatelessWidget {
  const _TrustSection();

  @override
  Widget build(BuildContext context) {
    const facts = [
      _TrustFact(
        Icons.verified_rounded,
        'FULLTECH SRL',
        'Producto desarrollado y operado por FULLTECH SRL.',
      ),
      _TrustFact(
        Icons.chat_rounded,
        'Soporte por WhatsApp',
        'Asistencia directa por el canal comercial $_supportPhoneDisplay.',
      ),
      _TrustFact(
        Icons.timer_rounded,
        'Prueba de 7 días',
        'Empieza gratis y decide con el sistema en uso.',
      ),
      _TrustFact(
        Icons.devices_rounded,
        'Windows, Android, iPhone y Web',
        'Acceso web/PWA y aplicaciones para los dispositivos soportados.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionShell(
          eyebrow: 'Confianza',
          title:
              'Un sistema desarrollado para negocios que necesitan control y simplicidad',
          copy:
              'Información verificable sobre quién desarrolla FullPOS Cloud y qué incluye la prueba.',
          child: SizedBox.shrink(),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 900 ? 2 : 1;
            final gap = 12.0;
            final cardWidth =
                (constraints.maxWidth - (gap * (columns - 1))) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final fact in facts)
                  SizedBox(width: cardWidth, child: _TrustFactCard(fact)),
              ],
            );
          },
        ),
        // TESTIMONIALS_PENDING_REAL_DATA
        // The slot is prepared but nothing is published until the owner supplies
        // real, verifiable testimonials. No invented customers, ratings or
        // statistics are rendered.
        if (_testimonials.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TestimonialsSection(),
        ],
      ],
    );
  }
}

class _TrustFact {
  const _TrustFact(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}

class _TrustFactCard extends StatelessWidget {
  const _TrustFactCard(this.fact);

  final _TrustFact fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(fact.icon, color: _primary, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fact.copy,
                  style: const TextStyle(
                    color: Color(0xFF60748C),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

/// TESTIMONIALS_PENDING_REAL_DATA
/// Renders only when real testimonials are provided by the business owner.
const List<_TestimonialInfo> _testimonials = <_TestimonialInfo>[];

class _TestimonialInfo {
  const _TestimonialInfo({
    required this.quote,
    required this.author,
    required this.business,
  });

  final String quote;
  final String author;
  final String business;
}

class _TestimonialsSection extends StatelessWidget {
  const _TestimonialsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final testimonial in _testimonials) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  testimonial.quote,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${testimonial.author} · ${testimonial.business}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PricingSection extends StatelessWidget {
  const _PricingSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'Planes y precios',
      title: 'Elige el plan que mejor se adapte a tu negocio',
      copy:
          'Primero crea tu cuenta y prueba FullPOS gratis 7 días. Cuando decidas continuar, activas el plan que necesites: la activación mínima es por 3 meses.',
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => LandingScreen.openRegistration(
                context,
                'Regístrate gratis ahora - planes',
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
              label: const Text(LandingScreen.primaryCtaLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Prueba FullPOS gratis por 7 días. No necesitas elegir un plan para empezar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF60748C),
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
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
        '¿Puedo probar FullPOS antes de pagar?',
        'Sí. Crea tu cuenta gratis y usa FullPOS Cloud durante 7 días antes de activar cualquier plan.',
      ),
      (
        '¿Cuánto dura la prueba?',
        'La prueba gratis dura 7 días desde que creas tu cuenta.',
      ),
      (
        '¿Necesito instalar algo para probarlo?',
        'No. Puedes probarlo desde el navegador (Web/PWA). También puedes descargar FullPOS para Windows, Android o iPhone.',
      ),
      (
        '¿Puedo utilizarlo desde mi celular?',
        'Sí. Puedes crear tu cuenta desde el navegador de tu celular y usar FullPOS en la Web/PWA. En Android o iPhone inicia sesión en la app con la misma cuenta.',
      ),
      (
        '¿Funciona en Windows?',
        'Sí. FullPOS Cloud tiene instalador para Windows, además de acceso Web/PWA, Android y iPhone.',
      ),
      (
        '¿Qué ocurre después de los 7 días?',
        'Al terminar la prueba, para seguir usando FullPOS Cloud hay que activar un plan. Escríbenos por WhatsApp y activamos tu licencia después de confirmar el pago.',
      ),
      (
        '¿Puedo usar la misma cuenta en varios dispositivos?',
        'Sí. Crea tu cuenta una sola vez y usa los mismos datos para iniciar sesión en tus dispositivos.',
      ),
      (
        '¿Cómo puedo pagar?',
        'Actualmente aceptamos transferencia bancaria. La contratación mínima es de 3 meses.',
      ),
      (
        '¿Cómo recibo soporte?',
        'El soporte es por WhatsApp ($_supportPhoneDisplay), tanto durante la prueba como para activar tu licencia.',
      ),
    ];

    return _SectionShell(
      eyebrow: 'Preguntas frecuentes',
      title: 'Respuestas rápidas para empezar',
      copy:
          'Lo esencial sobre prueba, dispositivos, pago, activación y soporte.',
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

/// Secondary contact channel. Hidden while the phone sticky registration CTA is
/// visible so two floating actions never compete at the bottom of the screen.
class _FloatingWhatsAppButton extends StatelessWidget {
  const _FloatingWhatsAppButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FloatingActionButton.small(
        heroTag: 'landing-whatsapp',
        tooltip: 'Escríbenos por WhatsApp',
        backgroundColor: _whatsapp,
        foregroundColor: Colors.white,
        onPressed: () => LandingScreen._openWhatsApp(
          context,
          'Hola, necesito asistencia con FullPOS Cloud.',
          ctaName: 'WhatsApp flotante',
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
        minimumSize: const Size(0, 44),
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
    required this.subtitle,
    required this.valueMessage,
    required this.total,
    required this.monthlyEquivalent,
    required this.features,
    this.highlight = false,
  });

  final String name;
  final String subtitle;
  final String valueMessage;
  final String total;
  final String monthlyEquivalent;
  final List<String> features;
  final bool highlight;
}

const _plans = [
  _PlanInfo(
    name: 'Básico',
    subtitle: 'Para comenzar',
    valueMessage: 'Todo lo esencial para comenzar',
    total: 'RD\$3,000',
    monthlyEquivalent: 'RD\$1,000',
    features: ['100 productos', '2 usuarios', '1 almacén', '1 caja / terminal'],
  ),
  _PlanInfo(
    name: 'Negocio',
    subtitle: 'Más elegido',
    valueMessage: 'Más espacio para crecer',
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
    subtitle: 'Para negocios en crecimiento',
    valueMessage: 'Mayor capacidad para tu operación',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.subtitle,
                      style: const TextStyle(
                        color: _primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
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
            '${plan.monthlyEquivalent} / mes',
            style: const TextStyle(
              color: _ink,
              fontSize: 36,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Total trimestral: ${plan.total}',
            style: const TextStyle(
              color: _primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Facturación mínima de 3 meses',
            style: TextStyle(
              color: Color(0xFF60748C),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            plan.valueMessage,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final feature in plan.features) ...[
            _InlineCheck(text: feature),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => LandingScreen._openPlanWhatsApp(context, plan),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Activar este plan'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: highlighted ? _primary : _primaryDark,
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
