import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/onboarding/data/onboarding_repository.dart';
import 'package:daleventa_pos/features/onboarding/presentation/onboarding_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOnboardingRepository extends OnboardingRepository {
  _FakeOnboardingRepository(this.state) : super(Dio());

  OnboardingStateModel state;
  int startCalls = 0;

  @override
  Future<OnboardingStateModel> getState() async => state;

  @override
  Future<OnboardingStateModel> start() async {
    startCalls += 1;
    state = _state(status: 'IN_PROGRESS', shouldShowWelcome: false);
    return state;
  }
}

class _AuthenticatedAuthController extends AuthController {
  _AuthenticatedAuthController(super.ref, UserModel user) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: user,
      loading: false,
      restoringSession: false,
      hasSessionHint: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Welcome + Comenzar configuracion muestra Paso 1', (
    tester,
  ) async {
    final repo = _FakeOnboardingRepository(
      _state(status: 'WELCOME_PENDING', shouldShowWelcome: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu cuenta está lista'), findsOneWidget);

    await tester.tap(find.text('Comenzar configuración'));
    await tester.pumpAndSettle();

    expect(repo.startCalls, 1);
    expect(find.text('Datos de tu negocio'), findsOneWidget);
    expect(find.text('Tu cuenta está lista'), findsNothing);
  });

  testWidgets('IN_PROGRESS recargado abre el Paso 1 y no vuelve a Welcome', (
    tester,
  ) async {
    final repo = _FakeOnboardingRepository(
      _state(status: 'IN_PROGRESS', shouldShowWelcome: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Datos de tu negocio'), findsOneWidget);
    expect(find.text('Tu cuenta está lista'), findsNothing);
  });

  testWidgets('router mantiene /onboarding cuando requiresOnboarding=true', (
    tester,
  ) async {
    final user = _user(requiresOnboarding: true);
    final repo = _FakeOnboardingRepository(
      _state(status: 'IN_PROGRESS', shouldShowWelcome: false),
    );
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _AuthenticatedAuthController(ref, user),
          ),
          appBootstrapStatusProvider.overrideWith(
            (_) => AppBootstrapStatus.ready,
          ),
          businessRegistrationDisabledProvider.overrideWithValue(false),
          onboardingRepositoryProvider.overrideWithValue(repo),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(router.dispose);

    router.go(Routes.onboarding);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, Routes.onboarding);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Datos de tu negocio'), findsOneWidget);
  });
}

OnboardingStateModel _state({
  required String status,
  required bool shouldShowWelcome,
}) {
  return OnboardingStateModel(
    required: status == 'WELCOME_PENDING' || status == 'IN_PROGRESS',
    shouldShowWelcome: shouldShowWelcome,
    status: status,
    tutorialStatus: 'PENDING',
    steps: const {
      'company': 'PENDING',
      'billing': 'PENDING',
      'product': 'PENDING',
      'ready': 'PENDING',
    },
    company: const OnboardingCompanyModel(
      name: 'Demo',
      commercialName: 'Demo',
      rnc: '',
      phone: '',
      address: '',
      taxEnabled: false,
      pricesIncludeTax: false,
      ncfEnabled: false,
    ),
    productCount: 0,
    trialEndsAt: DateTime(2026, 10, 4),
  );
}

UserModel _user({required bool requiresOnboarding}) {
  return UserModel(
    id: 'user-a',
    email: 'admin@example.test',
    nombreCompleto: 'Admin',
    telefono: '',
    role: 'ADMIN',
    companyId: 'company-a',
    companyName: 'Company A',
    onboardingRequired: requiresOnboarding,
    onboardingStatus: requiresOnboarding ? 'IN_PROGRESS' : 'NOT_REQUIRED',
    requiresOnboarding: requiresOnboarding,
  );
}
