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

UserModel _user() => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin',
  telefono: '',
  role: 'ADMIN',
  companyId: 'company-a',
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
  _FakeApplicationRepository({required this.initial})
    : super(Dio());

  final EcfApplicationDraft initial;

  int saves = 0;
  int loads = 0;
  int submits = 0;
  int? lastExpectedRevision;
  Map<String, dynamic>? lastPayload;

  /// Si no es `null`, el siguiente guardado lanza este error.
  Object? failSaveWith;

  /// Si no es `null`, el guardado espera a que se complete esta compuerta.
  /// Permite observar el estado «Guardando…» de forma determinista en vez de
  /// depender de que la respuesta tarde.
  Completer<void>? saveGate;

  /// Datos que devuelve el servidor tras un conflicto.
  EcfApplicationDraft? serverAfterConflict;

  @override
  Future<EcfApplicationDraft> draft() async {
    loads++;
    return serverAfterConflict ?? initial;
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
    return EcfApplicationDraft(
      state: 'NOT_STARTED',
      draft: payload,
      missingFields: const <String>[],
      draftUpdatedAt: DateTime.now(),
      draftRevision: (expectedRevision ?? 0) + 1,
      currentSnapshotVersion: 0,
      consentVersion: null,
      requiredConsentVersion: 'v-test',
      consentPurpose: 'Autorizo el uso de los datos.',
    );
  }

  @override
  Future<EcfApplicationSubmitResult> submit({
    required String consentVersion,
    required Map<String, dynamic> payload,
  }) async {
    submits++;
    return const EcfApplicationSubmitResult(
      idempotent: false,
      version: 1,
      state: 'APPLICATION_PENDING',
    );
  }
}

EcfApplicationDraft _draft({
  Map<String, dynamic>? data,
  int revision = 0,
  List<String> missing = const <String>[],
}) {
  return EcfApplicationDraft(
    state: 'NOT_STARTED',
    draft: data,
    missingFields: missing,
    draftUpdatedAt: null,
    draftRevision: revision,
    currentSnapshotVersion: 0,
    consentVersion: null,
    requiredConsentVersion: 'v-test',
    consentPurpose: 'Autorizo el uso de los datos.',
  );
}

Widget _harness(_FakeApplicationRepository repository) {
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
            user: _user(),
            hasSessionHint: true,
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: EcfDgiiApplicationWizard()),
  );
}

void main() {
  testWidgets('el paso de datos muestra los campos de empresa y representante', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _FakeApplicationRepository(initial: _draft(data: _completeDraft)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Datos de la empresa'), findsOneWidget);
    expect(find.text('Representante legal'), findsOneWidget);
    expect(find.widgetWithText(TextField, '131000001'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Ana Pérez'), findsOneWidget);
    expect(find.text('Datos'), findsOneWidget); // cabecera de pasos
    expect(find.text('Enviar'), findsOneWidget);
  });

  testWidgets('recupera el borrador guardado al abrir la pantalla', (tester) async {
    final repository = _FakeApplicationRepository(
      initial: _draft(data: _completeDraft, revision: 4),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(repository.loads, 1);
    expect(find.widgetWithText(TextField, 'Empresa Sintética SRL'), findsOneWidget);
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

    await tester.enterText(
      find.widgetWithText(TextField, 'RNC'),
      '131000777',
    );
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

  testWidgets('ante un conflicto adopta la versión del servidor y avisa', (
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

    await tester.enterText(
      find.widgetWithText(TextField, 'Dirección fiscal'),
      'Dirección local',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // No se impone lo local: se adopta lo del servidor y se avisa.
    expect(
      find.widgetWithText(TextField, 'Dirección del otro dispositivo'),
      findsOneWidget,
    );
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
    expect(find.text('Datos de la empresa'), findsOneWidget);
    expect(repository.submits, 0);
  });
}
