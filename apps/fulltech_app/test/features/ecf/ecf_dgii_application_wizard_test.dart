import 'dart:async';

import 'package:dio/dio.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_application_repository.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dgii_application_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests del ASISTENTE de postulación.
///
/// Se comprueba el comportamiento que el usuario percibe: el formulario, la
/// recuperación del borrador, el autoguardado con su debounce, los tres estados
/// de guardado, el reintento y la adopción de la versión del servidor cuando hay
/// conflicto. No se sustituye por pruebas de repositorio: aquí se pulsa y se
/// escribe de verdad sobre el árbol de widgets.

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _user({String role = 'ADMIN', String companyId = 'company-a'}) =>
    UserModel(
      id: 'user-a',
      email: 'admin@test.local',
      nombreCompleto: 'Admin',
      telefono: '',
      role: role,
      companyId: companyId,
      companyName: 'FULLTECH, SRL',
    );

const _completeDraft = <String, dynamic>{
  'company': {
    'rnc': '131000001',
    'legalName': 'Empresa Sintética SRL',
    'address': 'Calle Sintética 1',
  },
  'representative': {
    'fullName': 'Ana Pérez',
    'identification': '001-0000000-1',
    'email': 'ana@example.test',
  },
};

EcfDgiiHabilitationView _view() => const EcfDgiiHabilitationView(
  companyId: 'company-a',
  state: 'NOT_STARTED',
  officialAuthorization: false,
  officialAuthorizationBlockers: <EcfDgiiBlocker>[],
  authorizationSource: 'NONE',
  moduleEnabled: true,
  certificationStatus: 'NOT_STARTED',
  providerIntegrationConfigured: false,
  progress: EcfDgiiProgress.empty,
  evidence: <EcfDgiiEvidenceView>[],
  emission: EcfDgiiEmissionState(
    realEmissionAuthorized: false,
    simulatedDispatchAuthorized: false,
    productionEmissionImplemented: false,
  ),
  blockers: <EcfDgiiBlocker>[],
);

/// Repositorio falso: controla qué devuelve el servidor y cuándo falla.
class _FakeApplicationRepository extends EcfApplicationRepository {
  _FakeApplicationRepository({required this.initial}) : super(Dio());

  final EcfApplicationDraft initial;
  EcfApplicationDraft? persisted;

  int saves = 0;
  int loads = 0;
  int submits = 0;
  String? lastConsentVersion;
  Object? failSubmitWith;
  Completer<void>? submitGate;
  int? lastExpectedRevision;
  Map<String, dynamic>? lastPayload;

  /// Si no es `null`, el siguiente guardado lanza este error.
  Object? failSaveWith;
  Object? failLoadWith;

  /// Si no es `null`, el guardado espera a que se complete esta compuerta.
  /// Permite observar el estado «Guardando…» de forma determinista en vez de
  /// depender de que la respuesta tarde.
  Completer<void>? saveGate;

  /// Datos que devuelve el servidor tras un conflicto.
  EcfApplicationDraft? serverAfterConflict;

  @override
  Future<EcfApplicationDraft> draft() async {
    loads++;
    final failure = failLoadWith;
    if (failure != null) {
      failLoadWith = null;
      throw failure;
    }
    return serverAfterConflict ?? persisted ?? initial;
  }

  @override
  Future<EcfApplicationDraft> saveDraft(
    Map<String, dynamic> payload, {
    int? expectedRevision,
  }) async {
    saves++;
    lastExpectedRevision = expectedRevision;
    lastPayload = payload;
    final gate = saveGate;
    if (gate != null) await gate.future;
    final failure = failSaveWith;
    if (failure != null) {
      failSaveWith = null;
      throw failure;
    }
    persisted = EcfApplicationDraft(
      state: 'NOT_STARTED',
      draft: payload,
      missingFields: const <String>[],
      draftUpdatedAt: DateTime.now(),
      draftRevision: (expectedRevision ?? 0) + 1,
      currentSnapshotVersion: 0,
      consentVersion: null,
      requiredConsentVersion: 'v-test',
      consentPurpose: initial.consentPurpose,
    );
    return persisted!;
  }

