import 'dart:async';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_diagnostic.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_diagnostic_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpDiagnostic(
    WidgetTester tester, {
    required _DiagnosticApi api,
    String role = 'ADMIN',
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
        dosaCertificationDiagnosticApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DosaCertificationDiagnosticSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('administrador consulta solo después de abrir el diagnóstico', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _DiagnosticApi(_diagnostic());

    await pumpDiagnostic(tester, api: api);
    expect(api.readCalls, 0);
    expect(find.text('Ver diagnóstico'), findsOneWidget);

    await tester.tap(find.text('Ver diagnóstico'));
    await tester.pumpAndSettle();

    expect(api.readCalls, 1);
    expect(find.text('Intento: 1'), findsOneWidget);
    expect(find.text('Estado: Sin iniciar'), findsOneWidget);
    expect(find.text('Proveedor registrado: ALANUBE'), findsOneWidget);
    expect(find.text('Sesión externa: Sin referencia'), findsOneWidget);
    expect(find.text('Postulación externa: Sin referencia'), findsOneWidget);
    expect(find.text('Atribución histórica: ALANUBE'), findsOneWidget);
    expect(
      find.text(
        'Reconciliación administrativa: Necesaria antes de abrir el portal',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('company-a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usuario ordinario no ve ni consulta el diagnóstico', (
    tester,
  ) async {
    final api = _DiagnosticApi(_diagnostic());

    await pumpDiagnostic(tester, api: api, role: 'MARKETING');

    expect(find.text('Diagnóstico administrativo'), findsNothing);
    expect(api.readCalls, 0);
  });

  testWidgets('denegación del backend muestra mensaje de permisos', (
    tester,
  ) async {
    final api = _DiagnosticApi(
      null,
      error: const DosaDiagnosticException(DosaDiagnosticFailure.accessDenied),
    );
    await pumpDiagnostic(tester, api: api);

    await tester.tap(find.text('Ver diagnóstico'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No tienes permiso'), findsOneWidget);
    expect(find.text('Intento: 1'), findsNothing);
  });

  testWidgets('respuesta de otra empresa falla cerrada', (tester) async {
    final api = _DiagnosticApi(_diagnostic(companyId: 'company-b'));
    await pumpDiagnostic(tester, api: api);

    await tester.tap(find.text('Ver diagnóstico'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no corresponde a la empresa actual'),
      findsOneWidget,
    );
    expect(find.text('Intento: 1'), findsNothing);
  });

  testWidgets('cambio de empresa no muestra la respuesta anterior', (
    tester,
  ) async {
    final pending = Completer<DosaCertificationDiagnostic>();
    final api = _DiagnosticApi(null, pending: pending);
    final container = await pumpDiagnostic(tester, api: api);

    await tester.tap(find.text('Ver diagnóstico'));
    await tester.pump();
    (container.read(authStateProvider.notifier) as _FixedAuthController)
        .setTestUser(_user(companyId: 'company-b'));
    pending.complete(_diagnostic());
    await tester.pumpAndSettle();

    expect(find.text('Intento: 1'), findsNothing);
    expect(
      find.textContaining('no corresponde a la empresa actual'),
      findsOneWidget,
    );
  });

  test(
    'cliente usa únicamente GET sin cuerpo ni companyId en la URL',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _json(),
              ),
            );
          },
        ),
      );

      final result = await DosaCertificationDiagnosticApi(dio).read();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.path, ApiRoutes.ecfDosaCertificationDiagnostic);
      expect(requests.single.data, isNull);
      expect(result.companyId, 'company-a');
      expect(result.requiresReconciliation, isTrue);
    },
  );

  test('cliente convierte HTTP 403 en denegación de permisos', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 403),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    await expectLater(
      DosaCertificationDiagnosticApi(dio).read(),
      throwsA(
        isA<DosaDiagnosticException>().having(
          (error) => error.failure,
          'failure',
          DosaDiagnosticFailure.accessDenied,
        ),
      ),
    );
  });

  test('solo una atribución DOSA íntegra evita la reconciliación', () {
    final dosa = DosaCertificationDiagnostic.fromJson({
      'companyId': 'company-a',
      'intention': {
        'attemptNo': 1,
        'status': 'NOT_STARTED',
        'recordedProvider': 'DOSA',
        'hasProviderSessionUrl': false,
        'hasProviderPostulationId': false,
      },
      'audit': [
        {'recordedProvider': 'DOSA'},
      ],
    });
    final missingAudit = DosaCertificationDiagnostic.fromJson({
      'companyId': 'company-a',
      'intention': {
        'attemptNo': 1,
        'status': 'NOT_STARTED',
        'recordedProvider': 'DOSA',
        'hasProviderSessionUrl': false,
        'hasProviderPostulationId': false,
      },
      'audit': <Map<String, dynamic>>[],
    });

    expect(dosa.requiresReconciliation, isFalse);
    expect(missingAudit.requiresReconciliation, isTrue);
  });

  test('reconciliación efectiva conserva la atribución histórica', () {
    final result = DosaCertificationDiagnostic.fromJson({
      'companyId': 'company-a',
      'intention': {
        'attemptNo': 1,
        'status': 'NOT_STARTED',
        'recordedProvider': 'ALANUBE',
        'effectiveProvider': 'DOSA',
        'hasProviderSessionUrl': false,
        'hasProviderPostulationId': false,
      },
      'audit': [
        {'recordedProvider': 'ALANUBE'},
      ],
    });
    expect(result.attempt!.recordedProvider, 'ALANUBE');
    expect(result.attempt!.effectiveProvider, 'DOSA');
    expect(result.requiresReconciliation, isFalse);
  });
}

Map<String, dynamic> _json({String companyId = 'company-a'}) => {
  'companyId': companyId,
  'intention': {
    'attemptNo': 1,
    'status': 'NOT_STARTED',
    'recordedProvider': 'ALANUBE',
    'hasProviderSessionUrl': false,
    'hasProviderPostulationId': false,
  },
  'audit': [
    {'recordedProvider': 'ALANUBE'},
  ],
};

DosaCertificationDiagnostic _diagnostic({String companyId = 'company-a'}) =>
    DosaCertificationDiagnostic.fromJson(_json(companyId: companyId));

class _DiagnosticApi extends DosaCertificationDiagnosticApi {
  _DiagnosticApi(this.result, {this.error, this.pending}) : super(Dio());

  final DosaCertificationDiagnostic? result;
  final Object? error;
  final Completer<DosaCertificationDiagnostic>? pending;
  int readCalls = 0;

  @override
  Future<DosaCertificationDiagnostic> read() async {
    readCalls++;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return result!;
  }
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

UserModel _user({String role = 'ADMIN', String companyId = 'company-a'}) =>
    UserModel(
      id: 'user-a',
      email: 'user-a@test.local',
      nombreCompleto: 'Administrador',
      telefono: '',
      role: role,
      companyId: companyId,
      companyName: 'Empresa de prueba',
    );
