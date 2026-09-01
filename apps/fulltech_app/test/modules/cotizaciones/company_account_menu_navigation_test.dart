import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MenuAuthController extends AuthController {
  _MenuAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'u-menu',
        email: 'menu@example.com',
        nombreCompleto: 'Usuario Menu',
        telefono: '',
        role: 'ADMIN',
        companyId: 'company-menu',
      ),
    );
  }
}

Future<GoRouter> _pumpCompanyMenu(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/menu-test',
    routes: [
      GoRoute(
        path: '/menu-test',
        builder: (_, __) => Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: buildCompanyAccountMenuForTesting(),
          ),
        ),
      ),
      GoRoute(
        path: Routes.configuracionEmpresa,
        builder: (_, __) => const Scaffold(body: Text('Datos de empresa')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_MenuAuthController.new),
        companySettingsProvider.overrideWith(
          (_) async =>
              CompanySettings.empty().copyWith(companyName: 'FullPOS Test'),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _companyMenuItem(String label) {
  return find
      .descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
      )
      .last;
}

void main() {
  testWidgets(
    'Cuenta y empresa > Empresa navega sin usar ref tras cerrar menu',
    (tester) async {
      final router = await _pumpCompanyMenu(tester);

      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Empresa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        Routes.configuracionEmpresa,
      );
      expect(find.text('Datos de empresa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cuenta y empresa no muestra acceso directo a Almacenes', (
    tester,
  ) async {
    await _pumpCompanyMenu(tester);

    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pumpAndSettle();

    expect(find.text('Almacenes'), findsNothing);
  });

  testWidgets(
    'Cuenta y empresa > Empresa soporta desmontaje rapido sin StateError',
    (tester) async {
      await _pumpCompanyMenu(tester);

      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Empresa'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