  @override
  Future<EcfApplicationSubmitResult> submit({
    required String consentVersion,
    required Map<String, dynamic> payload,
  }) async {
    submits++;
    lastConsentVersion = consentVersion;
    if (submitGate != null) await submitGate!.future;
    if (failSubmitWith != null) throw failSubmitWith!;
    return const EcfApplicationSubmitResult(
      idempotent: false,
      version: 1,
      state: 'APPLICATION_PENDING',
    );
  }
}

EcfApplicationDraft _draft({
  Map<String, dynamic>? data,
  Map<String, dynamic> suggested = const {},
  int revision = 0,
  List<String> missing = const <String>[],
  String consentPurpose = 'Autorizo el uso de los datos.',
}) {
  return EcfApplicationDraft(
    state: 'NOT_STARTED',
    draft: data,
    suggested: suggested,
    missingFields: missing,
    draftUpdatedAt: null,
    draftRevision: revision,
    currentSnapshotVersion: 0,
    consentVersion: null,
    requiredConsentVersion: 'v-test',
    consentPurpose: consentPurpose,
  );
}

Widget _harness(
  _FakeApplicationRepository repository, {
  UserModel? user,
  bool embedded = false,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      ecfDgiiHabilitationProvider.overrideWith((ref) async => _view()),
      ecfApplicationRepositoryProvider.overrideWithValue(repository),
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: user ?? _user(),
            hasSessionHint: true,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: embedded
          ? const Scaffold(
              body: SizedBox(
                height: 640,
                child: EcfDgiiApplicationWizard(embedded: true),
              ),
            )
          : const EcfDgiiApplicationWizard(),
    ),
  );
}

