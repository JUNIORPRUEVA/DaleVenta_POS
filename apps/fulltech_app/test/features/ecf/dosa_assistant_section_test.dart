import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_section.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// El registro de la intención es una escritura en el backend. Estas pruebas
/// fijan la garantía de producto: **abrir el expediente no escribe nada**, y el
/// asistente solo se abre después de que el administrador lo pida.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DosaAssistantConfig enabledConfig() =>
      const DosaAssistantConfig(enabled: true);

  Future<void> pumpSection(
    WidgetTester tester, {
    required _IntentApi api,
    String role = 'ADMIN',
    String rnc = '133306001',
  }) async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: _user(role: role),
              hasSessionHint: true,
            ),
          ),
        ),
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty().copyWith(
            companyName: 'FULLTECH, SRL',
            rnc: rnc,
          ),
        ),
        dosaCertificationIntentApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DosaAssistantSection(config: enabledConfig()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('abrir el expediente NO registra la intención', (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api);

    // Solo se consultó el estado (lectura). Ninguna escritura.
    expect(api.stateCalls, 1);
    expect(api.registerCalls, isEmpty);
    // Y se ofrece la acción explícita, no se ejecuta sola.
    expect(find.text('Preparar certificación con DOSA'), findsOneWidget);
  });

  testWidgets('el botón registra una sola vez y entonces abre el asistente',
      (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api);
    expect(api.registerCalls, isEmpty);

    await tester.tap(find.text('Preparar certificación con DOSA'));
    await tester.pumpAndSettle();

    expect(api.registerCalls, hasLength(1));
    // El paso previo desaparece: ya hay intención registrada y se monta el
    // asistente con su barra de estado.
    expect(find.text('Preparar certificación con DOSA'), findsNothing);
    expect(find.textContaining('Intento 1'), findsOneWidget);
  });

  testWidgets('un usuario sin permiso administrativo no ve la acción',
      (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api, role: 'MARKETING');

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación con DOSA'), findsNothing);
    expect(find.textContaining('Solo un administrador autorizado'), findsOneWidget);
  });

  testWidgets('un motivo del backend se explica y no abre el asistente',
      (tester) async {
    final api = _IntentApi(blockingReasons: const ['COMPANY_RNC_NOT_VERIFIED']);

    await pumpSection(tester, api: api);

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación con DOSA'), findsNothing);
    expect(
      find.textContaining('no tiene un RNC verificado'),
      findsOneWidget,
    );
  });
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _user({String role = 'ADMIN'}) {
  return UserModel(
    id: 'user-a',
    email: 'user-a@test.local',
    nombreCompleto: 'Admin Prueba',
    telefono: '',
    role: role,
    companyId: 'company-a',
    companyName: 'FULLTECH, SRL',
  );
}

/// Doble del cliente HTTP: cuenta lecturas y escrituras por separado, que es
/// justo la diferencia que estas pruebas vigilan.
class _IntentApi implements DosaCertificationIntentApi {
  _IntentApi({this.blockingReasons = const []});

  final List<String> blockingReasons;
  final List<String?> registerCalls = <String?>[];
  int stateCalls = 0;

  @override
  Future<DosaIntentState> state() async {
    stateCalls += 1;
    return DosaIntentState.fromJson({
      'companyId': 'company-a',
      'canonicalRnc': '133306001',
      'ecfEnabled': false, // emisión apagada: preparar sigue disponible
      'provider': 'DOSA',
      'canRegister': blockingReasons.isEmpty,
      'blockingReasons': blockingReasons,
    });
  }

  @override
  Future<DosaCertificationIntent> register({String? rnc}) async {
    registerCalls.add(rnc);
    return DosaCertificationIntent.fromJson(const {
      'companyId': 'company-a',
      'rnc': '133306001',
      'sessionId': 'session-1',
      'attemptNo': 1,
      'created': true,
      'status': 'NOT_STARTED',
      'provider': 'DOSA',
      'ecfEnabled': false,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
