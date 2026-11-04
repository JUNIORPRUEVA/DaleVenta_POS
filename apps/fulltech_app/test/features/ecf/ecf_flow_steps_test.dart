import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_application_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_certification_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_platform_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:daleventa_pos/features/ecf/ecf_certification_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_support_grant_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_habilitation_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_fiscal_data_page.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_flow_preview_button.dart';
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

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
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
}) => EcfDgiiHabilitationView(
  companyId: 'company-a',
  state: state,
  observations: null,
  officialAuthorization: official,
  officialAuthorizationBlockers: const [],
  authorizationSource: 'NONE',
  authorizedAt: null,
  moduleEnabled: true,
  certificationStatus: 'NOT_STARTED',
  providerIntegrationConfigured: false,
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
      legalRepresentativeName: complete ? 'Manolo Lio' : '',
      legalRepresentativeCedula: complete ? '40323211222' : '',
    );

Widget _harness({
  EcfDgiiHabilitationView? view,
  UserModel? user,
  CompanySettings? settings,
  bool simulationAvailable = false,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      ecfDgiiHabilitationProvider.overrideWith(
        (ref) async => view ?? _habilitation(),
      ),
      ecfDgiiHistoryProvider.overrideWith((ref) async => const []),
      ecfApplicationRepositoryProvider.overrideWithValue(
        _ApplicationRepository(),
      ),
      ecfPlatformStaffProvider.overrideWith((ref) async => false),
      dosaPortalEligibilityProvider.overrideWith((ref) async => false),
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

  testWidgets('bienvenida: sin formularios técnicos y con los 3 requisitos', (
    tester,
  ) async {
    await _pump(tester, _harness());

    expect(find.text('Activa tu facturación electrónica'), findsOneWidget);
    expect(
      find.textContaining('Te acompañamos durante el proceso de habilitación'),
      findsOneWidget,
    );
    // Requisitos esenciales, en el orden de la DGII.
    expect(
      find.text('Acceso al Portal de Certificación de la DGII'),
      findsOneWidget,
    );
    expect(find.text('Certificado digital vigente'), findsOneWidget);
    expect(find.text('Datos fiscales de la empresa'), findsOneWidget);
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
    'empresa: reutiliza los datos guardados y muestra el certificado',
    (tester) async {
      await _pump(tester, _harness());
      await _tapText(tester, 'Comenzar');

      expect(find.text('133020232'), findsOneWidget);
      expect(find.text('ECF Visual UAT Demo'), findsOneWidget);
      expect(find.text('Calle 1'), findsOneWidget);
      expect(find.text('Manolo Lio'), findsOneWidget);
      expect(find.text('Certificado digital'), findsOneWidget);
      expect(find.text('Validar certificado'), findsOneWidget);
      // No se vuelve a pedir lo que FullPOS ya conoce.
      expect(find.byType(TextField), findsOneWidget); // solo la contraseña
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empresa sin datos completos avisa y no deja continuar', (
    tester,
  ) async {
    await _pump(tester, _harness(settings: _settings(complete: false)));
    await _tapText(tester, 'Comenzar');
    await tester.pumpAndSettle();

    // El paso de empresa exige los datos: se resuelven con el mecanismo que ya
    // existe (el formulario fiscal del expediente) y no se ofrece «Continuar»
    // con datos incompletos.
    expect(find.byType(EcfFiscalDataContent), findsOneWidget);
    expect(find.text('Continuar'), findsNothing);
  });

  testWidgets('empresa: «Continuar» bloqueado hasta validar el certificado', (
    tester,
  ) async {
    await _pump(tester, _harness());
    await _tapText(tester, 'Comenzar');

    final button = find.byKey(const ValueKey('ecf_company_step_continue'));
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    // Se dice exactamente qué falta, sin obligar a avanzar y volver.
    expect(
      find.text(
        'Valida el certificado digital del representante legal para continuar.',
      ),
      findsOneWidget,
    );
    // Los datos ya registrados siguen a la vista y no se vuelven a pedir.
    expect(find.text('133020232'), findsOneWidget);
    expect(find.text('ECF Visual UAT Demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preparación: oculta el motor legado deshabilitado', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        view: _habilitation(progress: _certificateResolvedProgress()),
      ),
    );

    expect(find.text('Antes de postular'), findsOneWidget);
    expect(find.text('Datos de la empresa'), findsWidgets);
    expect(find.text('Certificado digital'), findsWidgets);
    expect(find.text('Acceso al portal de la DGII'), findsOneWidget);

    final button = find.byKey(
      const ValueKey('ecf_intelligent_certification_button'),
    );
    expect(button, findsNothing);
    expect(find.text('Postulación inteligente'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preparación: el modo de prueba se declara cuando existe', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        simulationAvailable: true,
        view: _habilitation(progress: _certificateResolvedProgress()),
      ),
    );

    expect(find.byKey(const ValueKey('ecf_test_mode_badge')), findsOneWidget);
    expect(find.textContaining('MODO DE PRUEBA'), findsOneWidget);
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
    await _tapText(tester, 'Seguimiento');

    expect(find.text('Solicitud'), findsOneWidget);
    expect(find.text('Pruebas'), findsOneWidget);
    expect(find.text('Certificación'), findsOneWidget);
    // El cliente no ve el listado técnico de operaciones.
    expect(find.text('Pruebas del SET'), findsNothing);
    expect(find.textContaining('36%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle técnico: invisible para quien no gestiona', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        user: _viewer(),
        view: _habilitation(state: 'IN_PROGRESS'),
      ),
    );
    await _tapText(tester, 'Seguimiento');
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
    expect(find.text('Empresa'), findsOneWidget);
    expect(find.text('Preparación'), findsOneWidget);
    expect(find.text('Seguimiento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('atajo de vista previa (solo empresa de prueba)', () {
    test('recorre los cuatro pasos y vuelve al primero', () {
      expect(nextEcfFlowStep(EcfFlowStep.welcome), EcfFlowStep.company);
      expect(nextEcfFlowStep(EcfFlowStep.company), EcfFlowStep.preparation);
      expect(nextEcfFlowStep(EcfFlowStep.preparation), EcfFlowStep.tracking);
      expect(nextEcfFlowStep(EcfFlowStep.tracking), EcfFlowStep.welcome);
    });

    testWidgets('el botón se dibuja con el nombre del paso siguiente', (
      tester,
    ) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EcfFlowPreviewButton(
              nextLabel: 'Empresa',
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      expect(find.text('Saltar a Empresa'), findsOneWidget);
      await tester.tap(find.text('Saltar a Empresa'));
      expect(pressed, 1);
    });

    testWidgets('sin la variable de compilación el atajo no existe', (
      tester,
    ) async {
      // La compilación de pruebas no define ECF_FLOW_PREVIEW_RNC, así que ni la
      // empresa real ni ninguna otra ven el botón.
      await _pump(tester, _harness());
      expect(find.textContaining('Saltar a'), findsNothing);
    });
  });
}
