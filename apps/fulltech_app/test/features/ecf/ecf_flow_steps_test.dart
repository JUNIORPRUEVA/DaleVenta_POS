import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_application_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_certification_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_platform_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_session_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:daleventa_pos/features/ecf/ecf_certification_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_activation_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_support_grant_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_habilitation_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_fiscal_data_page.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_flow_step.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recorrido visual de la habilitación e-CF.
///
/// Lo que se comprueba aquí es la experiencia: que el cliente entre por una
/// bienvenida sin formularios técnicos, que sus datos se reutilicen, que el
/// seguimiento muestre **tres hitos** y no quince operaciones, y que el detalle
/// técnico quede fuera del camino salvo para quien puede gestionarlo.

/// Repositorio falso: el bloque de autorización consulta al aparecer y **ninguna
/// prueba puede salir a la red** (ni siquiera a un host real por defecto).
class _FakeEcfRepository extends EcfRepository {
  _FakeEcfRepository({EcfDosaActivationOutcome? outcome})
    : outcome =
           outcome ??
           EcfDosaActivationOutcome.fromJson(const {
             'ok': false,
             'companyId': 'company-a',
             'certificationStatus': 'IN_PROGRESS',
             'changed': false,
             'environments': [
               {
                 'environment': 'test',
                 'status': 'PENDING_CONFIRMATION',
                 'activated': false,
                 'blockingReasons': [
                   'ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED',
                 ],
               },
             ],
           }),
       super(Dio());

  final EcfDosaActivationOutcome outcome;
  int attempts = 0;

  @override
  Future<EcfDosaActivationOutcome> attemptDosaActivation() async {
    attempts++;
    return outcome;
  }

  /// Numeración ya declarada: la sección de e-NCF no aparece y estas pruebas
  /// siguen midiendo el recorrido, no el formulario de numeración.
  @override
  Future<List<EcfSequenceInfo>> sequences() async => const [
    EcfSequenceInfo(
      id: 'seq-1',
      documentType: 'E31',
      prefix: 'E31',
      startNumber: 1,
      nextNumber: 2,
      endNumber: 100,
      active: true,
      consumed: 1,
      remaining: 99,
    ),
  ];
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

class _FakeIntentApi implements DosaCertificationIntentApi {
  int registerCalls = 0;

