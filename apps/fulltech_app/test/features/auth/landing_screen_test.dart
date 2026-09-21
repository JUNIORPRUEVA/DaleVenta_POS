import 'package:daleventa_pos/features/auth/presentation/landing_screen.dart';
import 'package:daleventa_pos/core/analytics/marketing_analytics.dart';
import 'package:daleventa_pos/core/app_access/app_access_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(MarketingAnalytics.debugResetForTests);

  test('landing optimized image assets are bundled', () async {
    const assetPaths = [
      'assets/image/fullpos-windows-ios-android.webp',
      'assets/image/fullpos-ios-android.webp',
      'assets/image/logo-web.webp',
    ];

    for (final assetPath in assetPaths) {
      final bytes = await rootBundle.load(assetPath);

      expect(
        bytes.lengthInBytes,
        greaterThan(0),
        reason: '$assetPath must be present in the Flutter asset bundle.',
      );
    }
  });

  test('landing download links use centralized production sources', () {
    expect(
      AppAccessLinks.windowsReleaseUri.toString(),
      'https://github.com/JUNIORPRUEVA/DaleVenta_POS/releases/download/v1.0.4/FullPOS-Cloud-Setup-1.0.3-7.exe',
    );
    expect(
      AppAccessLinks.androidReleaseUri.toString(),
      'https://github.com/JUNIORPRUEVA/fullpos_cluouds/releases/latest/download/app-release.apk',
    );
    expect(
      AppAccessLinks.iosAppStoreUri.toString(),
      'https://apps.apple.com/do/app/fullpos-cloud/id6801349002',
    );
  });

  testWidgets('landing shows commercial plans and purchase rules', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Controla tus ventas, inventario y caja desde un solo lugar'),
      findsOneWidget,
    );
    expect(
      find.text(
        'FullPOS Cloud te ayuda a manejar ventas, inventario, clientes, créditos y reportes desde tu computadora o celular.',
      ),
      findsOneWidget,
    );
    expect(find.text(LandingScreen.primaryCtaLabel), findsWidgets);
    expect(find.text(LandingScreen.compactCtaLabel), findsWidgets);
    expect(find.text('Prueba FullPOS gratis por 7 días'), findsWidgets);
    expect(find.text('Crea tu cuenta en pocos minutos.'), findsOneWidget);
    expect(find.text('Ya tengo cuenta'), findsWidgets);
    expect(find.text('Usa FullPOS donde quieras'), findsOneWidget);
    expect(find.text('Descargar para Windows'), findsOneWidget);
    expect(find.text('Descargar para Android'), findsOneWidget);
    expect(find.text('Descargar para iPhone'), findsOneWidget);
    expect(find.text('iPhone'), findsWidgets);
    expect(find.text('Usar FullPOS en la Web'), findsOneWidget);
    expect(
      find.text(
        '¿Vas a usar FullPOS en Android o iPhone? Crea primero tu cuenta desde la Web o Windows y luego inicia sesión en la app con los mismos datos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Crea tu cuenta gratis'), findsOneWidget);
    expect(find.text('Configura tu negocio'), findsOneWidget);
    expect(find.text('Prueba FullPOS durante 7 días'), findsOneWidget);
    expect(
      find.text('Si te funciona, activa el plan que necesites'),
      findsOneWidget,
    );
    expect(
      find.textContaining('activamos tu licencia después de confirmar el pago'),
      findsOneWidget,
    );
    expect(find.text('Hablar por WhatsApp'), findsOneWidget);
    expect(find.text('Prueba de 7 días'), findsOneWidget);
    expect(find.text('Soporte por WhatsApp'), findsOneWidget);
    expect(find.text('Prueba gratis por 7 días'), findsWidgets);
    expect(find.textContaining('5 días'), findsNothing);
    expect(find.textContaining('5 dias'), findsNothing);
    expect(find.text('Planes'), findsWidgets);
    expect(find.text('Básico'), findsOneWidget);
    expect(find.text('Negocio'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('RD\$1,000 / mes'), findsOneWidget);
    expect(find.text('RD\$1,500 / mes'), findsOneWidget);
    expect(find.text('RD\$2,500 / mes'), findsOneWidget);
    expect(find.text('Facturación mínima de 3 meses'), findsNWidgets(3));
    expect(find.text('Total trimestral: RD\$3,000'), findsOneWidget);
    expect(find.text('Total trimestral: RD\$4,500'), findsOneWidget);
    expect(find.text('Total trimestral: RD\$7,500'), findsOneWidget);
    expect(find.text('Todo lo esencial para comenzar'), findsOneWidget);
    expect(find.text('Más espacio para crecer'), findsOneWidget);
    expect(find.text('Mayor capacidad para tu operación'), findsOneWidget);
    expect(find.text('MÁS ELEGIDO'), findsOneWidget);
    expect(find.textContaining('pago es anticipado'), findsOneWidget);
    expect(find.text('Crear mi cuenta'), findsNothing);
    expect(find.text('Ahorra RD\$ 2,000 anual'), findsNothing);
    expect(find.text('WhatsApp: 829-531-9442'), findsOneWidget);
    expect(find.byTooltip('Escríbenos por WhatsApp'), findsWidgets);
    expect(find.text('Activar este plan'), findsNWidgets(3));
    expect(find.textContaining('Instalación remota incluida'), findsNothing);
    expect(find.textContaining('instalación remota incluida'), findsNothing);
    expect(find.textContaining('configuración remota'), findsNothing);
    expect(find.textContaining('Configuración inicial remota'), findsNothing);
    expect(find.textContaining('te ayuda remotamente'), findsNothing);
  });

  testWidgets('landing account CTAs route to register and login', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(
      MarketingAnalytics.debugEventsForTests.where(
        (event) => event.name == 'ViewContent',
      ),
      hasLength(1),
    );

    await tester.tap(find.text(LandingScreen.primaryCtaLabel).first);
    await tester.pumpAndSettle();
    expect(find.text('Register'), findsOneWidget);
    expect(
      MarketingAnalytics.debugEventsForTests.where(
        (event) => event.name == 'ClickCreateAccount',
      ),
      hasLength(1),
    );
    expect(
      MarketingAnalytics.debugEventsForTests.last.parameters,
      containsPair('cta_name', 'Regístrate gratis ahora - hero'),
    );

    router.go('/');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ya tengo cuenta').first);
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('landing pricing CTA routes to register with its own cta_name', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);
    _setPhoneViewport(tester, const Size(1024, 900));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final pricingCta = find.text(LandingScreen.primaryCtaLabel).last;
    await tester.ensureVisible(pricingCta);
    await tester.pumpAndSettle();
    await tester.tap(pricingCta);
    await tester.pumpAndSettle();

    expect(find.text('Register'), findsOneWidget);
    expect(
      MarketingAnalytics.debugEventsForTests.last.parameters,
      containsPair('cta_name', 'Regístrate gratis ahora - planes'),
    );
  });

  testWidgets('landing renders without layout errors on responsive widths', (
    tester,
  ) async {
    final sizes = <Size>[
      const Size(320, 900),
      const Size(360, 900),
      const Size(375, 900),
      const Size(390, 900),
      const Size(412, 900),
      const Size(430, 900),
      const Size(768, 1024),
      const Size(820, 1024),
      const Size(1024, 900),
      const Size(1280, 900),
      const Size(1366, 900),
      const Size(1440, 900),
      const Size(1600, 950),
    ];

    for (final size in sizes) {
      final router = _landingRouter();
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(size);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Landing should not throw layout errors at ${size.width}px.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('landing supports larger text scaling without layout errors', (
    tester,
  ) async {
    final scales = <double>[1.0, 1.2, 1.4];

    for (final scale in scales) {
      final router = _landingRouter();
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 1100));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Landing should not throw layout errors at text scale $scale.',
      );
      expect(find.text('RD\$1,000 / mes'), findsOneWidget);
      expect(find.text('RD\$1,500 / mes'), findsOneWidget);
      expect(find.text('RD\$2,500 / mes'), findsOneWidget);
      expect(find.text('Total trimestral: RD\$3,000'), findsOneWidget);
      expect(find.text('Total trimestral: RD\$4,500'), findsOneWidget);
      expect(find.text('Total trimestral: RD\$7,500'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('hero CTA stays above the fold on phone viewports', (
    tester,
  ) async {
    const phones = <Size>[
      Size(360, 800),
      Size(375, 812),
      Size(390, 844),
      Size(412, 915),
      Size(430, 932),
    ];

    for (final size in phones) {
      final router = _landingRouter();
      addTearDown(router.dispose);
      _setPhoneViewport(tester, size);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'layout at $size');

      final title = tester.getRect(
        find.text('Controla tus ventas, inventario y caja desde un solo lugar'),
      );
      final heroCta = tester.getRect(
        find
            .ancestor(
              of: find.text(LandingScreen.primaryCtaLabel).first,
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(
        title.top,
        greaterThanOrEqualTo(0),
        reason: 'Headline must start inside the viewport at $size',
      );
      expect(
        heroCta.bottom,
        lessThanOrEqualTo(size.height),
        reason: 'Register CTA must be visible without scrolling at $size',
      );
      expect(heroCta.height, greaterThanOrEqualTo(44));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.reset);
  });

  testWidgets('phone header exposes logo, register CTA and menu', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);
    _setPhoneViewport(tester, const Size(360, 800));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final headerCta = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.compactCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(headerCta.top, lessThan(120));
    expect(headerCta.bottom, lessThanOrEqualTo(800));
    expect(headerCta.height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('Menu'), findsOneWidget);
    final menuButton = tester.getRect(find.byTooltip('Menu'));
    expect(menuButton.width, greaterThanOrEqualTo(42));
    expect(menuButton.right, greaterThanOrEqualTo(348));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sticky register CTA appears only after the hero CTA leaves', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);
    _setPhoneViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final sticky = find.byKey(LandingScreen.stickyCtaKey);
    final heroCta = find
        .ancestor(
          of: find.text(LandingScreen.primaryCtaLabel).first,
          matching: find.byType(FilledButton),
        )
        .first;
    expect(tester.getRect(heroCta).bottom, lessThanOrEqualTo(844));
    // Not mounted above the fold: the FAB is the only floating action there.
    expect(sticky, findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(heroCta).bottom,
      lessThanOrEqualTo(0),
      reason: 'The hero CTA must scroll out of view to trigger the sticky CTA.',
    );
    // Diagnostic order: the FAB disappears as soon as the sticky CTA shows.
    expect(find.byType(FloatingActionButton), findsNothing);

    expect(sticky, findsOneWidget);
    final barCta = find.descendant(
      of: sticky,
      matching: find.byType(FilledButton),
    );
    final stickyRect = tester.getRect(barCta);
    expect(stickyRect.top, greaterThan(600));
    expect(stickyRect.bottom, lessThanOrEqualTo(844));
    expect(stickyRect.height, greaterThanOrEqualTo(44));

    await tester.tap(barCta);
    await tester.pumpAndSettle();

    expect(find.text('Register'), findsOneWidget);
    expect(
      MarketingAnalytics.debugEventsForTests.last.parameters,
      containsPair('cta_name', 'Regístrate gratis - CTA fijo móvil'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sticky register CTA uses subtle attention animation', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);
    _setPhoneViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final sticky = find.byKey(LandingScreen.stickyCtaKey);
    expect(sticky, findsOneWidget);
    final stickyButton = find.descendant(
      of: sticky,
      matching: find.byType(FilledButton),
    );
    final resting = tester.getRect(stickyButton);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 300));
    final shaking = tester.getRect(stickyButton);
    expect((shaking.left - resting.left).abs(), greaterThan(0.5));

    await tester.pump(const Duration(milliseconds: 900));
    final recovered = tester.getRect(stickyButton);
    expect((recovered.left - resting.left).abs(), lessThan(0.5));
    expect((recovered.width - resting.width).abs(), lessThan(0.5));
    expect(tester.takeException(), isNull);

    addTearDown(tester.view.reset);
  });

  testWidgets('mobile registration note is shown only on phone widths', (
    tester,
  ) async {
    final router = _landingRouter();
    addTearDown(router.dispose);
    _setPhoneViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('¿Estás desde tu celular?'), findsOneWidget);
    expect(
      find.text(
        'Puedes crear tu cuenta ahora desde este navegador, sin instalar nada.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final wideRouter = _landingRouter();
    addTearDown(wideRouter.dispose);
    _setPhoneViewport(tester, const Size(1024, 900));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: wideRouter)),
    );
    await tester.pumpAndSettle();

    expect(find.text('¿Estás desde tu celular?'), findsNothing);
    expect(find.byKey(LandingScreen.stickyCtaKey), findsNothing);

    addTearDown(tester.view.reset);
  });

  testWidgets('CTA attention animation rests and honours reduced motion', (
    tester,
  ) async {
    Future<void> pumpLanding({required bool reduceMotion}) async {
      final router = _landingRouter();
      addTearDown(router.dispose);
      _setPhoneViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Motion allowed: the CTA shakes and then returns to rest.
    await pumpLanding(reduceMotion: false);
    final resting = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.primaryCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 300));
    final shaking = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.primaryCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(
      (shaking.left - resting.left).abs(),
      greaterThan(0.5),
      reason: 'The CTA should shift during the attention animation.',
    );

    await tester.pump(const Duration(milliseconds: 900));
    final recovered = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.primaryCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect((recovered.left - resting.left).abs(), lessThan(0.5));
    expect(
      (recovered.width - resting.width).abs(),
      lessThan(0.5),
      reason: 'The animation must not leave a layout shift behind.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // Reduced motion: no shake at all.
    await pumpLanding(reduceMotion: true);
    final reducedRest = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.primaryCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 300));
    final reducedAfter = tester.getRect(
      find
          .ancestor(
            of: find.text(LandingScreen.primaryCtaLabel).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect((reducedAfter.left - reducedRest.left).abs(), lessThan(0.5));
    expect((reducedAfter.width - reducedRest.width).abs(), lessThan(0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    addTearDown(tester.view.reset);
  });

  testWidgets('landing header switches at the 1180px breakpoint', (
    tester,
  ) async {
    final compactRouter = _landingRouter();
    addTearDown(compactRouter.dispose);
    _setPhoneViewport(tester, const Size(1179, 900));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: compactRouter)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);
    expect(find.text(LandingScreen.compactCtaLabel), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final desktopRouter = _landingRouter();
    addTearDown(desktopRouter.dispose);
    _setPhoneViewport(tester, const Size(1180, 900));

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: desktopRouter)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Menu'), findsNothing);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    addTearDown(tester.view.reset);
  });
}

/// Sets a real phone viewport (setSurfaceSize alone does not resize the view).
void _setPhoneViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
}

GoRouter _landingRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('Login')),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const Scaffold(body: Text('Register')),
      ),
    ],
  );
}
