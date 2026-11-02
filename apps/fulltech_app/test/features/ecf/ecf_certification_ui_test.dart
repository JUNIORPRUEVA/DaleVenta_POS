import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/data/ecf_certification_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_certification_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_certification_recovery_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_postulation_xml_card.dart';

class _FakeRepository implements EcfCertificationRepository {
  _FakeRepository({
    this.uploadError,
    this.attempts = const <EcfBlockedAttempt>[],
  });

  final Object? uploadError;
  final List<EcfBlockedAttempt> attempts;

  int uploads = 0;
  String? lastDecision;
  String? lastEvidence;

  @override
  Future<EcfPostulationXmlResult> uploadPostulationXml({
    required List<int> bytes,
    required String fileName,
  }) async {
    uploads += 1;
    if (uploadError != null) throw uploadError!;
    return const EcfPostulationXmlResult(
      id: 'ev-1',
      state: 'VALIDATED',
      rootElement: 'PostulacionEmisor',
      duplicate: false,
      notes: ['Esta validación no es una aprobación de la DGII.'],
      sha256Prefix: 'abcdef123456',
    );
  }

  @override
  Future<List<EcfBlockedAttempt>> blockedAttempts() async => attempts;

  @override
  Future<String> resolveAttempt({
    required String attemptId,
    required String decision,
    String? evidenceRef,
    String? note,
    String? externalId,
  }) async {
    lastDecision = decision;
    lastEvidence = evidenceRef;
    return 'SUCCEEDED';
  }

  @override
  Future<EcfPreparationMetadata> preparation() async =>
      const EcfPreparationMetadata(
        videoUrl: null,
        simulationAvailable: false,
        simulationBadge: 'MODO DE PRUEBA',
        simulationReason: null,
      );

  @override
  Future<void> start() async {}

  @override
  Future<EcfActivationProgress> progress() async => const EcfActivationProgress(
    stage: 'NOT_STARTED',
    percent: 0,
    resolvedCount: 0,
    total: 0,
    steps: <EcfActivationStepView>[],
    transportSimulated: true,
  );
}

Widget _wrap(_FakeRepository repository, Widget child) => ProviderScope(
  overrides: [ecfCertificationRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Future<({String name, List<int> bytes})?> Function() _picker(String name) =>
    () async => (name: name, bytes: const [1, 2, 3]);

void main() {
  testWidgets('XML: sube, valida y declara que no es aprobación oficial', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      _wrap(
        repository,
        EcfPostulationXmlCard(pickFile: _picker('postulacion.xml')),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    expect(find.text('postulacion.xml'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ecf_postulation_xml_upload')));
    await tester.pumpAndSettle();

    expect(repository.uploads, 1);
    expect(find.text('XML validado y asociado al expediente'), findsOneWidget);
    expect(
      find.textContaining('no es una aprobación de la DGII'),
      findsOneWidget,
    );
  });

  testWidgets('XML: explica el rechazo por documento de otra etapa', (
    tester,
  ) async {
    final repository = _FakeRepository(
      uploadError: Exception('BadRequest: ECF_POSTULATION_XML_WRONG_STAGE'),
    );
    await tester.pumpWidget(
      _wrap(repository, EcfPostulationXmlCard(pickFile: _picker('e32.xml'))),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ecf_postulation_xml_upload')));
    await tester.pumpAndSettle();

    expect(find.textContaining('no el XML de postulación'), findsOneWidget);
    expect(find.text('XML validado y asociado al expediente'), findsNothing);
  });

  testWidgets('reconciliación: exige decisión explícita y envía la evidencia', (
    tester,
  ) async {
    final repository = _FakeRepository(
      attempts: const [
        EcfBlockedAttempt(
          attemptId: 'a1',
          operation: 'SET_TESTS',
          stepKey: 'SET_TESTS',
          createdAt: '2026-11-01T09:00:00.000Z',
          reference: null,
          errorCode: 'ECF_PROVIDER_RESULT_UNKNOWN',
          reason: 'El proveedor no confirmó el resultado.',
          safeAction: 'No se puede reenviar por un timeout.',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: EcfCertificationRecoveryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SET_TESTS'), findsOneWidget);
    expect(find.textContaining('No se puede reenviar'), findsOneWidget);
    // No existe un botón de «reintentar» a secas.
    expect(find.text('Reintentar'), findsNothing);

    await tester.tap(find.text('Sí se aplicó (con evidencia)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Referencia de la evidencia'),
      'acuse-778',
    );
    await tester.tap(find.text('Registrar decisión'));
    await tester.pumpAndSettle();

    expect(repository.lastDecision, 'CONFIRM_APPLIED_WITH_EVIDENCE');
    expect(repository.lastEvidence, 'acuse-778');
  });

  testWidgets('reconciliación: sin intentos informa y no ofrece acciones', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: EcfCertificationRecoveryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay intentos bloqueados'), findsOneWidget);
    expect(find.text('Sí se aplicó (con evidencia)'), findsNothing);
  });
}
