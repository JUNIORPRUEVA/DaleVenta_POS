import 'dart:io';

import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
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

class _GuardedCatalogRepository extends CatalogRepository {
  _GuardedCatalogRepository() : super(Dio());

  int fetchProductsCalls = 0;
  int createProductCalls = 0;

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    fetchProductsCalls += 1;
    throw StateError('Onboarding must not download the full catalog');
  }

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return const <ProductModel>[];
  }

  @override
  Future<ProductModel> createProduct({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    String? itemType,
    bool? trackInventory,
    bool skipLoader = false,
  }) async {
    createProductCalls += 1;
    return ProductModel(
      id: 'onboarding-product',
      nombre: nombre,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
    );
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

  testWidgets(
    'paso producto con 5000 productos usa conteo y no descarga catalogo',
    (tester) async {
      final repo = _FakeOnboardingRepository(
        _state(
          status: 'IN_PROGRESS',
          shouldShowWelcome: false,
          productCount: 5000,
          steps: const {
            'company': 'COMPLETED',
            'billing': 'COMPLETED',
            'product': 'PENDING',
            'ready': 'PENDING',
          },
        ),
      );
      final catalog = _GuardedCatalogRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingRepositoryProvider.overrideWithValue(repo),
            catalogRepositoryProvider.overrideWithValue(catalog),
          ],
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ya tienes productos'), findsOneWidget);
      expect(find.text('Tu primer producto'), findsNothing);
      expect(catalog.fetchProductsCalls, 0);
      expect(catalog.createProductCalls, 0);
    },
  );

  test('onboarding no usa fetchProducts ni loadAllProductPages', () {
    final source = File(
      'lib/features/onboarding/presentation/onboarding_screen.dart',
    ).readAsStringSync();
    final backendSource = File(
      '../api/src/onboarding/onboarding.service.ts',
    ).readAsStringSync();

    expect(source, isNot(contains('fetchProducts(')));
    expect(source, isNot(contains('loadAllProductPages')));
    expect(backendSource, contains('this.prisma.product.count'));
    expect(backendSource, isNot(contains('this.prisma.product.findMany')));
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
  int productCount = 0,
  Map<String, String> steps = const {
    'company': 'PENDING',
    'billing': 'PENDING',
    'product': 'PENDING',
    'ready': 'PENDING',
  },
}) {
  return OnboardingStateModel(
    required: status == 'WELCOME_PENDING' || status == 'IN_PROGRESS',
    shouldShowWelcome: shouldShowWelcome,
    status: status,
    tutorialStatus: 'PENDING',
    steps: steps,
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
    productCount: productCount,
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
