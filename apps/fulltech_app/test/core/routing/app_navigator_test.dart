import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daleventa_pos/core/routing/app_navigator.dart';
import 'package:daleventa_pos/core/routing/routes.dart';

void main() {
  tearDown(AppNavigator.resetBackHistoryForTesting);

  test('records previous shell location for drawer-style navigation', () {
    AppNavigator.recordShellLocation(Routes.cotizaciones);
    AppNavigator.recordShellLocation(Routes.catalogo);

    expect(AppNavigator.debugCurrentShellLocation, Routes.catalogo);
    expect(AppNavigator.debugPreviousShellLocation, Routes.cotizaciones);
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.catalogo),
      Routes.cotizaciones,
    );
  });

  test('does not create a duplicate fallback for the same shell route', () {
    AppNavigator.recordShellLocation(Routes.catalogo);
    AppNavigator.recordShellLocation(Routes.catalogo);

    expect(AppNavigator.debugCurrentShellLocation, Routes.catalogo);
    expect(AppNavigator.debugPreviousShellLocation, isNull);
    expect(AppNavigator.effectiveFallbackRouteFor(Routes.catalogo), isNull);
  });

  test('keeps explicit module fallback routes', () {
    expect(
      AppNavigator.fallbackRouteFor(Routes.cotizacionesHistorial),
      Routes.cotizaciones,
    );
    expect(
      AppNavigator.fallbackRouteFor('${Routes.clientes}/cliente-1/editar'),
      Routes.clientes,
    );
  });

  test('prefers the previous shell route over explicit child fallback', () {
    AppNavigator.recordShellLocation(Routes.cotizaciones);
    AppNavigator.recordShellLocation(Routes.catalogo);

    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.catalogoStock),
      Routes.cotizaciones,
    );
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.comprasLista),
      Routes.cotizaciones,
    );
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.cajaTurnosHistorial),
      Routes.cotizaciones,
    );
  });

  test('uses explicit module fallback when there is no previous shell', () {
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.catalogoStock),
      Routes.catalogo,
    );
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.comprasLista),
      Routes.compras,
    );
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.cajaTurnosHistorial),
      Routes.caja,
    );
    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.contabilidadFacturaFiscal),
      Routes.contabilidad,
    );
  });

  test('factura fiscal back goes to the real previous screen', () {
    AppNavigator.recordShellLocation(Routes.home);
    AppNavigator.recordShellLocation(Routes.contabilidadFacturaFiscal);

    expect(
      AppNavigator.effectiveFallbackRouteFor(Routes.contabilidadFacturaFiscal),
      Routes.home,
    );
  });

  test('user permissions back always returns to the users list', () {
    AppNavigator.recordShellLocation(Routes.users);
    AppNavigator.recordShellLocation('/users/user-1/permissions');

    expect(
      AppNavigator.effectiveFallbackRouteFor('/users/user-1/permissions'),
      Routes.users,
    );

    AppNavigator.recordShellLocation('/users/user-1');
    AppNavigator.recordShellLocation('/users/user-1/permissions');

    expect(
      AppNavigator.effectiveFallbackRouteFor('/users/user-1/permissions'),
      Routes.users,
    );
  });

  testWidgets('returns to the source shell route after opening inventory', (
    tester,
  ) async {
    late final GoRouter router;
    router = GoRouter(
      initialLocation: Routes.cotizaciones,
      routes: [
        GoRoute(
          path: Routes.cotizaciones,
          builder: (context, state) {
            AppNavigator.recordShellLocation(state.uri.toString());
            return Scaffold(
              body: ElevatedButton(
                key: const ValueKey('open-inventory'),
                onPressed: () => AppNavigator.go(context, Routes.catalogo),
                child: const Text('Facturación'),
              ),
            );
          },
        ),
        GoRoute(
          path: Routes.catalogo,
          builder: (context, state) {
            AppNavigator.recordShellLocation(state.uri.toString());
            return Scaffold(
              body: ElevatedButton(
                key: const ValueKey('back-from-inventory'),
                onPressed: () => AppNavigator.goBack(context),
                child: const Text('Inventario'),
              ),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('open-inventory')));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.catalogo,
    );
    expect(find.text('Inventario'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('back-from-inventory')));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.cotizaciones,
    );
    expect(find.text('Facturación'), findsOneWidget);
  });
}
