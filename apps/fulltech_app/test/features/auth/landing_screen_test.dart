import 'package:daleventa_pos/features/auth/presentation/landing_screen.dart';
import 'package:daleventa_pos/core/app_access/app_access_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      find.text('Vende y controla tu negocio desde cualquier dispositivo'),
      findsOneWidget,
    );
    expect(find.text('Crear cuenta y probar gratis'), findsWidgets);
    expect(find.text('Ya tengo cuenta'), findsWidgets);
    expect(find.text('Usa FullPOS donde quieras'), findsOneWidget);
    expect(find.text('Descargar para Windows'), findsOneWidget);
    expect(find.text('Descargar para Android'), findsOneWidget);
    expect(find.text('Descargar para iPhone'), findsOneWidget);
    expect(find.text('iPhone'), findsWidgets);
    expect(find.text('Crear cuenta'), findsWidgets);
    expect(find.text('Usar FullPOS en la Web'), findsOneWidget);
    expect(
      find.text(
        '¿Vas a usar FullPOS en Android o iPhone? Crea primero tu cuenta desde la Web o Windows y luego inicia sesión en la app con los mismos datos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Crea tu cuenta'), findsWidgets);
    expect(find.text('Prueba FullPOS por 7 días'), findsOneWidget);
    expect(find.text('Activa tu licencia'), findsOneWidget);
    expect(
      find.textContaining('activamos tu licencia después de confirmar el pago'),
      findsOneWidget,
    );
    expect(find.text('Activar por WhatsApp'), findsOneWidget);
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
    expect(find.byTooltip('Escríbenos por WhatsApp'), findsOneWidget);
    expect(find.text('Comenzar prueba'), findsNWidgets(3));
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

    await tester.tap(find.text('Crear cuenta y probar gratis').first);
    await tester.pumpAndSettle();
    expect(find.text('Register'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ya tengo cuenta').first);
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
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
