import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/auth/presentation/forgot_password_screen.dart';
import 'package:daleventa_pos/features/auth/presentation/login_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(dio: Dio(), storage: TokenStorage());

  String? requestedEmail;
  String? resetToken;
  String? resetPasswordValue;

  @override
  Future<String> requestPasswordReset(String email) async {
    requestedEmail = email;
    return 'Si tu cuenta permite recuperación por correo, recibirás las instrucciones correspondientes. De lo contrario, contacta al administrador de tu empresa.';
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    resetToken = token;
    resetPasswordValue = password;
  }
}

class _AuthenticatedAuthController extends AuthController {
  _AuthenticatedAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'owner-id',
        email: 'owner@test.local',
        nombreCompleto: 'Owner',
        telefono: '',
        role: 'ADMIN',
        companyId: 'company-id',
      ),
      loading: false,
      restoringSession: false,
      hasSessionHint: true,
    );
  }

  @override
  Future<void> logout() async {
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      user: null,
      loading: false,
      restoringSession: false,
      hasSessionHint: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('forgot-password muestra confirmación limpia', (tester) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'owner@test.local',
    );
    await tester.tap(find.text('Enviar instrucciones'));
    await tester.pumpAndSettle();

    expect(repository.requestedEmail, 'owner@test.local');
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(
      find.text(
        'Si tu cuenta permite recuperación, te enviamos un enlace para crear una nueva contraseña.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Si tu cuenta permite recuperación por correo'),
      findsNothing,
    );
  });

  testWidgets('abrir reset link muestra formulario y no consume token', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: ResetPasswordScreen(token: 'reset-token'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nueva contraseña'), findsWidgets);
    expect(find.text('Confirmar contraseña'), findsOneWidget);
    expect(find.text('Guardar nueva contraseña'), findsOneWidget);
    expect(repository.resetToken, isNull);
    expect(repository.resetPasswordValue, isNull);
  });

  testWidgets('contraseña solo cambia al enviar formulario', (tester) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: ResetPasswordScreen(token: 'reset-token'),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'new-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'new-password-123',
    );
    expect(repository.resetPasswordValue, isNull);

    await tester.tap(find.text('Guardar nueva contraseña'));
    await tester.pumpAndSettle();

    expect(repository.resetToken, 'reset-token');
    expect(repository.resetPasswordValue, 'new-password-123');
    expect(find.text('Contraseña actualizada correctamente'), findsOneWidget);
    expect(find.text('Volver a iniciar sesión'), findsOneWidget);
  });

  testWidgets('abrir reset link autenticado NO redirige al home', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith(_AuthenticatedAuthController.new),
          appBootstrapStatusProvider.overrideWith(
            (_) => AppBootstrapStatus.authenticatedLoadingCompany,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    addTearDown(router.dispose);

    router.go('${Routes.resetPassword}?token=reset-token');
    await tester.pump();
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.path,
      Routes.resetPassword,
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['token'],
      'reset-token',
    );
    expect(find.text('Nueva contraseña'), findsWidgets);
    expect(find.text('Guardar nueva contraseña'), findsOneWidget);
    expect(repository.resetToken, isNull);
  });

  testWidgets(
    'reset link aparece inmediato mientras bootstrap restaura sesión',
    (tester) async {
      final repository = _FakeAuthRepository();
      late GoRouter router;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            authStateProvider.overrideWith(_AuthenticatedAuthController.new),
            appBootstrapStatusProvider.overrideWith(
              (_) => AppBootstrapStatus.authenticatedLoadingCompany,
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      addTearDown(router.dispose);

      router.go('${Routes.resetPassword}?token=reset-token');
      await tester.pump();
      await tester.pump();

      expect(
        router.routeInformationProvider.value.uri.path,
        Routes.resetPassword,
      );
      expect(find.text('Nueva contraseña'), findsWidgets);
      expect(find.text('Guardar nueva contraseña'), findsOneWidget);
      expect(repository.resetToken, isNull);
    },
  );

  testWidgets('volver al login funciona tras actualizar contraseña', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appBootstrapStatusProvider.overrideWith(
            (_) => AppBootstrapStatus.unauthenticated,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    addTearDown(router.dispose);

    router.go('${Routes.resetPassword}?token=reset-token');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'new-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'new-password-123',
    );
    await tester.tap(find.text('Guardar nueva contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver a iniciar sesión'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, Routes.login);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('reset exitoso limpia sesión local existente', (tester) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith(_AuthenticatedAuthController.new),
          appBootstrapStatusProvider.overrideWith(
            (_) => AppBootstrapStatus.authenticatedLoadingCompany,
          ),
        ],
        child: const MaterialApp(
          home: ResetPasswordScreen(token: 'reset-token'),
        ),
      ),
    );

    final context = tester.element(find.byType(ResetPasswordScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(authStateProvider).isAuthenticated, isTrue);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'new-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'new-password-123',
    );
    await tester.tap(find.text('Guardar nueva contraseña'));
    await tester.pump();
    await tester.pump();

    expect(repository.resetPasswordValue, 'new-password-123');
    expect(container.read(authStateProvider).isAuthenticated, isFalse);
    expect(find.text('Volver a iniciar sesión'), findsOneWidget);
  });
}
