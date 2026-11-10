import 'dart:async';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_activation_models.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_dosa_activation_status.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bloque de estado de la autorización de emisión.
///
/// Es la única pieza de interfaz que cierra el circuito del cliente, así que se
/// prueba lo que puede salir mal: que oculte permisos, que muestre códigos en
/// crudo, que dispare dos peticiones con doble toque y que confunda un fallo de
/// red con «falta evidencia».
class _FakeRepository extends EcfRepository {
  _FakeRepository() : super(Dio());

  EcfDosaActivationOutcome? result;
  Object? failure;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<EcfDosaActivationOutcome> attemptDosaActivation() async {
    calls++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return result!;
  }
}

EcfDosaActivationOutcome _outcome({
  bool authorized = false,
  String status = 'IN_PROGRESS',
  List<String> reasons = const [],
}) => EcfDosaActivationOutcome.fromJson({
  'ok': authorized,
  'companyId': 'company-a',
  'certificationStatus': status,
  'changed': false,
  'environments': [
    {
      'environment': 'test',
      'status': authorized ? 'ACTIVE' : 'PENDING_CONFIRMATION',
      'activated': false,
      'blockingReasons': reasons,
    },
  ],
});

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  EcfDosaActivationOutcome? result,
  Object? failure,
  Completer<void>? gate,
  bool canManage = true,
  bool compact = false,
}) async {
  final repository = _FakeRepository()
    ..result = result ?? _outcome()
    ..failure = failure
    ..gate = gate;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EcfDosaActivationStatus(
                canManage: canManage,
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('sin permiso no consulta ni muestra nada', (tester) async {
    final repository = await _pump(tester, canManage: false);

    expect(repository.calls, 0);
    expect(find.text('Actualizar estado'), findsNothing);
    expect(find.textContaining('Comprobando'), findsNothing);
  });

  testWidgets('consulta al aparecer, sin que el cliente pulse nada', (
    tester,
  ) async {
    final repository = await _pump(tester);

    expect(repository.calls, 1);
  });

  testWidgets('autorizado: lo dice y no deja nada por hacer', (tester) async {
    await _pump(tester, result: _outcome(authorized: true, status: 'PRODUCTION_READY'));

    expect(
      find.text('Autorizado para facturar electrónicamente en producción.'),
      findsOneWidget,
    );
    expect(find.text('Actualizar estado'), findsNothing);
  });

  testWidgets('pendiente: traduce los motivos y ofrece actualizar', (
    tester,
  ) async {
    await _pump(
      tester,
      result: _outcome(
        reasons: const [
          'ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED',
          'ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED',
        ],
      ),
    );

    expect(find.text('Autorización para facturar'), findsOneWidget);
    expect(
      find.textContaining('DOSA aún no ha confirmado'),
      findsOneWidget,
    );
    expect(
      find.textContaining('autorización de emisión que registra el equipo'),
      findsOneWidget,
    );
    expect(find.text('Actualizar estado'), findsOneWidget);
  });

  testWidgets('un motivo desconocido se muestra en crudo, no se esconde', (
    tester,
  ) async {
    await _pump(
      tester,
      result: _outcome(reasons: const ['ECF_ALGO_NUEVO_DEL_BACKEND']),
    );

    expect(find.textContaining('ECF_ALGO_NUEVO_DEL_BACKEND'), findsOneWidget);
  });

  testWidgets('sin motivos ni autorización avisa en vez de quedarse vacío', (
    tester,
  ) async {
    await _pump(tester, result: _outcome());

    expect(
      find.textContaining('Todavía no hay evidencia suficiente'),
      findsOneWidget,
    );
  });

  testWidgets('un fallo de red se distingue de «falta evidencia»', (
    tester,
  ) async {
    await _pump(tester, failure: DioException(requestOptions: RequestOptions()));

    expect(
      find.textContaining('No se pudo comprobar el estado'),
      findsOneWidget,
    );
    // No se inventa una lista de pendientes cuando en realidad no se consultó.
    expect(find.text('Autorización para facturar'), findsNothing);
  });

  testWidgets('el doble toque no dispara dos peticiones', (tester) async {
    final repository = await _pump(
      tester,
      result: _outcome(
        reasons: const ['ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED'],
      ),
    );
    // Consulta inicial.
    expect(repository.calls, 1);

    // La segunda llamada queda en vuelo: el botón debe quedar bloqueado.
    repository.gate = Completer<void>();
    await tester.tap(find.text('Actualizar estado'));
    await tester.pump();
    await tester.tap(find.text('Actualizar estado'), warnIfMissed: false);
    await tester.pump();

    expect(repository.calls, 2);

    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Actualizar estado'), findsOneWidget);
  });

  testWidgets('compacto en preparación: un motivo y acción', (tester) async {
    await _pump(
      tester,
      compact: true,
      result: _outcome(
        reasons: const [
          'ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED',
          'ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED',
        ],
      ),
    );

    expect(find.textContaining('DOSA aún no ha confirmado'), findsOneWidget);
    expect(find.textContaining('2 pasos por completar'), findsOneWidget);
    expect(find.text('Actualizar estado'), findsOneWidget);
    // El aviso vive dentro de una tarjeta con su propio título: fuera de ella
    // parecía un texto suelto sobre el fondo. El título nombra el trámite de
    // certificación para no confundirlo con la numeración de la DGII.
    expect(find.text('Certificación DGII'), findsOneWidget);
  });
}
