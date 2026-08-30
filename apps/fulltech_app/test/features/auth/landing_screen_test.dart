import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/features/auth/presentation/landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('landing shows updated offer and platform message', (
    tester,
  ) async {
    final router = GoRouter(
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
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessRegistrationDisabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RD\$ 1,000'), findsOneWidget);
    expect(find.text('RD\$ 1,000 mensual'), findsOneWidget);
    expect(find.text('Ahorra RD\$ 2,000 anual'), findsOneWidget);
    expect(find.text('Sistema POS completo'), findsOneWidget);
    expect(find.text('Un sistema potente multi plataforma'), findsOneWidget);
    expect(find.text('Web, PWA, Android, iPhone y Windows'), findsOneWidget);
    expect(find.text('829-531-9442'), findsOneWidget);
  });
}
