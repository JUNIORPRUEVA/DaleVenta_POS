import 'package:daleventa_pos/features/ecf/ui/flow/ecf_preparation_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pantalla de Preparación: una etapa del recorrido nunca puede quedarse sin
/// una acción. Cuando la postulación ya está abierta no hay nada que iniciar, y
/// la única salida razonable es continuar al seguimiento.

Widget _harness({
  required bool postulationStarted,
  required VoidCallback onContinue,
  Widget? dosaEntry,
  bool canManage = true,
  bool busy = false,
  VoidCallback? onEditFiscalData,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EcfPreparationStep(
        settings: null,
        companyReady: true,
        contactEmailReady: true,
        certificateReady: false,
        dosaOwnsCertificate: true,
        canManage: canManage,
        busy: busy,
        onEditFiscalData: onEditFiscalData ?? () {},
        onStart: () {},
        onGoCompany: () {},
        onGoCertificate: () {},
        onContinue: onContinue,
        postulationStarted: postulationStarted,
        dosaEntry: dosaEntry,
      ),
    ),
  );
}

void main() {
  testWidgets('datos completos conservan acceso explícito a la corrección', (tester) async {
    var edits = 0;
    await tester.pumpWidget(_harness(
      postulationStarted: false, onContinue: () {},
      onEditFiscalData: () => edits++,
    ));
    await tester.tap(find.byKey(const ValueKey('ecf_preparation_review_data')));
    expect(edits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no ofrece corrección sin permiso', (tester) async {
    await tester.pumpWidget(_harness(
      postulationStarted: false, onContinue: () {}, canManage: false,
    ));
    expect(find.byKey(const ValueKey('ecf_preparation_review_data')), findsNothing);
  });

  testWidgets('corrección deshabilitada durante una operación', (tester) async {
    await tester.pumpWidget(_harness(
      postulationStarted: false, onContinue: () {}, busy: true,
    ));
    final button = tester.widget<TextButton>(find.byKey(const ValueKey('ecf_preparation_review_data')));
    expect(button.onPressed, isNull);
  });

  testWidgets('con la postulación abierta la etapa solo deja continuar', (
    tester,
  ) async {
    var continues = 0;
    await tester.pumpWidget(
      _harness(
        postulationStarted: true,
        onContinue: () => continues++,
        // El bloque del portal se queda sin nada que ofrecer cuando el
        // expediente ya está abierto: aquí se simula ese hueco.
        dosaEntry: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('ecf_preparation_continue'));
    expect(action, findsOneWidget);
    // No se vuelve a ofrecer iniciar una postulación que ya existe.
    expect(find.text('Iniciar postulación'), findsNothing);
    expect(find.text('Revisar o corregir datos'), findsNothing);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(continues, 1);
  });

  testWidgets('permite corregir datos completos antes de postular', (tester) async {
    var edits = 0;
    await tester.pumpWidget(_harness(
      postulationStarted: false,
      onContinue: () {},
      onEditFiscalData: () => edits++,
    ));
    await tester.tap(find.byKey(const ValueKey('ecf_preparation_review_data')));
    expect(edits, 1);
  });

  testWidgets('no ofrece edición sin permiso y la bloquea mientras trabaja', (tester) async {
    await tester.pumpWidget(_harness(
      postulationStarted: false, onContinue: () {}, canManage: false,
    ));
    expect(find.text('Revisar o corregir datos'), findsNothing);
    var edits = 0;
    await tester.pumpWidget(_harness(
      postulationStarted: false, onContinue: () {}, busy: true,
      onEditFiscalData: () => edits++,
    ));
    await tester.tap(find.byKey(const ValueKey('ecf_preparation_review_data')));
    expect(edits, 0);
  });

  testWidgets('sin postulación previa se ofrece iniciarla', (tester) async {
    var continues = 0;
    await tester.pumpWidget(
      _harness(
        postulationStarted: false,
        onContinue: () => continues++,
        dosaEntry: const Text('Iniciar postulación'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar postulación'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_preparation_continue')),
      findsNothing,
    );
    expect(continues, 0);
  });
}
