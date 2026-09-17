import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/features/auth/data/remembered_login_users_storage.dart';
import 'package:daleventa_pos/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Login controller that resolves the login without touching the network.
class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      loading: false,
      restoringSession: false,
      hasSessionHint: false,
    );
  }

  String? lastEmail;
  String? lastPassword;

  @override
  Future<bool> login(String email, String password) async {
    lastEmail = email;
    lastPassword = password;
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      loading: false,
      restoringSession: false,
      hasSessionHint: true,
    );
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<_FakeAuthController> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/:rest(.*)',
          builder: (_, __) => const Scaffold(body: Text('destino')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_FakeAuthController.new),
          businessRegistrationDisabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    return ProviderScope.containerOf(
          tester.element(find.byType(LoginScreen)),
          listen: false,
        ).read(authStateProvider.notifier)
        as _FakeAuthController;
  }

  Future<void> openSavedUsersMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();
  }

  const usersKey = RememberedLoginUsersStorage.usersKey;

  testWidgets(
    'en Windows el campo Usuario muestra el desplegable',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        usersKey: <String>['guardado@example.test'],
      });

      await pumpLogin(tester);

      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
      expect(find.text('Recordar usuario'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      await openSavedUsersMenu(tester);
      expect(find.text('guardado@example.test'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final entry in const <String, TargetPlatform>{
    'Android': TargetPlatform.android,
    'iOS': TargetPlatform.iOS,
  }.entries) {
    testWidgets(
      'en ${entry.key} el campo Usuario muestra el desplegable',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          usersKey: <String>['guardado@example.test'],
        });

        await pumpLogin(tester);

        expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
        expect(find.text('Recordar usuario'), findsNothing);
        expect(find.byType(Switch), findsNothing);

        await openSavedUsersMenu(tester);
        expect(find.text('guardado@example.test'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(entry.value),
    );
  }

  testWidgets(
    'seleccionar un usuario rellena Usuario y vacía Contraseña',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        usersKey: <String>['guardado@example.test'],
      });

      await pumpLogin(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'clave-anterior-123',
      );
      await tester.pump();
      await openSavedUsersMenu(tester);

      await tester.tap(find.text('guardado@example.test'));
      await tester.pumpAndSettle();

      final emailField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Usuario'),
      );
      final passwordField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Contraseña'),
      );
      expect(emailField.controller!.text, 'guardado@example.test');
      expect(passwordField.controller!.text, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'la X quita el usuario recordado de este dispositivo',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        usersKey: <String>['uno@example.test', 'dos@example.test'],
      });

      await pumpLogin(tester);
      await openSavedUsersMenu(tester);

      expect(find.text('uno@example.test'), findsOneWidget);
      expect(find.text('dos@example.test'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(usersKey), <String>['dos@example.test']);
      expect(find.text('uno@example.test'), findsNothing);
      expect(find.text('dos@example.test'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'el desplegable avisa cuando no hay usuarios guardados',
    (tester) async {
      await pumpLogin(tester);
      await openSavedUsersMenu(tester);

      expect(
        find.text('Aún no hay usuarios guardados en este dispositivo'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'un login exitoso guarda el usuario y nunca la contraseña',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        RememberedLoginUsersStorage.legacyRememberFlagKey: true,
        RememberedLoginUsersStorage.legacyRememberEmailKey: 'viejo@example.test',
        RememberedLoginUsersStorage.legacyRememberPasswordKey: 'heredada-123',
      });

      final auth = await pumpLogin(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuario'),
        'nuevo@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'SuperSecreta123',
      );
      await tester.pump();

      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(auth.lastEmail, 'nuevo@example.test');
      expect(auth.lastPassword, 'SuperSecreta123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(usersKey), <String>['nuevo@example.test']);
      expect(
        prefs.containsKey(RememberedLoginUsersStorage.legacyRememberPasswordKey),
        isFalse,
      );
      expect(
        prefs.containsKey(RememberedLoginUsersStorage.legacyRememberEmailKey),
        isFalse,
      );
      expect(
        prefs.containsKey(RememberedLoginUsersStorage.legacyRememberFlagKey),
        isFalse,
      );
      final storedValues = prefs
          .getKeys()
          .map((key) => prefs.get(key).toString())
          .toList();
      expect(
        storedValues.any((value) => value.contains('SuperSecreta123')),
        isFalse,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'el usuario ya escrito se marca como Actual y no se puede reseleccionar',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        usersKey: <String>['guardado@example.test'],
      });

      await pumpLogin(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuario'),
        'guardado@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'clave-anterior-123',
      );
      await tester.pump();
      await openSavedUsersMenu(tester);

      expect(find.text('Actual'), findsOneWidget);

      // Pulsar la fila actual no hace nada: no se borra la contraseña escrita.
      final currentRow = find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('guardado@example.test'),
      );
      expect(currentRow, findsOneWidget);
      await tester.tap(currentRow, warnIfMissed: false);
      await tester.pumpAndSettle();

      final passwordField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Contraseña'),
      );
      expect(passwordField.controller!.text, 'clave-anterior-123');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'la X sigue quitando el usuario aunque sea el actual',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        usersKey: <String>['guardado@example.test'],
      });

      await pumpLogin(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuario'),
        'guardado@example.test',
      );
      await tester.pump();
      await openSavedUsersMenu(tester);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(usersKey), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final entry in const <String, TargetPlatform>{
    'Android': TargetPlatform.android,
    'iOS': TargetPlatform.iOS,
  }.entries) {
    testWidgets(
      'en ${entry.key} un login exitoso también guarda el usuario (nunca la contraseña)',
      (tester) async {
        final auth = await pumpLogin(tester);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Usuario'),
          'nuevo@example.test',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña'),
          'SuperSecreta123',
        );
        await tester.pump();

        await tester.tap(find.text('Iniciar sesión'));
        await tester.pumpAndSettle();

        expect(auth.lastEmail, 'nuevo@example.test');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(usersKey), <String>['nuevo@example.test']);
        final storedValues = prefs
            .getKeys()
            .map((key) => prefs.get(key).toString())
            .toList();
        expect(
          storedValues.any((value) => value.contains('SuperSecreta123')),
          isFalse,
        );
      },
      variant: TargetPlatformVariant.only(entry.value),
    );
  }
}