void main() {
  Future<void> openConsent(WidgetTester tester) async {
    if (find.widgetWithText(FilledButton, 'Continuar').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Enviar a revisión interna'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Enviar a revisión interna'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enviar a revisión interna'),
    );
    await tester.pumpAndSettle();
  }

  for (final width in <double>[320, 390, 768, 1366]) {
    testWidgets('consentimiento explícito y adaptable a ${width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _FakeApplicationRepository(
        initial: _draft(data: _completeDraft),
      );
      await tester.pumpWidget(_harness(repository, embedded: true));
      await tester.pumpAndSettle();
      await openConsent(tester);
      expect(
        find.text('Autorización y consentimiento para revisión interna'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Lee y acepta las condiciones para continuar con la revisión de tu expediente.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'He leído y acepto esta autorización para la revisión interna de mi expediente',
        ),
        findsOneWidget,
      );
      final authorize = find.widgetWithText(
        FilledButton,
        'Autorizo y envío a revisión interna',
      );
      expect(tester.widget<FilledButton>(authorize).onPressed, isNull);
      expect(repository.submits, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repository.submits, 0);
      await openConsent(tester);
      expect(tester.widget<FilledButton>(authorize).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(authorize).onPressed, isNotNull);
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(repository.submits, 1);
      expect(repository.lastConsentVersion, 'v-test');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('separa los dos párrafos y la nota legal del servidor', (
    tester,
  ) async {
    const purpose =
        'Párrafo de autorización.\n\n'
        'Párrafo sobre el alcance de la revisión.\n\n'
        'Esta aceptación autoriza únicamente la revisión interna del expediente. No constituye presentación oficial ante la DGII ni habilitación para emitir comprobantes electrónicos';
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft, consentPurpose: purpose),
    );
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await openConsent(tester);
    expect(find.text('Párrafo de autorización.'), findsOneWidget);
    expect(
      find.text('Párrafo sobre el alcance de la revisión.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Esta aceptación autoriza únicamente la revisión interna del expediente. No constituye presentación oficial ante la DGII ni habilitación para emitir comprobantes electrónicos',
      ),
      findsOneWidget,
    );
    expect(find.text('Versión del texto: v-test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el modal se ajusta al contenido y no reserva alto fijo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeApplicationRepository(
      initial: _draft(
        data: _completeDraft,
        consentPurpose: 'Autorizo el uso de los datos de mi empresa.',
      ),
    );
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await openConsent(tester);
    final box = tester.getSize(
      find.byKey(const ValueKey('ecf_consent_dialog_box')),
    );
    // Un consentimiento corto no debe reservar el alto máximo del diálogo
    // (antes el modal tenía una altura fija de 600-680 px).
    expect(box.height, lessThan(520));
    expect(box.height, greaterThan(120));
    expect(box.width, lessThanOrEqualTo(560));
    // Las acciones siguen visibles sin hacer scroll.
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Autorizo y envío a revisión interna'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mantiene las acciones visibles en un móvil de 320 × 568', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft),
    );
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await openConsent(tester);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Autorizo y envío a revisión interna'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doble envío y error del servidor no presentan éxito falso', (
    tester,
  ) async {
    final repository =
        _FakeApplicationRepository(initial: _draft(data: _completeDraft))
          ..submitGate = Completer<void>()
          ..failSubmitWith = Exception('error de prueba');
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await openConsent(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Autorizo y envío a revisión interna'),
    );
    await tester.pump();
    expect(repository.submits, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviar a revisión interna'),
          )
          .onPressed,
      isNull,
    );
    repository.submitGate!.complete();
    await tester.pumpAndSettle();
    expect(repository.submits, 1);
    expect(
      find.textContaining('Expediente enviado a revisión interna.'),
      findsNothing,
    );
    expect(
      find.text('No se pudo completar la operación. Inténtalo de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'un fallo al cargar bloquea la edición hasta recuperar el borrador',
    (tester) async {
      final repository = _FakeApplicationRepository(
        initial: _draft(data: _completeDraft),
      )..failLoadWith = Exception('sin red');
      await tester.pumpWidget(_harness(repository, embedded: true));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar carga'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(repository.saves, 0);

      await tester.tap(find.text('Reintentar carga'));
      await tester.pumpAndSettle();
      expect(repository.loads, 2);
      expect(find.text('Reintentar carga'), findsNothing);
      expect(
        find.text(
          'Los datos de tu empresa están registrados. Puedes continuar.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('el paso de datos resume un expediente completo', (tester) async {
    await tester.pumpWidget(
      _harness(
        _FakeApplicationRepository(initial: _draft(data: _completeDraft)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Los datos de tu empresa están registrados. Puedes continuar.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Datos'), findsOneWidget); // cabecera de pasos
    expect(find.text('Enviar'), findsOneWidget);
  });

  testWidgets('recupera el borrador guardado al abrir la pantalla', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft, revision: 4),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(repository.loads, 1);
    await tester.tap(find.text('Revisar datos'));
    await tester.pump();
    expect(
      find.widgetWithText(TextField, 'Empresa Sintética SRL'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Calle Sintética 1'), findsOneWidget);
    expect(find.widgetWithText(TextField, '001-0000000-1'), findsOneWidget);
  });

  testWidgets('autoguarda a los 800 ms y muestra guardando y guardado', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    repository.saveGate = Completer<void>();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'RNC'), '131000777');
    await tester.pump();

    // Antes del debounce no se ha guardado nada.
    await tester.pump(const Duration(milliseconds: 700));
    expect(repository.saves, 0);

    // Al cumplirse el debounce arranca el guardado y el estado es visible
    // mientras la respuesta sigue en vuelo.
    await tester.pump(const Duration(milliseconds: 150));
    expect(repository.saves, 1);
    expect(find.text('Guardando…'), findsOneWidget);

    // Al resolverse la petición pasa a guardado.
    repository.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Guardado en el servidor'), findsOneWidget);
    expect(repository.lastPayload?['company']['rnc'], '131000777');
  });

  testWidgets('un error de guardado se muestra con opción de reintentar', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    repository.failSaveWith = DioException(
      requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
        statusCode: 500,
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'RNC'), '131000888');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo guardar el borrador'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    // Reintento real: vuelve a llamar al servidor y queda guardado.
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repository.saves, 2);
    expect(find.text('Guardado en el servidor'), findsOneWidget);
  });

  testWidgets('ante un conflicto conserva la edición con foco y avisa', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft, revision: 2),
    );
    repository.failSaveWith = DioException(
      requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
        statusCode: 409,
        data: {'message': 'ECF_DGII_DRAFT_CONFLICT', 'currentRevision': 3},
      ),
      message: 'ECF_DGII_DRAFT_CONFLICT',
    );
    repository.serverAfterConflict = _draft(
      data: {
        ..._completeDraft,
        'company': {
          ...(_completeDraft['company'] as Map<String, dynamic>),
          'address': 'Dirección del otro dispositivo',
        },
      },
      revision: 3,
    );

    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar datos'));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Dirección fiscal'),
      'Dirección local',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // Una respuesta asíncrona no reemplaza el texto bajo el cursor.
    expect(find.widgetWithText(TextField, 'Dirección local'), findsOneWidget);
    expect(find.text('Dirección del otro dispositivo'), findsNothing);
    expect(find.textContaining('otro dispositivo'), findsWidgets);
    expect(repository.saves, 1);
  });

  testWidgets('el envío no puede ocurrir mientras un guardado falla', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    repository.failSaveWith = DioException(
      requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/ecf/dgii/application/draft'),
        statusCode: 500,
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'RNC'), '131000999');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // Con el guardado en error, el asistente sigue en el paso de datos y no
    // existe ningún camino hasta el envío.
    expect(
      find.text('Completa o corrige los datos necesarios para continuar.'),
      findsOneWidget,
    );
    expect(repository.submits, 0);
  });

  testWidgets('reutiliza cinco datos fiscales y pide solo el correo', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(
        suggested: {
          'company': {
            'rnc': '131000001',
            'legalName': 'Empresa Sintética SRL',
            'address': 'Calle Sintética 1',
          },
          'representative': {
            'fullName': 'Ana Pérez',
            'identification': '001-0000000-1',
          },
        },
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Correo electrónico'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Necesitamos el correo electrónico del representante para continuar.',
      ),
      findsOneWidget,
    );
    expect(repository.saves, 0);
    await tester.enterText(find.byType(TextField), 'ana@example.test');
    await tester.pump(const Duration(milliseconds: 900));
    expect(repository.lastPayload?['company']['rnc'], '131000001');
    expect(
      repository.lastPayload?['representative']['email'],
      'ana@example.test',
    );
  });

  testWidgets('una diferencia exige elegir antes de continuar', (tester) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(
        data: _completeDraft,
        suggested: {
          'company': {'address': 'Calle Fiscal 2'},
        },
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.text('Datos fiscales: Calle Fiscal 2'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Conservar expediente'));
    await tester.pump();
    expect(find.text('Datos fiscales: Calle Fiscal 2'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('datos parciales muestran solo campos ausentes', (tester) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(
        suggested: {
          'company': {'rnc': '131000001', 'legalName': 'Empresa Sintética SRL'},
          'representative': {'fullName': 'Ana Pérez'},
        },
      ),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.widgetWithText(TextField, 'Dirección fiscal'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cédula o identificación'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Correo electrónico'),
      findsOneWidget,
    );
    expect(find.textContaining('company.rnc'), findsNothing);
  });

  testWidgets('un usuario sin permiso no puede guardar el borrador', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    await tester.pumpWidget(_harness(repository, user: _user(role: 'CAJERO')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'RNC')).readOnly,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'))
          .onPressed,
      isNull,
    );
    expect(repository.saves, 0);
  });

  testWidgets(
    'el formulario integrado no agrega una segunda barra de progreso',
    (tester) async {
      final repository = _FakeApplicationRepository(
        initial: _draft(data: _completeDraft),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(repository, embedded: true));
      await tester.pumpAndSettle();
      expect(find.text('Postulación DGII'), findsNothing);
      expect(find.text('Datos'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Continuar'), findsOneWidget);
      expect(find.text('Enviar a revisión interna'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Enviar a revisión interna'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.widgetWithText(FilledButton, 'Enviar a revisión interna'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('el formulario integrado pide solo el correo faltante', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(
        suggested: {
          'company': _completeDraft['company'] as Map<String, dynamic>,
          'representative': {
            'fullName': 'Ana Pérez',
            'identification': '001-0000000-1',
          },
        },
      ),
    );
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Correo electrónico'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Guardar correo'), findsOneWidget);
  });

  testWidgets(
    'escritura lenta y rápida conserva foco, texto y selección hasta salir',
    (tester) async {
      final repository = _FakeApplicationRepository(
        initial: _draft(
          suggested: {
            'company': _completeDraft['company'] as Map<String, dynamic>,
            'representative': {
              'fullName': 'Ana Pérez',
              'identification': '001-0000000-1',
            },
          },
        ),
      );
      await tester.pumpWidget(_harness(repository, embedded: true));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('application_field_representative.email'),
      );
      await tester.tap(field);
      await tester.enterText(field, 'ana@');
      await tester.pump(const Duration(milliseconds: 900));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'ana@example.test');
      await tester.pump(const Duration(milliseconds: 900));
      expect(field, findsOneWidget);
      final input = tester.widget<TextField>(field);
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.text, 'ana@example.test');
      expect(input.controller!.selection.baseOffset, 16);
      input.focusNode!.unfocus();
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(
        repository.persisted?.read('representative.email'),
        'ana@example.test',
      );
    },
  );

  testWidgets('campo inválido permanece al pasar a otro campo', (tester) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    final rnc = find.byKey(const ValueKey('application_field_company.rnc'));
    final name = find.byKey(
      const ValueKey('application_field_company.legalName'),
    );
    await tester.enterText(rnc, '123');
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(rnc, findsOneWidget);
    expect(tester.widget<TextField>(rnc).controller!.text, '123');
  });

  testWidgets('respuesta de guardado en vuelo no borra una edición posterior', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    repository.saveGate = Completer<void>();
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    final rnc = find.byKey(const ValueKey('application_field_company.rnc'));
    await tester.enterText(rnc, '131000001');
    await tester.pump(const Duration(milliseconds: 850));
    expect(repository.saves, 1);
    await tester.enterText(rnc, '131000002');
    repository.saveGate!.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<TextField>(rnc).controller!.text, '131000002');
    await tester.pump(const Duration(milliseconds: 850));
    expect(repository.saves, 2);
    expect(repository.persisted?.read('company.rnc'), '131000002');
  });

  testWidgets('reabrir expediente recupera el borrador persistido', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(initial: _draft());
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('application_field_company.rnc')),
      '131000001',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
    await tester.tap(find.text('Revisar datos'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('application_field_company.rnc')),
          )
          .controller!
          .text,
      '131000001',
    );
  });

  testWidgets('Atrás desde documentos vuelve a datos sin perder el borrador', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft),
    );
    await tester.pumpWidget(_harness(repository, embedded: true));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Documentos del expediente'), findsOneWidget);
    await tester
        .state<EcfDgiiApplicationWizardState>(
          find.byType(EcfDgiiApplicationWizard),
        )
        .goBack();
    await tester.pumpAndSettle();
    expect(find.text('Documentos del expediente'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Continuar'), findsOneWidget);
    await tester.tap(find.text('Revisar datos'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('application_field_company.rnc')),
          )
          .controller!
          .text,
      '131000001',
    );
  });
}
