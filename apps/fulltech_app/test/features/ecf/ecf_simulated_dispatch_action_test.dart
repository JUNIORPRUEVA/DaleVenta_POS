import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_simulated_dispatch_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acción de DESPACHO SIMULADO en el detalle del comprobante.
///
/// Se prueba lo que la misión exige: que no exista fuera del perfil UAT, sin
/// e-CF en la empresa, sin permiso o con el comprobante en un estado no
/// despachable; que avise de forma inequívoca de que NO es aceptación DGII; que
/// no permita doble pulsación; y que muestre el bloqueo del backend.

const _notice = 'SIMULACIÓN — NO VÁLIDO COMO ACEPTACIÓN DGII.';

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

  final List<String> scenarios = <String>[];
  DioException? failure;
  Completer<void>? gate;

  @override
  Future<EcfSimulatedDispatchOutcome> simulateDispatch({
    required String documentId,
    required String scenario,
  }) async {
    scenarios.add('$documentId:$scenario');
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return const EcfSimulatedDispatchOutcome(
      simulated: true,
      officialFiscalAcceptance: false,
      scenario: 'PROVIDER_ACCEPTED',
      correlated: true,
      documentType: 'E31',
      providerOutcome: 'ACCEPTED',
      safeCode: 'ECF_OBSERVED_ACCEPTED',
    );
  }
}

Future<_FakeEcfRepository> _pump(
  WidgetTester tester, {
  bool uatProfile = true,
  bool ecfEnabled = true,
  String role = 'ADMIN',
  String status = 'LOCAL_VALIDATED',
}) async {
  final repository = _FakeEcfRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ecfSimulatedDispatchVisibleProvider.overrideWithValue(uatProfile),
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
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty().copyWith(
            companyName: 'Empresa Test',
            ecfEnabled: ecfEnabled,
          ),
        ),
        ecfRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EcfSimulatedDispatchAction(
              documentId: 'doc-1',
              status: status,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return repository;
}

void main() {
  group('compuertas de visibilidad', () {
    testWidgets('no existe fuera del perfil UAT', (tester) async {
      await _pump(tester, uatProfile: false);
      expect(find.text(_notice), findsNothing);
      expect(find.text('Ejecutar despacho simulado'), findsNothing);
    });

    testWidgets('no existe si la empresa tiene e-CF desactivado', (tester) async {
      await _pump(tester, ecfEnabled: false);
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('no existe sin permiso para preparar e-CF', (tester) async {
      await _pump(tester, role: 'CAJERO');
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('no existe si el comprobante no es despachable', (tester) async {
      await _pump(tester, status: 'HUMAN_REVIEW_REQUIRED');
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('no existe si ya está aceptado por la DGII', (tester) async {
      await _pump(tester, status: 'DGII_ACCEPTED');
      expect(find.text(_notice), findsNothing);
    });
  });

  group('aviso y ejecución', () {
    testWidgets('avisa de forma inequívoca de que no es aceptación DGII', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text(_notice), findsOneWidget);
      expect(find.text('Ejecutar despacho simulado'), findsOneWidget);
    });

    testWidgets('ejecuta, muestra el resultado y no declara aceptación oficial', (
      tester,
    ) async {
      final repository = await _pump(tester);

      await tester.tap(find.text('Ejecutar despacho simulado'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(repository.scenarios, ['doc-1:PROVIDER_ACCEPTED']);
      expect(find.text('Resultado de la simulación'), findsOneWidget);
      expect(find.text('Resultado observado: ACCEPTED'), findsOneWidget);
      expect(find.text('Aceptación fiscal oficial: no'), findsOneWidget);
      // El aviso obligatorio sigue presente tras ejecutar.
      expect(find.text(_notice), findsOneWidget);
    });

    testWidgets('una segunda pulsación mientras trabaja no dispara otra llamada', (
      tester,
    ) async {
      final repository = await _pump(tester);
      repository.gate = Completer<void>();

      await tester.tap(find.text('Ejecutar despacho simulado'));
      await tester.pump();
      expect(find.text('Ejecutando…'), findsOneWidget);

      // El botón está deshabilitado: el segundo toque no debe llegar a nada.
      await tester.tap(find.text('Ejecutando…'), warnIfMissed: false);
      await tester.pump();

      repository.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(repository.scenarios, hasLength(1));
    });

    testWidgets('un bloqueo del backend muestra el motivo', (tester) async {
      final repository = await _pump(tester);
      repository.failure = DioException(
        requestOptions: RequestOptions(path: '/ecf/documents/doc-1/simulate-dispatch'),
        response: Response<dynamic>(
          statusCode: 409,
          data: {'message': 'ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT'},
          requestOptions: RequestOptions(path: '/x'),
        ),
      );

      await tester.tap(find.text('Ejecutar despacho simulado'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        find.textContaining('ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT'),
        findsOneWidget,
      );
      expect(find.text('Resultado de la simulación'), findsNothing);
    });
  });
}
