import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_section.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
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

  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    required _IntentApi api,
    String role = 'ADMIN',
    String rnc = '133306001',
    bool portalOnly = false,
    _PortalApi? portalApi,
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
        dosaPortalApiProvider.overrideWithValue(portalApi ?? _PortalApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DosaAssistantSection(
                config: portalOnly
                    ? const DosaAssistantConfig(enabled: false)
                    : enabledConfig(),
                portalOnly: portalOnly,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('abrir el expediente NO registra la intención', (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api);

    // Solo se consultó el estado (lectura). Ninguna escritura.
    expect(api.stateCalls, 1);
    expect(api.registerCalls, isEmpty);
    // Y se ofrece la acción explícita, no se ejecuta sola.
    expect(find.text('Preparar certificación'), findsOneWidget);
  });

  testWidgets('portal en Preparación consulta elegibilidad sin escribir', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(portal.eligibilityCalls, 1);
    expect(portal.ticketCalls, 0);
    expect(api.stateCalls, 1);
    expect(api.registerCalls, isEmpty);
    expect(find.text('Estado de certificación'), findsOneWidget);
    expect(find.text('Preparar certificación'), findsOneWidget);
  });

  testWidgets('portal fuera del piloto falla cerrado', (tester) async {
    final api = _IntentApi();
    final portal = _PortalApi(eligible: false);

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(portal.eligibilityCalls, 1);
    expect(portal.ticketCalls, 0);
    expect(api.stateCalls, 0);
    expect(api.registerCalls, isEmpty);
    expect(find.text('Estado de certificación'), findsNothing);
  });

  testWidgets('portal sin permiso no consulta ni ofrece acciones', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();

    await pumpSection(
      tester,
      api: api,
      role: 'MARKETING',
      portalOnly: true,
      portalApi: portal,
    );

    expect(portal.eligibilityCalls, 0);
    expect(portal.ticketCalls, 0);
    expect(api.stateCalls, 0);
    expect(api.registerCalls, isEmpty);
    expect(find.text('Estado de certificación'), findsNothing);
  });

  testWidgets('portal registra intención solo después del clic', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);
    await tester.tap(find.text('Preparar certificación'));
    await tester.pumpAndSettle();

    expect(api.registerCalls, hasLength(1));
    expect(portal.ticketCalls, 0);
    expect(find.text('Estado de certificación'), findsOneWidget);
    expect(find.text('Continuar certificación'), findsOneWidget);
  });

  testWidgets('intención existente ofrece portal sin pedir ticket al cargar', (
    tester,
  ) async {
    final api = _IntentApi(hasSession: true);
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(find.text('Estado de certificación'), findsOneWidget);
    expect(find.text('Continuar certificación'), findsOneWidget);
    expect(api.registerCalls, isEmpty);
    expect(portal.ticketCalls, 0);
  });

  testWidgets('intención histórica ALANUBE no ofrece el portal DOSA', (
    tester,
  ) async {
    final api = _IntentApi(hasSession: true, provider: 'ALANUBE');
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(find.textContaining('Revisa el intento de certificación existente'),
        findsOneWidget);
    expect(find.text('Continuar certificación'), findsNothing);
    expect(api.registerCalls, isEmpty);
    expect(portal.ticketCalls, 0);
  });

  testWidgets('cambio de empresa durante el ticket no abre el portal', (
    tester,
  ) async {
    final ticket = Completer<DosaPortalTicket>();
    final portal = _PortalApi(pendingTicket: ticket);
    final container = await pumpSection(
      tester,
      api: _IntentApi(hasSession: true),
      portalOnly: true,
      portalApi: portal,
    );

    await tester.tap(find.text('Continuar certificación'));
    await tester.pump();
    expect(portal.ticketCalls, 1);

    (container.read(authStateProvider.notifier) as _FixedAuthController)
        .setTestUser(_user(companyId: 'company-b'));
    ticket.complete(
      const DosaPortalTicket(url: 'mailto:otro@example.test', expiresAt: ''),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo abrir el navegador'), findsNothing);
  });

  testWidgets('el botón registra una sola vez y entonces abre el asistente',
      (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api);
    expect(api.registerCalls, isEmpty);

    await tester.tap(find.text('Preparar certificación'));
    await tester.pumpAndSettle();

    expect(api.registerCalls, hasLength(1));
    // El paso previo desaparece: ya hay intención registrada y se monta el
    // asistente con su barra de estado.
    expect(find.text('Preparar certificación'), findsNothing);
    expect(find.textContaining('Intento 1'), findsOneWidget);
  });

  testWidgets('un usuario sin permiso administrativo no ve la acción',
      (tester) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api, role: 'MARKETING');

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación'), findsNothing);
    expect(find.textContaining('Solo un administrador autorizado'), findsOneWidget);
  });

  testWidgets(
      'con intento ya registrado, el administrador ve el acceso al portal',
      (tester) async {
    final api = _IntentApi(hasSession: true);

    await pumpSection(tester, api: api);

    expect(find.text('Continuar certificación'), findsOneWidget);
    // Abrir el expediente sigue sin escribir nada.
    expect(api.registerCalls, isEmpty);
  });

  testWidgets(
      'con intento ya registrado, un usuario sin permiso NO ve el portal',
      (tester) async {
    // Regresión: el panel se devolvía antes de comprobar el permiso, así que
    // un usuario sin manageEcfOnboarding veía el botón del portal.
    final api = _IntentApi(hasSession: true);

    await pumpSection(tester, api: api, role: 'MARKETING');

    expect(find.text('Continuar certificación'), findsNothing);
    expect(api.registerCalls, isEmpty);
  });

  testWidgets('un motivo del backend se explica y no abre el asistente',
      (tester) async {
    final api = _IntentApi(blockingReasons: const ['COMPANY_RNC_NOT_VERIFIED']);

    await pumpSection(tester, api: api);

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación'), findsNothing);
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

  void setTestUser(UserModel user) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: user,
      hasSessionHint: true,
    );
  }
}

