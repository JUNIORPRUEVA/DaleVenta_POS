import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_section.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_session_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:dio/dio.dart';
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
    _SessionApi? sessionApi,
    DosaCertificationSessionApi? realSessionApi,
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
        // Por defecto la API de sesiones está deshabilitada: así los casos
        // históricos comprueban el fallback seguro al portal existente.
        dosaCertificationSessionApiProvider.overrideWithValue(
          realSessionApi ??
              sessionApi ??
              _SessionApi(
                error: DosaCertificationSessionException(
                  'ECF_DOSA_SESSION_DISABLED',
                ),
              ),
        ),
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
    expect(find.text('Postulación electrónica'), findsOneWidget);
    expect(find.text('Iniciar postulación'), findsOneWidget);
  });

  testWidgets('portal fuera del piloto falla cerrado', (tester) async {
    final api = _IntentApi();
    final portal = _PortalApi(eligible: false);

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(portal.eligibilityCalls, 1);
    expect(portal.ticketCalls, 0);
    expect(api.stateCalls, 0);
    expect(api.registerCalls, isEmpty);
    expect(find.text('Postulación electrónica'), findsNothing);
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
    expect(find.text('Postulación electrónica'), findsNothing);
  });

  testWidgets('un solo clic registra la intención y abre el portal', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);
    expect(portal.ticketCalls, 0);

    await tester.tap(find.text('Iniciar postulación'));
    await tester.pumpAndSettle();

    // Un toque: registra la intención (una vez) y pide el ticket del portal.
    expect(api.registerCalls, hasLength(1));
    expect(portal.ticketCalls, 1);
    expect(
      find.text('Asistente de certificación electrónica'),
      findsOneWidget,
    );
    // La reapertura queda como acción secundaria, no como paso obligatorio.
    expect(find.text('Continuar con el asistente'), findsOneWidget);
    expect(find.text('Iniciar postulación'), findsNothing);
  });

  testWidgets('doble clic no duplica la intención ni el ticket', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);
    final button = find.text('Iniciar postulación');

    // Dos toques dentro del mismo frame: el segundo no debe crear nada nuevo.
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(api.registerCalls, hasLength(1));
    expect(portal.ticketCalls, 1);
  });

  testWidgets('la API de sesiones abre la URL oficial sin pedir ticket', (
    tester,
  ) async {
    final api = _IntentApi();
    final portal = _PortalApi();
    final sessionApi = _SessionApi(
      session: const DosaCertificationSession(
        companyId: 'company-a',
        sessionUrl: 'mailto:sesion@example.test',
        expiresAt: '2030-01-01T00:00:00Z',
        attemptNo: 1,
        reused: false,
      ),
    );

    await pumpSection(
      tester,
      api: api,
      portalOnly: true,
      portalApi: portal,
      sessionApi: sessionApi,
    );

    await tester.tap(find.text('Iniciar postulación'));
    await tester.pumpAndSettle();

    expect(sessionApi.calls, 1);
    expect(portal.ticketCalls, 0);
    expect(api.registerCalls, hasLength(1));
  });

  testWidgets('un resultado incierto NO cae al portal antiguo', (tester) async {
    final api = _IntentApi();
    final portal = _PortalApi();
    final sessionApi = _SessionApi(
      error: DosaCertificationSessionException('ECF_DOSA_SESSION_UNCERTAIN'),
    );

    await pumpSection(
      tester,
      api: api,
      portalOnly: true,
      portalApi: portal,
      sessionApi: sessionApi,
    );

    await tester.tap(find.text('Iniciar postulación'));
    await tester.pumpAndSettle();

    expect(sessionApi.calls, 1);
    expect(portal.ticketCalls, 0);
    expect(find.textContaining('no confirmó la sesión'), findsOneWidget);
  });

  testWidgets('intención existente ofrece portal sin pedir ticket al cargar', (
    tester,
  ) async {
    final api = _IntentApi(hasSession: true);
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(
      find.text('Asistente de certificación electrónica'),
      findsOneWidget,
    );
    expect(find.text('Continuar con el asistente'), findsOneWidget);
    expect(api.registerCalls, isEmpty);
    expect(portal.ticketCalls, 0);
  });

  testWidgets('intención histórica ALANUBE no ofrece el portal DOSA', (
    tester,
  ) async {
    final api = _IntentApi(hasSession: true, provider: 'ALANUBE');
    final portal = _PortalApi();

    await pumpSection(tester, api: api, portalOnly: true, portalApi: portal);

    expect(
      find.textContaining('Revisa el intento de certificación existente'),
      findsOneWidget,
    );
    expect(find.text('Continuar con el asistente'), findsNothing);
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

    await tester.tap(find.text('Continuar con el asistente'));
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

  testWidgets('el botón registra una sola vez y entonces abre el asistente', (
    tester,
  ) async {
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

  testWidgets('un usuario sin permiso administrativo no ve la acción', (
    tester,
  ) async {
    final api = _IntentApi();

    await pumpSection(tester, api: api, role: 'MARKETING');

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación'), findsNothing);
    expect(
      find.textContaining('Solo un administrador autorizado'),
      findsOneWidget,
    );
  });

  testWidgets(
    'con intento ya registrado, el administrador ve el acceso al portal',
    (tester) async {
      final api = _IntentApi(hasSession: true);

      await pumpSection(tester, api: api);

      expect(find.text('Continuar certificación'), findsOneWidget);
      // Abrir el expediente sigue sin escribir nada.
      expect(api.registerCalls, isEmpty);
    },
  );

  testWidgets(
    'con intento ya registrado, un usuario sin permiso NO ve el portal',
    (tester) async {
      // Regresión: el panel se devolvía antes de comprobar el permiso, así que
      // un usuario sin manageEcfOnboarding veía el botón del portal.
      final api = _IntentApi(hasSession: true);

      await pumpSection(tester, api: api, role: 'MARKETING');

      expect(find.text('Continuar certificación'), findsNothing);
      expect(api.registerCalls, isEmpty);
    },
  );

  testWidgets(
    'expediente histórico solo muestra la autorización, no el portal',
    (tester) async {
      final api = _IntentApi(hasSession: true, historicalReviewRequired: true);

      await pumpSection(tester, api: api);

      // La autorización es el paso obligatorio: se muestra sin desplegarla.
      expect(
        find.text('Autorización administrativa requerida'),
        findsOneWidget,
      );
      expect(find.text('Continuar certificación'), findsNothing);
      expect(api.authorizeCalls, isEmpty);
    },
  );

  testWidgets(
    'si la autorización no está disponible no se ofrece el formulario',
    (tester) async {
      // El backend ya sabe que la acción no puede completarse: interruptor
      // apagado o expediente que dejó de estar en el Intento 1 original. Un
      // formulario aquí solo produciría un error al pulsar «Autorizar».
      final api = _IntentApi(
        hasSession: true,
        historicalReviewRequired: true,
        historicalTransitionAvailable: false,
      );

      await pumpSection(tester, api: api);

      expect(find.text('Autorización administrativa requerida'), findsNothing);
      expect(find.text('Continuar certificación'), findsNothing);
      expect(
        find.textContaining('no hay ninguna acción pendiente'),
        findsOneWidget,
      );
      expect(api.authorizeCalls, isEmpty);
    },
  );

  testWidgets(
    'con sesión vigente se reanuda aunque la autorización histórica haya expirado',
    (tester) async {
      final api = _IntentApi(
        hasSession: true,
        historicalReviewRequired: true,
        sessionReusable: true,
      );

      await pumpSection(tester, api: api);

      // No se pide una autorización nueva solo para volver a abrir una sesión
      // que el backend ya consideró vigente.
      expect(find.text('Autorización administrativa requerida'), findsNothing);
      expect(find.text('Continuar certificación'), findsOneWidget);
      expect(api.authorizeCalls, isEmpty);
      expect(api.registerCalls, isEmpty);
    },
  );

  testWidgets('un usuario sin permiso no ve la autorización histórica', (
    tester,
  ) async {
    final api = _IntentApi(hasSession: true, historicalReviewRequired: true);

    await pumpSection(tester, api: api, role: 'MARKETING');

    expect(find.text('Autorización administrativa requerida'), findsNothing);
    expect(find.text('Continuar certificación'), findsNothing);
    expect(api.authorizeCalls, isEmpty);
  });

  testWidgets(
    'el administrador autoriza con confirmación y refresca el estado',
    (tester) async {
      final api = _IntentApi(hasSession: true, historicalReviewRequired: true);

      await pumpSection(tester, api: api);

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Referencia de aprobación del propietario',
        ),
        'owner-approval-123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo de la autorización'),
        'Revisión documentada de la transición histórica.',
      );
      await tester.tap(
        find.text(
          'Confirmo que revisé el expediente y autorizo esta transición '
          'histórica.',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autorizar transición'));
      await tester.pumpAndSettle();

      // La confirmación es explícita: todavía no se envió nada.
      expect(api.authorizeCalls, isEmpty);
      await tester.tap(find.text('Autorizar'));
      await tester.pumpAndSettle();

      expect(api.authorizeCalls, hasLength(1));
      expect(api.authorizeCalls.single.intentId, 'session-1');
      expect(
        api.authorizeCalls.single.ownerApprovalReference,
        'owner-approval-123',
      );
      // Tras la autorización se refresca el estado y aparece el portal; nunca se
      // abre solo ni se registra una nueva intención.
      expect(find.text('Continuar certificación'), findsOneWidget);
      expect(api.registerCalls, isEmpty);
    },
  );

  testWidgets('un motivo del backend se explica y no abre el asistente', (
    tester,
  ) async {
    final api = _IntentApi(blockingReasons: const ['COMPANY_RNC_NOT_VERIFIED']);

    await pumpSection(tester, api: api);

    expect(api.registerCalls, isEmpty);
    expect(find.text('Preparar certificación'), findsNothing);
    expect(find.textContaining('no tiene un RNC verificado'), findsOneWidget);
  });

  group('la ruta la decide el backend, no un código de error', () {
    /// Dio que devuelve el estado y el cuerpo indicados, sin tocar la red.
    Dio dioCon(Object? body, int status) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: status,
                data: body,
              ),
            ),
          ),
        ),
      );
      return dio;
    }

    /// Respuesta real del backend con la apertura privada apagada.
    const cuerpoReal =
        '{"message":"ECF_DOSA_SESSION_DISABLED","error":"Service Unavailable",'
        '"statusCode":503}';

    Future<(_PortalApi, _SessionApi)> pulsarCon(
      WidgetTester tester, {
      required DosaCertificationMode mode,
      _SessionApi? sessionApi,
      Dio? dio,
    }) async {
      final portal = _PortalApi();
      final sessions =
          sessionApi ??
          _SessionApi(
            error: DosaCertificationSessionException(
              'ECF_DOSA_SESSION_DISABLED',
            ),
          );
      await pumpSection(
        tester,
        api: _IntentApi(hasSession: true, certificationMode: mode),
        portalOnly: true,
        portalApi: portal,
        sessionApi: sessions,
        realSessionApi: dio == null
            ? null
            : DosaCertificationSessionApi(dio),
      );
      await tester.tap(find.text('Continuar con el asistente'));
      await tester.pumpAndSettle();
      return (portal, sessions);
    }

    testWidgets('modo PUBLIC_PORTAL: no llama a la sesión privada y pide UN '
        'ticket', (tester) async {
      // El backend ya declaró que no puede abrir sesiones. El cliente no debe
      // provocar un 503 ni interpretar nada: va directo al portal.
      final (portal, sessions) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.publicPortal,
        // Si se llamara, fallaría de forma visible.
        sessionApi: _SessionApi(
          error: DosaCertificationSessionException('NO_DEBIO_LLAMARSE'),
        ),
      );

      expect(sessions.calls, 0);
      expect(portal.ticketCalls, 1);
    });

    testWidgets('modo PRIVATE_SESSION + apertura deshabilitada (cuerpo real): '
        'cae al portal una sola vez', (tester) async {
      final (portal, _) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.privateSession,
        dio: dioCon(cuerpoReal, 503),
      );

      expect(portal.ticketCalls, 1);
    });

    testWidgets('backend antiguo sin modo: intenta la sesión y solo un estado '
        'explícito abre el portal', (tester) async {
      final (portal, sessions) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.unknown,
      );

      expect(sessions.calls, 1); // sí se intentó la sesión privada
      expect(portal.ticketCalls, 1);
    });

    testWidgets('modo PRIVATE_SESSION + cifrado no configurado: cae al portal', (
      tester,
    ) async {
      final (portal, _) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.privateSession,
        sessionApi: _SessionApi(
          error: DosaCertificationSessionException(
            'ECF_DOSA_SESSION_ENCRYPTION_NOT_CONFIGURED',
          ),
        ),
      );

      expect(portal.ticketCalls, 1);
    });

    testWidgets('modo PRIVATE_SESSION + error desconocido (sin respuesta): NO '
        'pide ticket ni duplica', (tester) async {
      // Un fallo de transporte no dice si el proveedor abrió algo: no autoriza
      // continuar por otra vía.
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException.connectionError(
              requestOptions: options,
              reason: 'sin respuesta',
            ),
          ),
        ),
      );
      final (portal, _) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.privateSession,
        dio: dio,
      );

      expect(portal.ticketCalls, 0);
      expect(
        find.textContaining('No se pudo iniciar la postulación'),
        findsOneWidget,
      );
    });

    testWidgets('modo PRIVATE_SESSION + 503 sin código legible: NO pide ticket', (
      tester,
    ) async {
      final (portal, _) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.privateSession,
        dio: dioCon('<html>error</html>', 503),
      );

      expect(portal.ticketCalls, 0);
    });

    testWidgets('resultado incierto: NO pide ticket ni duplica', (
      tester,
    ) async {
      final (portal, _) = await pulsarCon(
        tester,
        mode: DosaCertificationMode.privateSession,
        sessionApi: _SessionApi(
          error: DosaCertificationSessionException(
            'ECF_DOSA_SESSION_UNCERTAIN',
          ),
        ),
      );

      expect(portal.ticketCalls, 0);
    });
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
class _AuthorizeCall {
  const _AuthorizeCall({
    required this.intentId,
    required this.ownerApprovalReference,
    required this.reason,
  });