  @override
  Future<DosaCertificationIntent> register({String? rnc}) async {
    registerCalls += 1;
    return DosaCertificationIntent.fromJson(const {
      'companyId': 'company-a',
      'rnc': '133020232',
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

class _FakeSessionApi implements DosaCertificationSessionApi {
  _FakeSessionApi({this.session, this.error});

  final DosaCertificationSession? session;
  final DosaCertificationSessionException? error;
  int openCalls = 0;

  @override
  Future<DosaCertificationSession> open() async {
    openCalls += 1;
    if (error != null) throw error!;
    return session!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ApplicationRepository extends EcfApplicationRepository {
  _ApplicationRepository() : super(Dio());

  @override
  Future<EcfApplicationDraft> draft() async => const EcfApplicationDraft(
    state: 'NOT_STARTED',
    draft: null,
    suggested: {
      'company': {'rnc': '131000001', 'legalName': 'Empresa'},
    },
    missingFields: [],
    draftUpdatedAt: null,
    draftRevision: 0,
    currentSnapshotVersion: 0,
    consentVersion: null,
    requiredConsentVersion: 'v1',
    consentPurpose: 'Consentimiento',
  );
}

UserModel _admin({String companyId = 'company-a'}) => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin',
  telefono: '',
  role: 'ADMIN',
  companyId: companyId,
  companyName: 'FULLTECH, SRL',
);

UserModel _viewer() => UserModel(
  id: 'user-b',
  email: 'tecnico@test.local',
  nombreCompleto: 'Técnico',
  telefono: '',
  role: 'TECNICO',
  companyId: 'company-a',
  companyName: 'FULLTECH, SRL',
  userPermissions: const {
    'manageEcfConfig': false,
    'manageEcfOnboarding': false,
    'manageEcfDgiiRequirements': false,
  },
);

EcfDgiiHabilitationView _habilitation({
  String state = 'NOT_STARTED',
  EcfDgiiProgress? progress,
  bool official = false,
  String? provider = 'DOSA',
}) => EcfDgiiHabilitationView(
  companyId: 'company-a',
  state: state,
  observations: null,
  provider: provider,
  officialAuthorization: official,
  officialAuthorizationBlockers: const [],
  authorizationSource: 'NONE',
  authorizedAt: null,
  moduleEnabled: true,
  certificationStatus: 'NOT_STARTED',
  providerIntegrationConfigured: false,
  certificateValidation:
      progress?.requirements.any(
            (item) => item.key == 'DIGITAL_CERTIFICATE' && item.resolved,
          ) ==
          true
      ? EcfPersistedCertificateValidation(
          ready: true,
          notAfter: DateTime.utc(2027, 4, 16),
        )
      : null,
  progress: progress ?? EcfDgiiProgress.empty,
  evidence: const [],
  emission: const EcfDgiiEmissionState(
    realEmissionAuthorized: false,
    simulatedDispatchAuthorized: false,
    productionEmissionImplemented: false,
  ),
  blockers: const [],
);

/// Progreso con el certificado digital ya registrado en el expediente.
///
/// Es la vía legítima para llegar al paso de preparación sin volver a validar el
/// archivo: el expediente ya lo tiene resuelto.
EcfDgiiProgress _certificateResolvedProgress() => const EcfDgiiProgress(
  requirements: <EcfDgiiRequirementProgress>[
    EcfDgiiRequirementProgress(
      key: 'DIGITAL_CERTIFICATE',
      label: 'Certificado digital',
      mandatory: true,
      automatable: true,
      status: 'RESOLVED',
      resolved: true,
    ),
  ],
  total: 1,
  resolvedCount: 1,
  mandatoryTotal: 1,
  mandatoryResolved: 1,
  percent: 100,
  pendingMandatory: <String>[],
);

CompanySettings _settings({bool complete = true}) =>
    CompanySettings.empty().copyWith(
      companyName: 'ECF Visual UAT Demo',
      rnc: '133020232',
      address: complete ? 'Calle 1' : '',
      ecfContactEmail: complete ? 'facturacion@example.test' : '',
      legalRepresentativeName: complete ? 'Manolo Lio' : '',
      legalRepresentativeCedula: complete ? '40323211222' : '',
    );

Widget _harness({
  EcfDgiiHabilitationView? view,
  UserModel? user,
  CompanySettings? settings,
  bool simulationAvailable = false,
  bool dosaEligible = false,
  _FakeIntentApi? intentApi,
  _FakeSessionApi? sessionApi,
  _FakeEcfRepository? repository,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      ecfRepositoryProvider.overrideWithValue(repository ?? _FakeEcfRepository()),
      ecfDgiiHabilitationProvider.overrideWith(
        (ref) async => view ?? _habilitation(),
      ),
      ecfDgiiHistoryProvider.overrideWith((ref) async => const []),
      ecfApplicationRepositoryProvider.overrideWithValue(
        _ApplicationRepository(),
      ),
      ecfPlatformStaffProvider.overrideWith((ref) async => false),
      dosaPortalEligibilityProvider.overrideWith((ref) async => dosaEligible),
      dosaIntentStateProvider.overrideWith(
        (ref) async => DosaIntentState.fromJson(const {
          'provider': 'DOSA',
          'canRegister': true,
          'blockingReasons': <String>[],
        }),
      ),
      dosaCertificationIntentApiProvider.overrideWithValue(
        intentApi ?? _FakeIntentApi(),
      ),
      dosaCertificationSessionApiProvider.overrideWithValue(
        sessionApi ??
            _FakeSessionApi(
              error: DosaCertificationSessionException(
                'ECF_DOSA_SESSION_DISABLED',
              ),
            ),
      ),
      ecfSupportGrantsProvider.overrideWith(
        (ref) async => const EcfSupportGrantList(items: []),
      ),
      ecfPreparationProvider.overrideWith(
        (ref) async => EcfPreparationMetadata(
          videoUrl: null,
          simulationAvailable: simulationAvailable,
          simulationBadge: 'MODO DE PRUEBA — NO SE ENVIARÁ NADA A DGII',
          simulationReason: null,
        ),
      ),
      ecfActivationProgressProvider.overrideWith(
        (ref) async => const EcfActivationProgress(
          stage: 'NOT_STARTED',
          percent: 0,
          resolvedCount: 0,
          total: 15,
          steps: <EcfActivationStepView>[],
          transportSimulated: true,
        ),
      ),
      companySettingsProvider.overrideWith(
        (ref) async => settings ?? _settings(),
      ),
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: user ?? _admin(),
            hasSessionHint: true,
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: EcfDgiiHabilitationPage()),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget harness, {
  Size size = const Size(1280, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('paso inicial', () {
    test('empresa nueva empieza en la bienvenida', () {
      expect(
        initialEcfFlowStep(
          state: 'NOT_STARTED',
          hasResolvedRequirement: false,
          officialAuthorization: false,
          fiscalReady: true,
          certificateValidated: false,
          testsOrLater: false,
        ),
        EcfFlowStep.welcome,
      );
    });

    test('expediente en curso entra donde está, no en la bienvenida', () {
      expect(
        initialEcfFlowStep(
          state: 'IN_PROGRESS',
          hasResolvedRequirement: true,
          officialAuthorization: false,
          fiscalReady: true,
          certificateValidated: false,
          testsOrLater: false,
        ),
        EcfFlowStep.preparation,
      );
      expect(
        initialEcfFlowStep(
          state: 'IN_PROGRESS',
          hasResolvedRequirement: true,
          officialAuthorization: false,
          fiscalReady: true,
          certificateValidated: true,
          testsOrLater: false,
        ),
        EcfFlowStep.preparation,
      );
      expect(
        initialEcfFlowStep(
          state: 'TESTS_PENDING',
          hasResolvedRequirement: true,
          officialAuthorization: false,
          fiscalReady: true,
          certificateValidated: true,
          testsOrLater: true,
        ),
        EcfFlowStep.tracking,
      );
    });
  });

  testWidgets('bienvenida: vídeo, portal DGII y una sola acción', (
    tester,
  ) async {
    await _pump(tester, _harness());

    expect(find.text('Activa tu facturación electrónica'), findsOneWidget);
    expect(
      find.textContaining('Todo el proceso, acompañado por FullPOS'),
      findsOneWidget,
    );
    // El recorrido no repite requisitos en la portada.
    expect(
      find.text('Acceso al Portal de Certificación de la DGII'),
      findsNothing,
    );
    expect(find.text('Certificado digital vigente'), findsNothing);
    expect(find.text('Datos fiscales de la empresa'), findsNothing);
    // Espacio del vídeo sin simular reproducción + portal oficial.
    expect(find.text('Aquí irá el vídeo de preparación'), findsOneWidget);
    expect(find.text('Abrir portal de la DGII'), findsOneWidget);
    // Ni XML, ni evidencias, ni estados internos en la portada.
    expect(find.text('XML de postulación'), findsNothing);
    expect(find.text('Detalle técnico'), findsNothing);
    expect(find.text('Comenzar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preparación: reutiliza los datos guardados y no repite el certificado',
    (tester) async {
      await _pump(tester, _harness());
      await _tapText(tester, 'Comenzar');

      // Los datos completos NO se repiten: quedan en una sola línea con la
      // opción de copiarlos, y el detalle vive en Configuración de empresa.
      expect(find.textContaining('133020232'), findsOneWidget);
      expect(find.textContaining('ECF Visual UAT Demo'), findsOneWidget);
      expect(find.text('Completa lo que falta'), findsNothing);
      expect(find.text('Correo fiscal'), findsNothing);
      // El certificado pertenece al asistente de DOSA: no se muestra como
      // dato cargado ni como paso pendiente en FullPOS.
      expect(find.text('Certificado digital'), findsNothing);
      expect(find.text('Validar certificado'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recorrido UAT: empresa → preparación → un clic → sesión', (
    tester,
  ) async {
    final intentApi = _FakeIntentApi();
    final sessionApi = _FakeSessionApi(
      session: const DosaCertificationSession(
        companyId: 'company-a',
        sessionUrl: 'mailto:sesion@example.test',
        expiresAt: '2030-01-01T00:00:00Z',
        attemptNo: 1,
        reused: false,
      ),
    );
    await _pump(
      tester,
      _harness(
        dosaEligible: true,
        intentApi: intentApi,
        sessionApi: sessionApi,
      ),
      size: const Size(1280, 1400),
    );
    await _tapText(tester, 'Comenzar');

    expect(find.text('Iniciar postulación'), findsOneWidget);
    await _tapText(tester, 'Iniciar postulación');

    expect(intentApi.registerCalls, 1);
    expect(sessionApi.openCalls, 1);
    expect(find.text('Continuar con el asistente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preparación incompleta pide completar sin duplicar el formulario',
    (tester) async {
      await _pump(tester, _harness(settings: _settings(complete: false)));
      await _tapText(tester, 'Comenzar');
      await tester.pumpAndSettle();

      expect(find.text('Completar datos'), findsOneWidget);
      expect(find.text('Iniciar postulación'), findsNothing);
      expect(find.byType(EcfFiscalDataContent), findsNothing);

      await _tapText(tester, 'Completar datos');
      expect(find.byType(EcfFiscalDataContent), findsOneWidget);
      expect(find.text('Correo fiscal'), findsOneWidget);
    },
  );

  testWidgets('preparación DOSA: una sola acción y sin pedir certificado', (
    tester,
  ) async {
    await _pump(tester, _harness(dosaEligible: true));
    await _tapText(tester, 'Comenzar');

    expect(find.text('Iniciar postulación'), findsOneWidget);
    expect(find.text('Validar certificado'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Postulación inteligente'), findsNothing);
    expect(find.text('Antes de postular'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preparación DOSA: RNC y correo se pueden copiar sin duplicarlos',
    (tester) async {
      await _pump(tester, _harness(dosaEligible: true));
      await _tapText(tester, 'Comenzar');

      // El asistente oficial los vuelve a pedir; se copian en un solo toque.
      expect(find.text('Copiar'), findsOneWidget);
      // El dato no se duplica: una sola línea con empresa y RNC.
      expect(find.textContaining('133020232'), findsOneWidget);
      expect(find.text('facturacion@example.test'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preparación sin correo: no ofrece copiar un dato que falta', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(dosaEligible: true, settings: _settings(complete: false)),
    );
    await _tapText(tester, 'Comenzar');

    expect(find.byTooltip('Copiar correo fiscal'), findsNothing);
    expect(find.text('Falta el correo de facturación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preparación: sin datos no ofrece la postulación', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(dosaEligible: true, settings: _settings(complete: false)),
    );
    await _tapText(tester, 'Comenzar');

    expect(find.text('Completar datos'), findsOneWidget);
    expect(find.text('Iniciar postulación'), findsNothing);
    expect(find.text('Validar certificado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seguimiento: solo tres hitos y no quince operaciones', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        view: _habilitation(
          state: 'IN_PROGRESS',
          progress: const EcfDgiiProgress(
            requirements: [
              EcfDgiiRequirementProgress(
                key: 'FISCAL_DATA',
                label: 'Datos fiscales de la empresa',
                mandatory: true,
                automatable: true,
                status: 'COMPLETED',
                resolved: true,
              ),
              EcfDgiiRequirementProgress(
                key: 'SET_TESTS',
                label: 'Pruebas del SET',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
              ),
            ],
            total: 14,
            resolvedCount: 5,
            mandatoryTotal: 13,
            mandatoryResolved: 5,
            percent: 36,
            pendingMandatory: ['SET_TESTS'],
          ),
        ),
      ),
    );

    expect(find.text('Solicitud'), findsOneWidget);
    expect(find.text('Pruebas'), findsOneWidget);
    expect(find.text('Certificación'), findsOneWidget);
    // El cliente no ve el listado técnico de operaciones ni porcentajes internos.
    expect(find.text('Pruebas del SET'), findsNothing);
    expect(find.textContaining('36%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle técnico: invisible para quien no gestiona', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        user: _viewer(),
        view: _habilitation(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
        ),
      ),
    );
    expect(find.text('Detalle técnico'), findsNothing);
    expect(find.text('Avanzar estado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposición estrecha: los pasos no desbordan a 360 px', (
    tester,
  ) async {
    await _pump(tester, _harness(), size: const Size(360, 800));
    expect(find.text('Activa tu facturación electrónica'), findsOneWidget);
    await _tapText(tester, 'Comenzar');
    expect(find.text('Bienvenida'), findsOneWidget);
    expect(find.text('Preparación'), findsWidgets);
    expect(find.text('Tu postulación'), findsOneWidget);
    expect(find.text('Empresa'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
