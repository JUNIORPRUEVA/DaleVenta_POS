import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_platform_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_habilitation_page.dart';
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

EcfDgiiHabilitationView _view({
  String companyId = 'company-a',
  String state = 'NOT_STARTED',
  String? observations,
  bool officialAuthorization = false,
  List<EcfDgiiBlocker> officialBlockers = const [],
  String authorizationSource = 'NONE',
  DateTime? authorizedAt,
  EcfDgiiProgress? progress,
  List<EcfDgiiEvidenceView> evidence = const [],
  EcfDgiiEmissionState emission = _noAuthorization,
  List<EcfDgiiBlocker> blockers = const [],
}) {
  return EcfDgiiHabilitationView(
    companyId: companyId,
    state: state,
    observations: observations,
    officialAuthorization: officialAuthorization,
    officialAuthorizationBlockers: officialBlockers,
    authorizationSource: authorizationSource,
    authorizedAt: authorizedAt,
    moduleEnabled: true,
    certificationStatus: 'NOT_STARTED',
    providerIntegrationConfigured: false,
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
        return view ?? _view();
      }),
      ecfDgiiHistoryProvider.overrideWith((ref) async => history),
      // La pantalla pregunta al backend si la sesión es personal de plataforma.
      // La prueba fija la respuesta: sin esto quedaría una petición de red real
      // con su temporizador pendiente al desmontar el árbol.
      ecfPlatformStaffProvider.overrideWith((ref) async => false),
      companySettingsProvider.overrideWith(
        (ref) async => CompanySettings.empty(),
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
/// Es necesario porque el `ListView` construye sus hijos bajo demanda: en una
/// ventana pequeña las tarjetas inferiores no existen todavía, y la prueba
/// fallaría por un motivo que no es un defecto del producto. La disposición
/// móvil se cubre con su propia prueba.
Future<void> _pumpPage(
  WidgetTester tester,
  Widget harness, {
  Size size = const Size(1400, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empresa sin habilitación: no hay autorización oficial', (
    tester,
  ) async {
    await _pumpPage(tester, _harness(user: _adminUser()));

    expect(find.text('Sin autorización oficial de la DGII'), findsOneWidget);
    expect(find.text('Sin iniciar'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // Los datos fiscales sin registrar se declaran, no se inventan.
    expect(find.text('Sin registrar'), findsWidgets);
    // Nunca se insinúa que la emisión esté permitida.
    expect(find.text('Bloqueada'), findsOneWidget);
  });

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

    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('36%'), findsOneWidget);
    expect(find.textContaining('5 de 14 requisitos'), findsOneWidget);
    expect(find.textContaining('obligatorios 5/13'), findsOneWidget);
    expect(find.text('Datos fiscales de la empresa'), findsOneWidget);
    expect(find.text('Pruebas del SET'), findsOneWidget);
    expect(find.text('Pendiente el set de pruebas'), findsWidgets);
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
    expect(find.textContaining('Faltan requisitos obligatorios'), findsOneWidget);
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
    expect(find.text('nota-interna'), findsOneWidget);
    expect(find.textContaining('Declaración manual'), findsOneWidget);
  });

  testWidgets('usuario sin permisos: no puede modificar nada', (tester) async {
    await _pumpPage(
      tester,
      _harness(user: _userWithoutPermission(), view: _view(state: 'IN_PROGRESS')),
    );

    // Ve el estado (lectura permitida)…
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('Sin autorización oficial de la DGII'), findsOneWidget);
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

    expect(find.text('No se pudo cargar la habilitación DGII.'), findsOneWidget);
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
    expect(find.text('No se pudo cargar la habilitación DGII.'), findsOneWidget);
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

    expect(find.text('Sin autorización oficial de la DGII'), findsOneWidget);
    expect(find.textContaining('no autoriza emisión'), findsOneWidget);
    // La fuente declarada se muestra tal cual, para que no se confunda.
    expect(find.text('MANUAL_OPERATOR_DECLARATION'), findsOneWidget);

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

  testWidgets('el diálogo de evidencia rechaza una referencia inválida', (
    tester,
  ) async {
    await _pumpPage(tester, _harness(user: _adminUser()));

    await tester.tap(find.text('Registrar evidencia'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'resolucion');
    await tester.enterText(fields.at(1), 'http://no-valido');
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Debe empezar por'), findsOneWidget);
  });

  testWidgets('disposición móvil: se ve sin desbordes', (tester) async {
    await _pumpPage(
      tester,
      _harness(user: _adminUser(), view: _view(state: 'IN_PROGRESS')),
      size: const Size(390, 844),
    );

    expect(find.text('Sin autorización oficial de la DGII'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
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
        user: _userWith(const {'manageEcfDgiiRequirements': true}),
        view: _view(evidence: evidence),
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
        user: _userWith(const {'reviewEcfDgiiEvidence': true}),
        view: _view(evidence: evidence),
      ),
    );
    expect(find.byIcon(Icons.rule), findsOneWidget);
  });

  testWidgets('el diálogo de revisión exige motivo al rechazar', (tester) async {
    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {'reviewEcfDgiiEvidence': true}),
        view: _view(
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
        view: _view(progress: progress),
      ),
    );
    expect(find.text('Pruebas del SET'), findsOneWidget);
    expect(find.byTooltip('Registrar seguimiento interno'), findsNothing);

    await _pumpPage(
      tester,
      _harness(
        user: _userWith(const {'manageEcfDgiiRequirements': true}),
        view: _view(progress: progress),
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
    expect(find.textContaining('ni acredita nada ante la DGII'), findsOneWidget);

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
}