  final String intentId;
  final String ownerApprovalReference;
  final String reason;
}

class _IntentApi implements DosaCertificationIntentApi {
  _IntentApi({
    this.blockingReasons = const [],
    this.hasSession = false,
    this.provider = 'DOSA',
    this.historicalReviewRequired = false,
    this.historicalTransitionAvailable,
    this.sessionReusable = false,
    this.certificationMode = DosaCertificationMode.privateSession,
  });

  final List<String> blockingReasons;

  /// Simula un expediente que ya tiene intento registrado.
  final bool hasSession;
  final String provider;
  bool historicalReviewRequired;

  /// `null` = el doble declara disponible siempre que haya revisión, que es el
  /// caso normal. Un test puede forzar `false` para simular un despliegue con
  /// el interruptor apagado o un expediente ya iniciado.
  final bool? historicalTransitionAvailable;
  final bool sessionReusable;

  /// Modo que declara el backend: decide la ruta sin interpretar errores.
  final DosaCertificationMode certificationMode;
  final List<String?> registerCalls = <String?>[];
  final List<_AuthorizeCall> authorizeCalls = <_AuthorizeCall>[];
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
      'historicalReviewRequired': historicalReviewRequired,
      'historicalTransitionAvailable':
          historicalTransitionAvailable ?? historicalReviewRequired,
      'certificationMode': switch (certificationMode) {
        DosaCertificationMode.privateSession => 'PRIVATE_SESSION',
        DosaCertificationMode.publicPortal => 'PUBLIC_PORTAL',
        DosaCertificationMode.unknown => null,
      },
      if (hasSession)
        'session': {
          'id': 'session-1',
          'status': 'NOT_STARTED',
          'attemptNo': 1,
          'reusable': sessionReusable,
        },
    });
  }

  @override
  Future<void> authorizeHistoricalTransition({
    required String intentId,
    required String ownerApprovalReference,
    required String reason,
  }) async {
    authorizeCalls.add(
      _AuthorizeCall(
        intentId: intentId,
        ownerApprovalReference: ownerApprovalReference,
        reason: reason,
      ),
    );
    historicalReviewRequired = false;
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

class _SessionApi implements DosaCertificationSessionApi {
  _SessionApi({this.error, this.session});

  final DosaCertificationSessionException? error;
  final DosaCertificationSession? session;
  int calls = 0;

  @override
  Future<DosaCertificationSession> open() async {
    calls += 1;
    if (error != null) throw error!;
    return session!;
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
    // Esquema no navegable a propósito: la prueba no debe lanzar un navegador
    // real ni tocar la red. `openDosaPortal` devuelve false y la sección avisa.
    return const DosaPortalTicket(
      url: 'mailto:sin-navegador@example.test',
      expiresAt: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