UserModel _user({String role = 'ADMIN', String companyId = 'company-a'}) {
  return UserModel(
    id: 'user-a',
    email: 'user-a@test.local',
    nombreCompleto: 'Admin Prueba',
    telefono: '',
    role: role,
    companyId: companyId,
    companyName: 'FULLTECH, SRL',
  );
}

/// Doble del cliente HTTP: cuenta lecturas y escrituras por separado, que es
/// justo la diferencia que estas pruebas vigilan.
class _IntentApi implements DosaCertificationIntentApi {
  _IntentApi({this.blockingReasons = const [], this.hasSession = false,
    this.provider = 'DOSA'});

  final List<String> blockingReasons;

  /// Simula un expediente que ya tiene intento registrado.
  final bool hasSession;
  final String provider;
  final List<String?> registerCalls = <String?>[];
  int stateCalls = 0;

  @override
  Future<DosaIntentState> state() async {
    stateCalls += 1;
    return DosaIntentState.fromJson({
      'companyId': 'company-a',
      'canonicalRnc': '133306001',
      'ecfEnabled': false, // emisión apagada: preparar sigue disponible
      'provider': provider,
      'canRegister': blockingReasons.isEmpty,
      'blockingReasons': blockingReasons,
      if (hasSession)
        'session': {
          'id': 'session-1',
          'status': 'NOT_STARTED',
          'attemptNo': 1,
        },
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

class _PortalApi implements DosaPortalApi {
  _PortalApi({this.eligible = true, this.pendingTicket});

  final bool eligible;
  final Completer<DosaPortalTicket>? pendingTicket;
  int eligibilityCalls = 0;
  int ticketCalls = 0;

  @override
  Future<bool> isEligible() async {
    eligibilityCalls += 1;
    return eligible;
  }

  @override
  Future<DosaPortalTicket> requestTicket() async {
    ticketCalls += 1;
    if (pendingTicket != null) return pendingTicket!.future;
    throw StateError('No se debe pedir un ticket sin un clic explícito.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
