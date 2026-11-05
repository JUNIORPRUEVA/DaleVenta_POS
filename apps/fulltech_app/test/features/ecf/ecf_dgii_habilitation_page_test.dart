import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:dio/dio.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_platform_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_application_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_certification_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:daleventa_pos/features/ecf/ecf_certification_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_support_grant_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_habilitation_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_application_wizard.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_fiscal_data_page.dart';
import 'package:daleventa_pos/core/widgets/responsive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pantalla de habilitación DGII por empresa.
///
/// Lo que se comprueba aquí no es estética: es que la interfaz **no** pueda
/// presentar como aprobada una empresa que no lo está, ni ofrecer una acción de
/// aprobación oficial, ni insinuar que la emisión real está permitida.

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }

  void replaceUser(UserModel? user) {
    state = AuthState(
      initialized: true,
      isAuthenticated: user != null,
      user: user,
    );
  }
}

class _SessionEcfRepository extends EcfRepository {
  _SessionEcfRepository(this.companyId) : super(Dio());

  final String Function() companyId;
  int reads = 0;

  @override
  Future<EcfDgiiHabilitationView> dgiiHabilitation() async {
    reads++;
    return _view(companyId: companyId());
  }
}

class _ApplicationRepository extends EcfApplicationRepository {
  _ApplicationRepository() : super(Dio());

  @override
  Future<EcfApplicationDraft> draft() async => const EcfApplicationDraft(
    state: 'NOT_STARTED',
    draft: null,
    suggested: {
      'company': {
        'rnc': '131000001',
        'legalName': 'Empresa',
        'address': 'Calle 1',
      },
      'representative': {'fullName': 'Ana', 'identification': '00100000001'},
    },
    missingFields: ['representative.email'],
    draftUpdatedAt: null,
    draftRevision: 0,
    currentSnapshotVersion: 0,
    consentVersion: null,
    requiredConsentVersion: 'v1',
    consentPurpose: 'Consentimiento',
  );
}

UserModel _adminUser({String companyId = 'company-a'}) => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin',
  telefono: '',
  role: 'ADMIN',
  companyId: companyId,
  companyName: 'FULLTECH, SRL',
);

/// Usuario NO administrador y sin el permiso del módulo e-CF.
UserModel _userWithoutPermission({String companyId = 'company-a'}) => UserModel(
  id: 'user-b',
  email: 'tecnico@test.local',
  nombreCompleto: 'Técnico',
  telefono: '',
  role: 'TECNICO',
  companyId: companyId,
  companyName: 'FULLTECH, SRL',
  userPermissions: const {'manageEcfConfig': false},
);

/// Usuario NO administrador con permisos explícitos.
///
/// El rol no concede nada por sí mismo: importa el permiso, y estos nombres
/// coinciden con los que valida el backend.
UserModel _userWith(
  Map<String, bool> permissions, {
  String companyId = 'company-a',
}) => UserModel(
  id: 'user-c',
  email: 'operador@test.local',
  nombreCompleto: 'Operador',
  telefono: '',
  role: 'VENDEDOR',
  companyId: companyId,
  companyName: 'FULLTECH, SRL',
  userPermissions: permissions,
);

const _noAuthorization = EcfDgiiEmissionState(
  realEmissionAuthorized: false,
  simulatedDispatchAuthorized: false,
  productionEmissionImplemented: false,
);

/// Expediente con el certificado digital ya registrado.
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

EcfPersistedCertificateValidation _validCertificate() =>
    EcfPersistedCertificateValidation(
      ready: true,
      notAfter: DateTime.utc(2027, 4, 16),
    );

EcfDgiiHabilitationView _view({
  String companyId = 'company-a',
  String state = 'NOT_STARTED',
  String? observations,
  bool officialAuthorization = false,
  List<EcfDgiiBlocker> officialBlockers = const [],
  String authorizationSource = 'NONE',
  DateTime? authorizedAt,
  EcfDgiiProgress? progress,
  EcfPersistedCertificateValidation? certificateValidation,
  List<EcfDgiiEvidenceView> evidence = const [],
  EcfDgiiEmissionState emission = _noAuthorization,
  List<EcfDgiiBlocker> blockers = const [],
  String? provider = 'DOSA',
}) {
  return EcfDgiiHabilitationView(
    companyId: companyId,
    state: state,
    provider: provider,
    observations: observations,
    officialAuthorization: officialAuthorization,
    officialAuthorizationBlockers: officialBlockers,
    authorizationSource: authorizationSource,
    authorizedAt: authorizedAt,
    moduleEnabled: true,
    certificationStatus: 'NOT_STARTED',
    providerIntegrationConfigured: false,
    certificateValidation: certificateValidation,
    progress: progress ?? EcfDgiiProgress.empty,
    evidence: evidence,
    emission: emission,
    blockers: blockers,
  );
}

