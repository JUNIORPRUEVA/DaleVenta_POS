import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/auth/presentation/login_screen.dart';
import 'package:daleventa_pos/features/auth/presentation/register_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnauthenticatedAuthController extends AuthController {
  _UnauthenticatedAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      loading: false,
    );
  }
}

class _FailingRegisterRepository extends AuthRepository {
  _FailingRegisterRepository() : super(dio: Dio(), storage: TokenStorage());

  bool registerCalled = false;

  @override
  Future<UserModel> registerBusiness(Map<String, dynamic> payload) async {
    registerCalled = true;
    throw StateError('registerBusiness should not be called on mobile');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(
    WidgetTester tester, {
    required bool registrationDisabled,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_UnauthenticatedAuthController.new),
          businessRegistrationDisabledProvider.overrideWithValue(
            registrationDisabled,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<GoRouter> pumpAppRouter(
    WidgetTester tester, {
    required bool registrationDisabled,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_UnauthenticatedAuthController.new),
          businessRegistrationDisabledProvider.overrideWithValue(
            registrationDisabled,
          ),
          appBootstrapStatusProvider.overrideWith(
            (_) => AppBootstrapStatus.unauthenticated,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: ThemeData(platform: platform),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(router.dispose);
    return router;
  }

  testWidgets('iOS login keeps access fields and hides business registration', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      registrationDisabled: true,
      platform: TargetPlatform.iOS,
    );

    expect(find.text('Bienvenido a FullPOS Cloud'), findsOneWidget);
    expect(find.text('Email corporativo'), findsOneWidget);
    expect(find.text('Contrasena'), findsOneWidget);
    expect(find.text('Iniciar sesion'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text('Crear mi negocio'), findsNothing);
    expect(find.text('Crear empresa'), findsNothing);
    expect(find.text('¿No tienes una cuenta?'), findsOneWidget);
    expect(
      find.text('Solicita acceso al administrador de tu empresa.'),
      findsOneWidget,
    );
    expect(
      find.text('FullPOS Cloud requiere una cuenta empresarial existente.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android login hides business registration and explains access', (
    tester,
  ) async {
    await pumpLogin(tester, registrationDisabled: true);

    expect(find.text('Iniciar sesion'), findsOneWidget);
    expect(find.text('Crear mi negocio'), findsNothing);
    expect(find.text('Crear empresa'), findsNothing);
    expect(find.text('¿No tienes una cuenta?'), findsOneWidget);
    expect(
      find.text('Solicita acceso al administrador de tu empresa.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows login keeps business registration entry point', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      registrationDisabled: false,
      platform: TargetPlatform.windows,
    );

    expect(find.text('Iniciar sesion'), findsOneWidget);
    expect(find.text('Crear mi negocio'), findsOneWidget);
    expect(find.text('¿No tienes una cuenta?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS register route redirects to login', (tester) async {
    final router = await pumpAppRouter(
      tester,
      registrationDisabled: true,
      platform: TargetPlatform.iOS,
    );

    router.go(Routes.register);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('Android register route redirects to login', (tester) async {
    final router = await pumpAppRouter(tester, registrationDisabled: true);

    router.go(Routes.register);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('Windows register route remains available', (tester) async {
    final router = await pumpAppRouter(
      tester,
      registrationDisabled: false,
      platform: TargetPlatform.windows,
    );

    router.go(Routes.register);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, Routes.register);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Crear empresa'), findsOneWidget);
  });

  test('mobile registerBusiness guard prevents repository call', () async {
    final repository = _FailingRegisterRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        businessRegistrationDisabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(authStateProvider.notifier).registerBusiness(const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.displayCode,
          'displayCode',
          'BUSINESS_REGISTRATION_DISABLED',
        ),
      ),
    );
    expect(repository.registerCalled, isFalse);
  });
}
