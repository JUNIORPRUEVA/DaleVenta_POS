import 'package:daleventa_pos/features/auth/presentation/landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('landing optimized image assets are bundled', () async {
    const assetPaths = [
      'assets/image/landing-pos-cloud.webp',
      'assets/image/landing-mobile-sale.webp',
      'assets/image/landing-mobile-drawer.webp',
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
    expect(find.text('Ver planes y precios'), findsOneWidget);
    expect(find.text('Básico'), findsOneWidget);
    expect(find.text('Negocio'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('RD\$3,000'), findsOneWidget);
    expect(find.text('RD\$4,500'), findsOneWidget);
    expect(find.text('RD\$7,500'), findsOneWidget);
    expect(find.text('MÁS ELEGIDO'), findsOneWidget);
    expect(
      find.text('Pago anticipado mediante transferencia bancaria.'),
      findsNWidgets(3),
    );
    expect(find.text('Instalar PWA'), findsNothing);
    expect(find.text('Crear mi cuenta'), findsNothing);
    expect(find.text('Ahorra RD\$ 2,000 anual'), findsNothing);
    expect(find.text('WhatsApp: 829-531-9442'), findsOneWidget);
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
      expect(find.text('RD\$3,000'), findsOneWidget);
      expect(find.text('RD\$4,500'), findsOneWidget);
      expect(find.text('RD\$7,500'), findsOneWidget);

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
