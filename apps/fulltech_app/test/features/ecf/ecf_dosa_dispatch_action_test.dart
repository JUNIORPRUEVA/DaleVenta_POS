import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_dispatch_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_dosa_dispatch_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acción de EMISIÓN AUTORIZADA en el detalle del comprobante.
///
/// Se comprueba lo que la interfaz debe garantizar por sí misma:
///
///  * no aparece si la empresa no puede emitir o el usuario no tiene permiso;
///  * no aparece en estados no despachables;
///  * no permite doble pulsación;
///  * un rechazo fiscal se muestra con su motivo, no como caída de red;
///  * el mensaje nunca afirma aceptación de la DGII.

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _user({String role = 'ADMIN'}) => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin Test',
  telefono: '',
  role: role,
  companyId: 'company-a',
);

class _FakeEcfRepository extends EcfRepository {
  _FakeEcfRepository() : super(Dio());

  final List<String> calls = <String>[];
  EcfDosaDispatchOutcome result = const EcfDosaDispatchOutcome(
    ok: true,
    code: null,
    blockingReasons: <String>[],
    result: 'STOPPED_REVIEW_REQUIRED',
    correlated: true,
    encf: 'E310000000042',
    environment: 'TEST',
    httpStatus: 200,
    providerOutcome: 'ACCEPTED',
    safeCode: 'ECF_DOSA_OBSERVED_ACCEPTED',
    sequenceConsumed: true,
  );
  DioException? failure;
  Completer<void>? gate;

  @override
  Future<EcfDosaDispatchOutcome> dispatchDosa(String documentId) async {
    calls.add(documentId);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return result;
  }
}

EcfCapabilities _capabilities({bool emissionPathAvailable = true}) =>
    EcfCapabilities(
      enabled: true,
      environment: 'SANDBOX',
      certificationStatus: 'AUTHORIZED_SANDBOX',
      productionEnabled: false,
      allowedTypes: const <String>['E31'],
      emissionPathAvailable: emissionPathAvailable,
      documentTypes: const <EcfDocumentTypeCapability>[],
    );

Future<_FakeEcfRepository> _pump(
  WidgetTester tester, {
  bool emissionPathAvailable = true,
  String role = 'ADMIN',
  String status = 'LOCAL_VALIDATED',
}) async {
  final repository = _FakeEcfRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: _user(role: role),
              loading: false,
              restoringSession: false,
              hasSessionHint: true,
            ),
          ),
        ),
        ecfRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EcfDosaDispatchAction(
              documentId: 'doc-1',
              status: status,
              capabilities: _capabilities(
                emissionPathAvailable: emissionPathAvailable,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return repository;
}

void main() {
  testWidgets('no aparece si la empresa no puede emitir', (tester) async {
    await _pump(tester, emissionPathAvailable: false);
    expect(find.text('Emitir comprobante'), findsNothing);
  });

  testWidgets('no aparece sin permiso de preparación e-CF', (tester) async {
    await _pump(tester, role: 'VENDEDOR');
    expect(find.text('Emitir comprobante'), findsNothing);
  });

  testWidgets('no aparece en un estado no despachable', (tester) async {
    await _pump(tester, status: 'CANCELLED');
    expect(find.text('Emitir comprobante'), findsNothing);
  });

  testWidgets('emite una sola vez aunque se pulse dos veces', (tester) async {
    final repository = await _pump(tester);
    final gate = Completer<void>();
    repository.gate = gate;

    await tester.tap(find.text('Emitir comprobante'));
    await tester.pump();
    // Segundo toque mientras el primero sigue en curso: no debe salir otra
    // petición.
    await tester.tap(find.text('Emitiendo…'));
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
  });

  testWidgets('muestra el resultado y el e-NCF sin afirmar aceptación DGII',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Emitir comprobante'));
    await tester.pumpAndSettle();

    expect(find.textContaining('revisión'), findsOneWidget);
    expect(find.textContaining('E310000000042'), findsOneWidget);
    // Nunca se presenta como aceptación fiscal.
    expect(find.textContaining('ACEPTAD'), findsNothing);
  });

  testWidgets('un bloqueo fiscal se explica con su motivo', (tester) async {
    final repository = await _pump(tester);
    repository.result = const EcfDosaDispatchOutcome(
      ok: false,
      code: 'ECF_DOSA_GATE_BLOCKED',
      blockingReasons: <String>['ECF_DOSA_GATE_CREDENTIALS_NOT_ACTIVE'],
      result: null,
      correlated: false,
      encf: null,
      environment: null,
      httpStatus: null,
      providerOutcome: 'UNKNOWN',
      safeCode: null,
      sequenceConsumed: null,
    );

    await tester.tap(find.text('Emitir comprobante'));
    await tester.pumpAndSettle();

    expect(find.textContaining('pendientes de confirmación'), findsOneWidget);
  });

  testWidgets('un 409 explica que no se reenvía para no duplicar', (tester) async {
    final repository = await _pump(tester);
    repository.failure = DioException(
      requestOptions: RequestOptions(path: '/ecf/documents/doc-1/dispatch-dosa'),
      response: Response(
        requestOptions: RequestOptions(path: '/ecf/documents/doc-1/dispatch-dosa'),
        statusCode: 409,
      ),
    );

    await tester.tap(find.text('Emitir comprobante'));
    await tester.pumpAndSettle();

    expect(find.textContaining('reenvía'), findsOneWidget);
  });
}