EcfDgiiProgress _progress({
  int total = 14,
  int resolvedCount = 5,
  int mandatoryTotal = 13,
  int mandatoryResolved = 5,
  int percent = 36,
  List<String> pendingMandatory = const ['SET_TESTS'],
  List<EcfDgiiRequirementProgress> requirements = const [],
}) {
  return EcfDgiiProgress(
    requirements: requirements,
    total: total,
    resolvedCount: resolvedCount,
    mandatoryTotal: mandatoryTotal,
    mandatoryResolved: mandatoryResolved,
    percent: percent,
    pendingMandatory: pendingMandatory,
  );
}

Widget _harness({
  EcfDgiiHabilitationView? view,
  List<EcfDgiiHistoryEntry> history = const [],
  UserModel? user,
  Object? error,
  void Function()? onRead,
  CompanySettings? settings,
  bool dosaEligible = false,
}) {
  return ProviderScope(
    // `pumpWidget` ACTUALIZA el árbol existente en vez de recrearlo, y el
    // `ProviderScope` conserva su contenedor: sin una clave nueva, los
    // `overrides` de una segunda invocación no surtirían efecto y la prueba
    // mediría al usuario anterior.
    key: UniqueKey(),
    overrides: [
      ecfDgiiHabilitationProvider.overrideWith((ref) async {
        onRead?.call();
        if (error != null) throw error;
        return view ??
            _view(
              state: 'TESTS_PENDING',
              progress: _certificateResolvedProgress(),
            );
      }),
      ecfDgiiHistoryProvider.overrideWith((ref) async => history),
      ecfApplicationRepositoryProvider.overrideWithValue(
        _ApplicationRepository(),
      ),
      // La pantalla pregunta al backend si la sesión es personal de plataforma.
      // La prueba fija la respuesta: sin esto quedaría una petición de red real
      // con su temporizador pendiente al desmontar el árbol.
      ecfPlatformStaffProvider.overrideWith((ref) async => false),
      dosaPortalEligibilityProvider.overrideWith((ref) async => dosaEligible),
      dosaIntentStateProvider.overrideWith(
        (ref) async => DosaIntentState.fromJson(const {
          'provider': 'DOSA',
          'canRegister': true,
          'blockingReasons': <String>[],
        }),
      ),
      // El panel de «Ayuda y soporte» muestra el estado de la asistencia
      // temporal: sin este stub haría una petición real y el `pumpAndSettle`
      // no terminaría nunca.
      ecfSupportGrantsProvider.overrideWith(
        (ref) async => const EcfSupportGrantList(items: []),
      ),
      // Preparación (vídeo y modo de prueba) y progreso del motor: sin estos
      // stubs la pantalla haría peticiones reales y quedarían temporizadores
      // pendientes al desmontar.
      ecfPreparationProvider.overrideWith(
        (ref) async => const EcfPreparationMetadata(
          videoUrl: null,
          simulationAvailable: false,
          simulationBadge: 'MODO DE PRUEBA — NO SE ENVIARÁ NADA A DGII',
          simulationReason:
              'El motor de certificación no está habilitado en este entorno.',
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
        (ref) async =>
            settings ??
            CompanySettings.empty().copyWith(
              companyName: 'Empresa',
              rnc: '131000001',
              address: 'Calle 1',
              ecfContactEmail: 'facturacion@example.test',
            ),
      ),
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: user ?? _adminUser(),
            hasSessionHint: true,
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: EcfDgiiHabilitationPage()),
  );
}

/// Monta la pantalla en una ventana amplia (objetivo Windows/Web).
///
/// El recorrido ahora es por pasos: por defecto la prueba entra a
/// **Tu postulación**, donde vive el detalle técnico que antes estaba siempre
/// visible, y despliega ese bloque. Las pruebas que verifican la bienvenida o la
/// preparación pasan `step: null` o el paso que corresponda.
Future<void> _pumpPage(
  WidgetTester tester,
  Widget harness, {
  Size size = const Size(1400, 2600),
  String? step = 'Tu postulación',
  bool technical = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
  if (step != null) {
    // La bienvenida no muestra la guía de pasos: se entra con «Comenzar».
    if (find.text(step).evaluate().isEmpty &&
        find.text('Comenzar').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Comenzar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comenzar').first);
      await tester.pumpAndSettle();
    }
    final target = find.text(step);
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
      await tester.tap(target.first);
      await tester.pumpAndSettle();
    }
  }
  // El detalle técnico (requisitos, emisión, seguimiento interno) no forma
  // parte de la navegación del cliente: vive dentro de «Avanzado», solo para
  // administradores. Se abre para poder verificarlo.
  if (!technical) return;
  final advanced = find.text('Avanzado');
  if (advanced.evaluate().isNotEmpty) {
    await tester.ensureVisible(advanced.first);
    await tester.pumpAndSettle();
    await tester.tap(advanced.first);
    await tester.pumpAndSettle();
  }
  final block = find.text('Detalle técnico');
  if (block.evaluate().isNotEmpty) {
    await tester.ensureVisible(block.first);
    await tester.pumpAndSettle();
    await tester.tap(block.first);
    await tester.pumpAndSettle();
  }
}

void main() {
  test('recarga el expediente al cambiar de empresa o iniciar otra sesión', () async {
    late ProviderContainer container;
    final repository = _SessionEcfRepository(
      () => container.read(authStateProvider).user?.companyId ?? '',
    );
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _adminUser(),
          ),
        ),
      ),
      ecfRepositoryProvider.overrideWithValue(repository),
    ]);
    final subscription = container.listen(
      ecfDgiiHabilitationProvider,
      (_, __) {},
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    expect(
      (await container.read(ecfDgiiHabilitationProvider.future)).companyId,
      'company-a',
    );
    (container.read(authStateProvider.notifier) as _FixedAuthController).replaceUser(
          _adminUser(companyId: 'company-b'),
        );
    expect(
      (await container.read(ecfDgiiHabilitationProvider.future)).companyId,
      'company-b',
    );
    (container.read(authStateProvider.notifier) as _FixedAuthController).replaceUser(null);
    (container.read(authStateProvider.notifier) as _FixedAuthController).replaceUser(
          _adminUser(companyId: 'company-b'),
        );
    expect(
      (await container.read(ecfDgiiHabilitationProvider.future)).companyId,
      'company-b',
    );
    expect(repository.reads, greaterThanOrEqualTo(3));
  });

  for (final width in [320.0, 360.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('tres hitos sin desbordes a ${width.toInt()} px', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _harness(view: _view(state: 'IN_PROGRESS')),
        size: Size(width, 844),
      );
      expect(find.text('Solicitud'), findsOneWidget);
      expect(find.text('Pruebas'), findsOneWidget);
      expect(find.text('Certificación'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cliente nuevo: bienvenida y luego sus datos fiscales', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        view: _view(state: 'NOT_STARTED'),
        settings: CompanySettings.empty(),
      ),
      step: null,
      technical: false,
    );
    // Sin nada iniciado se ve la bienvenida, sin formularios técnicos.
    expect(find.text('Activa tu facturación electrónica'), findsOneWidget);
    expect(find.byType(EcfFiscalDataContent), findsNothing);
    expect(find.byType(EcfDgiiApplicationWizard), findsNothing);

    await tester.tap(find.text('Comenzar').first);
    await tester.pumpAndSettle();
    // La preparación no abre el formulario sola: primero muestra qué falta.
    expect(find.byType(EcfFiscalDataContent), findsNothing);
    await tester.tap(find.text('Completar datos'));
    await tester.pumpAndSettle();
    expect(find.byType(EcfFiscalDataContent), findsOneWidget);
    expect(find.byType(EcfDgiiApplicationWizard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cliente con datos fiscales válidos no repite el formulario', (
    tester,
  ) async {
    await _pumpPage(tester, _harness(), step: 'Preparación', technical: false);
    expect(find.byType(EcfFiscalDataContent), findsNothing);
    expect(find.text('Tu empresa'), findsOneWidget);
    expect(find.text('Postulación inteligente'), findsNothing);
  });

  testWidgets('un solo dato obligatorio pendiente muestra un solo campo', (
    tester,
  ) async {
    final settings = CompanySettings.empty().copyWith(
      companyName: 'Empresa',
      rnc: '131000001',
      address: '',
      ecfContactEmail: 'facturacion@example.test',
      legalRepresentativeName: 'Ana',
      legalRepresentativeCedula: '00100000001',
    );
    await _pumpPage(
      tester,
      _harness(view: _view(state: 'NOT_STARTED'), settings: settings),
    );
    await tester.tap(find.text('Completar datos'));
    await tester.pumpAndSettle();
    expect(find.byType(EcfFiscalDataContent), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Dirección fiscal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completar datos abre el formulario fiscal dentro de la preparación', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        view: _view(state: 'NOT_STARTED'),
        settings: CompanySettings.empty().copyWith(
          companyName: 'Empresa',
          rnc: '131000001',
          address: 'Calle 1',
        ),
      ),
    );
    await tester.tap(find.text('Completar datos').first);
    await tester.pumpAndSettle();
    expect(find.byType(EcfFiscalDataContent), findsOneWidget);
    expect(find.byType(EcfDgiiApplicationWizard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empresa sin habilitación: no hay autorización oficial', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
        ),
      ),
    );

    expect(find.text('En pruebas'), findsOneWidget);
    // Nunca se declara una autorización oficial que no existe.
    expect(find.text('Autorización oficial registrada'), findsNothing);
    expect(find.text('Solicitud'), findsOneWidget);
    expect(
      find.textContaining('Adjunta la evidencia disponible'),
      findsNothing,
    );
    // Nunca se insinúa que la emisión esté permitida.
    expect(find.text('Bloqueada'), findsOneWidget);
  });

  testWidgets(
    'certificado pendiente mantiene al cliente en Preparación',
    (tester) async {
      await _pumpPage(
        tester,
        _harness(
          view: _view(
            state: 'APPLICATION_PENDING',
            progress: _progress(
              requirements: const [
                EcfDgiiRequirementProgress(
                  key: 'DIGITAL_CERTIFICATE',
                  label: 'Certificado digital',
                  mandatory: true,
                  automatable: false,
                  status: 'PENDING',
                  resolved: false,
                ),
              ],
            ),
          ),
        ),
        step: null,
        technical: false,
      );
      // Un requisito pendiente no adelanta al cliente a la vista de seguimiento.
      expect(find.text('Tu empresa'), findsOneWidget);
      expect(find.text('Pruebas del SET'), findsNothing);
      // DOSA no pide el certificado en FullPOS.
      expect(find.text('Certificado digital'), findsNothing);
    },
  );

  testWidgets('empresa en proceso: muestra estado, progreso y requisitos', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'IN_PROGRESS',
          observations: 'Pendiente el set de pruebas',
          progress: _progress(
            requirements: const [
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
          ),
        ),
      ),
    );

    // El cliente ve una etiqueta comprensible; el nombre técnico queda en
    // «Detalle técnico» para administradores.
    expect(find.text('En revisión interna'), findsOneWidget);
    expect(find.text('Estado interno'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('36%'), findsOneWidget);
    expect(find.textContaining('5 de 14 requisitos'), findsOneWidget);
    expect(find.textContaining('obligatorios 5/13'), findsOneWidget);
    expect(find.text('Datos fiscales de la empresa'), findsOneWidget);
    expect(find.text('Pruebas del SET'), findsOneWidget);
    expect(find.text('Pendiente el set de pruebas'), findsWidgets);
  });

  testWidgets('revisión interna no adelanta la solicitud a pruebas', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        view: _view(
          state: 'APPLICATION_PENDING',
          progress: _progress(
            requirements: const [
              EcfDgiiRequirementProgress(
                key: 'SET_TESTS',
                label: 'Pruebas del SET',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
              ),
            ],
          ),
        ),
      ),
      step: null,
      technical: false,
    );
    // El cliente permanece en Preparación; no ve la guía técnica antigua.
    expect(find.text('Tu empresa'), findsOneWidget);
    expect(find.text('Ver cómo presentar'), findsNothing);
    expect(find.text('Cómo presentar tu solicitud'), findsNothing);
  });

  testWidgets('preparación local: vídeo, certificado y botón sin habilitar', (
    tester,
  ) async {
    // Bienvenida: guía de preparación. El vídeo es configuración; sin URL no se
    // finge reproducción.
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        dosaEligible: true,
        view: _view(state: 'NOT_STARTED'),
      ),
      step: null,
      technical: false,
    );
    expect(find.text('Antes de empezar'), findsOneWidget);
    expect(find.text('Vídeo no disponible'), findsOneWidget);
    expect(find.text('Abrir portal de la DGII'), findsOneWidget);

    // Preparación con DOSA: el certificado no se pide en FullPOS.
    await tester.tap(find.text('Comenzar').first);
    await tester.pumpAndSettle();
    expect(find.text('Certificado digital'), findsNothing);
    expect(find.text('Validar certificado'), findsNothing);
    expect(find.text('Ningún archivo seleccionado'), findsNothing);
    expect(find.textContaining('No hay que subirlos aquí'), findsNothing);
    expect(find.text('Iniciar postulación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empresa Alanube conserva la carga local del certificado', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(provider: 'ALANUBE', state: 'NOT_STARTED'),
      ),
      step: null,
      technical: false,
    );
    await tester.tap(find.text('Comenzar').first);
    await tester.pumpAndSettle();

    // El proveedor legado conserva su validación local solo mientras exista
    // esa rama; el recorrido DOSA no muestra ese paso.
    expect(find.text('Validar certificado'), findsOneWidget);
    expect(find.textContaining('No hay que subirlos aquí'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preparación: el botón de postulación espera al modo de prueba', (
    tester,
  ) async {
    // Se entra con el certificado ya registrado en el expediente (vía legítima
    // sin volver a subir el archivo): el recorrido abre directamente la
    // preparación.
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          progress: _certificateResolvedProgress(),
          certificateValidation: _validCertificate(),
        ),
      ),
      step: null,
      technical: false,
    );
    expect(find.text('Tu empresa'), findsOneWidget);

    // El motor legado desaparece cuando el modo de prueba no está disponible.
    final button = find.byKey(
      const ValueKey('ecf_intelligent_certification_button'),
    );
    expect(button, findsNothing);
    // Sin modo de prueba disponible no se muestra el distintivo de pruebas.
    expect(find.byKey(const ValueKey('ecf_test_mode_badge')), findsNothing);
    expect(find.text('Estado de certificación'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un requisito resuelto sin vigencia confirmada deja el certificado a DOSA', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(view: _view(progress: _certificateResolvedProgress())),
      step: null,
      technical: false,
    );
    // Sin vigencia confirmada no se finge que el certificado está validado,
    // pero tampoco se bloquea el recorrido: el certificado lo pide DOSA.
    expect(find.text('Tu empresa'), findsOneWidget);
    expect(find.text('Certificado digital'), findsNothing);
    expect(find.text('Continuar con DOSA'), findsNothing);
  });

  testWidgets('preparación ofrece DOSA al piloto sin activar el motor legado', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        view: _view(
          progress: _certificateResolvedProgress(),
          certificateValidation: _validCertificate(),
        ),
        dosaEligible: true,
      ),
      step: null,
      technical: false,
    );

    expect(find.text('Postulación electrónica'), findsOneWidget);
    // Un solo botón principal: inicia la postulación oficial de DOSA.
    expect(find.text('Iniciar postulación'), findsOneWidget);
    final legacy = find.byKey(
      const ValueKey('ecf_intelligent_certification_button'),
    );
    expect(legacy, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrada DOSA no desborda en móvil', (tester) async {
    await _pumpPage(
      tester,
      _harness(
        view: _view(
          progress: _certificateResolvedProgress(),
          certificateValidation: _validCertificate(),
        ),
        dosaEligible: true,
      ),
      size: const Size(360, 844),
      step: null,
      technical: false,
    );

    expect(find.text('Iniciar postulación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('los pasos de presentación DGII no se completan por proveedor', (
    tester,
  ) async {
    // El motor no es dueño de estas presentaciones: sin integración autorizada,
    // el paso queda esperando al cliente y nunca como completado.
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'IN_PROGRESS',
          progress: _progress(
            requirements: const [
              EcfDgiiRequirementProgress(
                key: 'DGII_POSTULATION',
                label: 'Postulación DGII',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
              ),
            ],
          ),
        ),
      ),
    );
    // Se declara como acción del cliente, no como algo automático.
    expect(find.text('Postulación DGII'), findsOneWidget);
    expect(find.text('Pendiente'), findsWidgets);
    expect(find.text('Automático'), findsNothing);
  });

  testWidgets('requisitos pendientes: aparecen como bloqueo explícito', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'APPLICATION_PENDING',
          blockers: const [
            EcfDgiiBlocker(
              code: 'ECF_DGII_REQUIREMENTS_PENDING',
              message: 'Faltan requisitos obligatorios de habilitación (2).',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Pendientes y bloqueos'), findsOneWidget);
    expect(find.textContaining('Faltan requisitos obligatorios'), findsWidgets);
  });

  testWidgets('evidencia registrada: oficial y manual no se confunden', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'IN_CERTIFICATION',
          evidence: const [
            EcfDgiiEvidenceView(
              id: 'e1',
              source: 'OFFICIAL_DOCUMENT',
              isOfficialDocument: true,
              kind: 'resolucion',
              fileName: 'resolucion-dgii.pdf',
            ),
            EcfDgiiEvidenceView(
              id: 'e2',
              source: 'MANUAL_DECLARATION',
              isOfficialDocument: false,
              kind: 'nota-interna',
            ),
          ],
        ),
      ),
    );

    expect(find.text('resolucion-dgii.pdf'), findsOneWidget);
    expect(find.textContaining('Documento oficial'), findsOneWidget);
    expect(find.text('Evidencia del expediente'), findsOneWidget);
    expect(find.text('nota-interna'), findsNothing);
    expect(find.textContaining('Declaración manual'), findsOneWidget);
  });

  testWidgets('usuario sin permisos: no puede modificar nada', (tester) async {
    await _pumpPage(
      tester,
      _harness(
        user: _userWithoutPermission(),
        view: _view(
          state: 'IN_PROGRESS',
          blockers: const [
            EcfDgiiBlocker(
              code: 'ECF_DGII_REQUIREMENTS_PENDING',
              message: 'Faltan requisitos obligatorios de habilitación (14).',
            ),
          ],
        ),
      ),
    );

    // Ve el estado (lectura permitida)…
    expect(find.text('En revisión interna'), findsOneWidget);
    expect(find.text('Solicitud'), findsOneWidget);
    expect(find.text('Pruebas'), findsOneWidget);
    expect(find.text('Certificación'), findsOneWidget);
    expect(find.text('Activación electrónica'), findsNothing);
    // …sin ver el lenguaje interno de bloqueo ni el conteo de requisitos.
    expect(find.textContaining('requisitos obligatorios'), findsNothing);
    expect(find.textContaining('obligatorios '), findsNothing);
    expect(find.text('Bloqueado'), findsNothing);
    expect(find.text('Pendientes y bloqueos'), findsNothing);
    // Nunca se declara una autorización oficial que no existe.
    expect(find.text('Autorización oficial registrada'), findsNothing);
    // …pero no puede avanzar el proceso ni registrar nada.
    expect(find.text('Avanzar estado'), findsNothing);
    expect(find.text('Registrar evidencia'), findsNothing);
    expect(find.text('Registrar autorización recibida'), findsNothing);
    expect(find.text('Observaciones'), findsNothing);
  });

  testWidgets(
    'empresa distinta: solo muestra los datos de la empresa de la sesión',
    (tester) async {
      await _pumpPage(
        tester,
        _harness(
          user: _adminUser(companyId: 'company-b'),
          view: _view(
            companyId: 'company-b',
            observations: 'Solo de la empresa B',
          ),
        ),
      );

      expect(find.text('Solo de la empresa B'), findsOneWidget);
      // El identificador de empresa no se proyecta en la interfaz: el ámbito lo
      // impone el backend desde la sesión.
      expect(find.textContaining('company-b'), findsNothing);
    },
  );

  testWidgets('error HTTP: ofrece reintentar sin romper la pantalla', (
    tester,
  ) async {
    await _pumpPage(tester, _harness(error: Exception('boom')));

    expect(
      find.text('No se pudo cargar la habilitación DGII.'),
      findsOneWidget,
    );
    expect(find.text('Comprueba la conexión con el servidor.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('reintento: vuelve a consultar y no deja el fallo sin manejar', (
    tester,
  ) async {
    var reads = 0;
    await _pumpPage(
      tester,
      _harness(error: Exception('boom'), onRead: () => reads++),
    );
    expect(reads, 1);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(reads, greaterThan(1));
    // El backend sigue fallando: la pantalla lo dice y no lanza nada.
    expect(
      find.text('No se pudo cargar la habilitación DGII.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('aprobación oficial no verificada: se declara y no se aprueba', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'IN_CERTIFICATION',
          authorizationSource: 'MANUAL_OPERATOR_DECLARATION',
          officialAuthorization: false,
          officialBlockers: const [
            EcfDgiiBlocker(
              code: 'ECF_DGII_STATE_NOT_APPROVED',
              message: 'El seguimiento interno no está en estado aprobado.',
            ),
            EcfDgiiBlocker(
              code: 'ECF_DGII_AUTHORIZATION_SOURCE_NOT_OFFICIAL',
              message:
                  'La fuente registrada no es un registro oficial de la DGII; '
                  'no autoriza emisión.',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Autorización oficial registrada'), findsNothing);
    expect(find.text('MANUAL_OPERATOR_DECLARATION'), findsNothing);

    // Anti-falsificación: el diálogo de avance NUNCA ofrece aprobar.
    await tester.tap(find.text('Avanzar estado'));
    await tester.pumpAndSettle();
    expect(find.text('Avanzar el seguimiento interno'), findsOneWidget);
    // Desde IN_CERTIFICATION el backend solo permite corrección.
    expect(find.text('Requiere corrección'), findsOneWidget);
    expect(find.textContaining('Aprobado'), findsNothing);
    expect(find.textContaining('APPROVED'), findsNothing);
  });

  testWidgets('emisión real bloqueada: se declara que no está implementada', (
    tester,
  ) async {
    await _pumpPage(tester, _harness(user: _adminUser()));

    expect(find.text('Autorización para emitir'), findsOneWidget);
    expect(find.text('Emisión real'), findsOneWidget);
    expect(find.text('Bloqueada'), findsOneWidget);
    expect(find.text('Emisión real implementada'), findsOneWidget);
    expect(find.textContaining('no está implementada'), findsOneWidget);
  });

  testWidgets('el cliente no ve referencias de constancia DGII', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
        ),
      ),
      technical: false,
    );

    expect(find.text('Registrar referencia de constancia DGII'), findsNothing);
    expect(find.text('Ver cómo presentar'), findsNothing);
  });

  testWidgets('disposición móvil: se ve sin desbordes', (tester) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(state: 'IN_PROGRESS'),
      ),
      size: const Size(390, 844),
    );

    expect(find.text('En revisión interna'), findsOneWidget);
    expect(find.text('Solicitud'), findsOneWidget);
    expect(find.text('Pruebas'), findsOneWidget);
    expect(find.text('Certificación'), findsOneWidget);
    // Un desbordamiento de layout se reporta como excepción en las pruebas.
    expect(tester.takeException(), isNull);
  });

  testWidgets('revisar una evidencia exige el permiso específico', (
    tester,
  ) async {
    final evidence = [
      const EcfDgiiEvidenceView(
        id: 'e1',
        source: 'OFFICIAL_DOCUMENT',
        isOfficialDocument: true,
        kind: 'resolucion',
        fileName: 'resolucion.pdf',
        reviewStatus: 'PENDING',
      ),
    ];

    // Con permiso de GESTIÓN pero sin el de revisión: el botón no existe y se
    // explica por qué, en vez de ofrecer una acción que el backend rechazará.
    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {'manageEcfOnboarding': true}),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
          evidence: evidence,
        ),
      ),
    );
    expect(find.byIcon(Icons.rule), findsNothing);
    expect(
      find.text('La revisión de evidencias requiere el permiso específico.'),
      findsOneWidget,
    );

    // Con el permiso de revisión, el botón aparece.
    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {
          'manageEcfOnboarding': true,
          'reviewEcfDgiiEvidence': true,
        }),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
          evidence: evidence,
        ),
      ),
    );
    expect(find.byIcon(Icons.rule), findsOneWidget);
  });

  testWidgets('el diálogo de revisión exige motivo al rechazar', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {
          'manageEcfOnboarding': true,
          'reviewEcfDgiiEvidence': true,
        }),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
          evidence: const [
            EcfDgiiEvidenceView(
              id: 'e1',
              source: 'MANUAL_DECLARATION',
              isOfficialDocument: false,
              kind: 'nota',
              reviewStatus: 'PENDING',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.rule));
    await tester.pumpAndSettle();

    // El diálogo declara que revisar no autoriza nada.
    expect(find.textContaining('no autoriza nada por sí sola'), findsOneWidget);

    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Un rechazo necesita un motivo para ser auditable.'),
      findsOneWidget,
    );
  });

  testWidgets('revisar no autoriza: la fila lo dice de forma explícita', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _certificateResolvedProgress(),
          evidence: const [
            EcfDgiiEvidenceView(
              id: 'e1',
              source: 'MANUAL_DECLARATION',
              isOfficialDocument: false,
              kind: 'nota',
              reviewStatus: 'REVIEWED',
            ),
            EcfDgiiEvidenceView(
              id: 'e2',
              source: 'OFFICIAL_DOCUMENT',
              isOfficialDocument: true,
              kind: 'resolucion',
              reviewStatus: 'REVIEWED',
              supportsOfficialAuthorization: true,
            ),
          ],
        ),
      ),
    );

    // Origen y revisión se muestran por separado.
    expect(find.textContaining('Declaración manual'), findsOneWidget);
    expect(find.textContaining('Documento oficial'), findsOneWidget);
    expect(find.text('Revisión: Revisada'), findsNWidgets(2));
    // Y la consecuencia se declara sin adornos.
    expect(
      find.text('No puede sustentar una autorización oficial.'),
      findsOneWidget,
    );
    expect(
      find.text('Puede sustentar una autorización oficial.'),
      findsOneWidget,
    );
  });

  testWidgets('el seguimiento interno se muestra pero no finge progreso', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'TESTS_PENDING',
          progress: _progress(
            requirements: const [
              EcfDgiiRequirementProgress(
                key: 'SET_TESTS',
                label: 'Pruebas del SET',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
                tracking: EcfDgiiRequirementTracking(
                  status: 'COMPLETED',
                  note: 'Enviadas el 15',
                  dueDate: '2026-11-30',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Seguimiento interno: Completado · vence 2026-11-30'),
      findsOneWidget,
    );
    expect(find.text('Enviadas el 15'), findsOneWidget);
    // El requisito sigue SIN resolver: la libreta no es el progreso.
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('el botón de seguimiento requiere permiso de gestión', (
    tester,
  ) async {
    final progress = _progress(
      requirements: const [
        EcfDgiiRequirementProgress(
          key: 'SET_TESTS',
          label: 'Pruebas del SET',
          mandatory: true,
          automatable: false,
          status: 'PENDING',
          resolved: false,
        ),
      ],
    );

    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {'viewEcfDgiiHabilitation': true}),
        view: _view(state: 'TESTS_PENDING', progress: progress),
      ),
    );
    expect(find.text('Avanzado'), findsNothing);
    expect(find.byTooltip('Registrar seguimiento interno'), findsNothing);
    // Sin permiso de gestión no hay bloque técnico: no se ofrece una interfaz
    // que el servidor rechazaría.
    expect(find.text('Detalle técnico'), findsNothing);

    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {'manageEcfOnboarding': true}),
        view: _view(state: 'TESTS_PENDING', progress: progress),
      ),
    );
    expect(find.text('Pruebas del SET'), findsOneWidget);
    expect(find.byTooltip('Registrar seguimiento interno'), findsOneWidget);
  });

  testWidgets('el diálogo de seguimiento valida el formato de la fecha', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          progress: _progress(
            requirements: const [
              EcfDgiiRequirementProgress(
                key: 'SET_TESTS',
                label: 'Pruebas del SET',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Registrar seguimiento interno'));
    await tester.pumpAndSettle();
    expect(find.text('Seguimiento del requisito'), findsOneWidget);
    expect(
      find.textContaining('ni acredita nada ante la DGII'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).first, '30/11/2026');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Usa el formato AAAA-MM-DD'), findsOneWidget);
  });

  testWidgets('disposición estrecha: los elementos nuevos no desbordan', (
    tester,
  ) async {
    // Se recorren de verdad las tarjetas con botón de revisión, con seguimiento
    // interno y con las tres acciones de evidencia, en el ancho de un móvil.
    await _pumpPage(
      tester,
      _harness(
        user: _adminUser(),
        view: _view(
          state: 'IN_CERTIFICATION',
          progress: _progress(
            requirements: const [
              EcfDgiiRequirementProgress(
                key: 'SET_TESTS',
                label: 'Pruebas del SET',
                mandatory: true,
                automatable: false,
                status: 'PENDING',
                resolved: false,
                tracking: EcfDgiiRequirementTracking(
                  status: 'BLOCKED',
                  note: 'Esperando respuesta del proveedor',
                  dueDate: '2026-11-30',
                ),
              ),
            ],
          ),
          evidence: const [
            EcfDgiiEvidenceView(
              id: 'e1',
              source: 'OFFICIAL_DOCUMENT',
              isOfficialDocument: true,
              kind: 'resolucion',
              fileName: 'resolucion-dgii.pdf',
              reviewStatus: 'PENDING',
            ),
          ],
        ),
      ),
      size: const Size(360, 3200),
    );

    expect(find.text('Pruebas del SET'), findsOneWidget);
    expect(find.text('Esperando respuesta del proveedor'), findsOneWidget);
    expect(find.byTooltip('Registrar seguimiento interno'), findsOneWidget);
    expect(find.byTooltip('Revisar evidencia'), findsOneWidget);
    // Un desbordamiento de layout se reporta como excepción en las pruebas.
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1366.0]) {
    testWidgets('Atrás del shell cierra el formulario fiscal a ${width.toInt()} px', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _harness(
          view: _view(state: 'NOT_STARTED'),
          settings: CompanySettings.empty(),
        ),
        size: Size(width, 1000),
        step: null,
        technical: false,
      );
      await tester.tap(find.text('Comenzar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completar datos').first);
      await tester.pumpAndSettle();
      expect(find.byType(EcfFiscalDataContent), findsOneWidget);
      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EcfDgiiHabilitationPage)),
      );
      container.read(desktopShellRouteActionsProvider)?.onBack?.call();
      await tester.pumpAndSettle();
      expect(find.byType(EcfFiscalDataContent), findsNothing);
      expect(find.text('Preparación'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dato fiscal válido permanece visible con foco y se oculta al salir',
    (tester) async {
      await _pumpPage(
        tester,
        _harness(
          view: _view(state: 'NOT_STARTED'),
          settings: CompanySettings.empty(),
        ),
        step: null,
        technical: false,
      );
      await tester.tap(find.text('Comenzar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completar datos').first);
      await tester.pumpAndSettle();
      final rnc = find.byKey(const ValueKey('fiscal_field_rnc'));
      final address = find.byKey(const ValueKey('fiscal_field_address'));
      await tester.enterText(rnc, '131000001');
      await tester.pump();
      expect(rnc, findsOneWidget);
      expect(tester.widget<TextField>(rnc).focusNode!.hasFocus, isTrue);
      await tester.tap(address);
      await tester.pumpAndSettle();
      expect(rnc, findsNothing);
      expect(address, findsOneWidget);
    },
  );

  testWidgets('no solicita constancia DGII antes de presentar el expediente', (
    tester,
  ) async {
    await _pumpPage(tester, _harness());
    expect(find.text('Registrar referencia de constancia DGII'), findsNothing);
    expect(find.text('Ver cómo presentar'), findsNothing);
  });

  testWidgets('recarga fiscal asíncrona respeta texto, foco y selección', (
    tester,
  ) async {
    final pending = Completer<CompanySettings>();
    var reads = 0;
    final initial = CompanySettings.empty();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companySettingsProvider.overrideWith((ref) {
            reads++;
            return reads == 1 ? Future.value(initial) : pending.future;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: EcfFiscalDataContent(compact: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('fiscal_field_rnc'));
    await tester.enterText(field, '131000001');
    await tester.pump();
    final before = tester.widget<TextField>(field);
    final selection = before.controller!.selection;
    final container = ProviderScope.containerOf(tester.element(field));
    container.invalidate(companySettingsProvider);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '131000001');
    pending.complete(initial.copyWith(rnc: '999999999'));
    await tester.pumpAndSettle();
    final after = tester.widget<TextField>(field);
    expect(after.controller!.text, '131000001');
    expect(after.controller!.selection, selection);
    expect(after.focusNode!.hasFocus, isTrue);
  });
}
