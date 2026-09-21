import 'package:daleventa_pos/core/analytics/marketing_analytics.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/business_registration_policy.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/auth/presentation/register_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RegisterAnalyticsRepository extends AuthRepository {
  _RegisterAnalyticsRepository({
    required this.shouldFail,
    this.beforeSuccessReturn,
  }) : super(dio: Dio(), storage: TokenStorage());

  final bool shouldFail;
  final VoidCallback? beforeSuccessReturn;
  int registerCalls = 0;
  Map<String, dynamic>? lastPayload;

  @override
  Future<UserModel> registerBusiness(Map<String, dynamic> payload) async {
    registerCalls += 1;
    lastPayload = Map<String, dynamic>.from(payload);

    if (shouldFail) {
      throw const ApiException.detailed(
        message: 'No se pudo crear el negocio en el mock.',
        type: ApiErrorType.server,
        displayCode: 'MOCK_REGISTER_FAILED',
        retryable: false,
      );
    }

    beforeSuccessReturn?.call();
    return UserModel(
      id: 'mock-user-id',
      email: 'owner@example.test',
      nombreCompleto: 'Persona QA',
      telefono: '8090000000',
      role: 'ADMIN',
      companyId: 'mock-company-id',
      companyName: 'Negocio Demo QA',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MarketingAnalytics.debugResetForTests();
  });

  Future<void> pumpRegisterScreen(
    WidgetTester tester, {
    required _RegisterAnalyticsRepository repository,
    Size size = const Size(1200, 1000),
  }) async {
    final router = GoRouter(
      initialLocation: Routes.register,
      routes: [
        GoRoute(
          path: Routes.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: Routes.landing,
          builder: (context, state) => const Scaffold(body: Text('Landing')),
        ),
        GoRoute(
          path: Routes.cotizaciones,
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: Routes.login,
          builder: (context, state) => const Scaffold(body: Text('Login')),
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          businessRegistrationDisabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  Future<void> completeValidRegistrationForm(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del negocio'),
      'Negocio Demo QA',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Persona responsable'),
      'Persona QA',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usuario'),
      'qa@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'WhatsApp'),
      '8090000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'Password123',
    );
    await tester.ensureVisible(find.text('Crear mi negocio'));
  }

  Future<void> submitRegistrationForm(WidgetTester tester) async {
    final submitButton = find.byType(FilledButton);
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
  }

  int eventCount(String name) => MarketingAnalytics.debugEventsForTests
      .where((event) => event.name == name)
      .length;

  testWidgets(
    'successful registration tracks completion and trial exactly once after repository success',
    (tester) async {
      late List<String> eventsBeforeSuccessReturn;
      final repository = _RegisterAnalyticsRepository(
        shouldFail: false,
        beforeSuccessReturn: () {
          eventsBeforeSuccessReturn = MarketingAnalytics.debugEventsForTests
              .map((event) => event.name)
              .toList();
        },
      );

      await pumpRegisterScreen(tester, repository: repository);
      await completeValidRegistrationForm(tester);
      await submitRegistrationForm(tester);

      final eventNames = MarketingAnalytics.debugEventsForTests
          .map((event) => event.name)
          .toList();
      final successEvents = MarketingAnalytics.debugEventsForTests.where(
        (event) =>
            event.name == 'CompleteRegistration' ||
            event.name == 'TrialStarted',
      );

      expect(repository.registerCalls, 1);
      expect(eventsBeforeSuccessReturn, ['RegistrationStarted']);
      expect(eventNames, [
        'RegistrationStarted',
        'CompleteRegistration',
        'TrialStarted',
      ]);
      expect(eventCount('RegistrationStarted'), 1);
      expect(eventCount('CompleteRegistration'), 1);
      expect(eventCount('TrialStarted'), 1);

      for (final event in successEvents) {
        expect(event.parameters, {'source_page': 'register'});
        expect(event.parameters.keys, isNot(contains('email')));
        expect(event.parameters.keys, isNot(contains('phone')));
        expect(event.parameters.keys, isNot(contains('telefono')));
        expect(event.parameters.keys, isNot(contains('name')));
        expect(event.parameters.keys, isNot(contains('nombre')));
        expect(event.parameters.keys, isNot(contains('password')));
        expect(event.parameters.keys, isNot(contains('rnc')));
        expect(event.parameters.keys, isNot(contains('company')));
        expect(event.parameters.values, everyElement('register'));
      }
    },
  );

  testWidgets('failed registration does not track completion or trial events', (
    tester,
  ) async {
    final repository = _RegisterAnalyticsRepository(shouldFail: true);

    await pumpRegisterScreen(tester, repository: repository);
    await completeValidRegistrationForm(tester);
    await submitRegistrationForm(tester);

    expect(repository.registerCalls, 1);
    expect(eventCount('RegistrationStarted'), 1);
    expect(eventCount('CompleteRegistration'), 0);
    expect(eventCount('TrialStarted'), 0);
  });

  testWidgets(
    'mobile registration layout exposes optimized fields and actions',
    (tester) async {
      final repository = _RegisterAnalyticsRepository(shouldFail: false);

      await pumpRegisterScreen(
        tester,
        repository: repository,
        size: const Size(390, 844),
      );

      expect(find.text('Crear mi empresa'), findsOneWidget);
      expect(find.text('Tu negocio'), findsOneWidget);
      expect(find.text('Datos de acceso'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Usuario'), findsOneWidget);
      expect(
        find.text('Debe ser un correo electrónico válido.'),
        findsOneWidget,
      );
      expect(
        find.text('Mínimo 8 caracteres. Ejemplo: MiNegocio26'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Hablar por WhatsApp'));
      expect(find.text('Crear mi negocio'), findsOneWidget);
      expect(find.text('Hablar por WhatsApp'), findsOneWidget);
      expect(
        find.text('¿Ya tienes una cuenta? Iniciar sesión'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'close with draft offers WhatsApp help and can leave to landing',
    (tester) async {
      final repository = _RegisterAnalyticsRepository(shouldFail: false);

      await pumpRegisterScreen(tester, repository: repository);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del negocio'),
        'Negocio Demo QA',
      );
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.text('¿Quieres que te contactemos?'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Tu WhatsApp'), findsOneWidget);

      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(find.text('Landing'), findsOneWidget);
    },
  );
}
