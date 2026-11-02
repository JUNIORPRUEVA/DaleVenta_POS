import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_panel.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DosaAssistantConfig _config({
  bool enabled = true,
  String scriptUrl = 'https://asistente.example/dosa-cert.js',
  String publishableKey = 'pk_test_valor-de-prueba',
  Map<String, String> documentedAttributes = const <String, String>{},
}) => DosaAssistantConfig(
  enabled: enabled,
  scriptUrl: scriptUrl,
  publishableKey: publishableKey,
  documentedAttributes: documentedAttributes,
);

DosaAssistantBinding _binding({
  String companyId = 'company-a',
  String taxId = '1-33-02023-2',
  String? externalId,
}) => DosaAssistantBinding(
  companyId: companyId,
  taxId: taxId,
  postulationExternalId: externalId,
);

void main() {
  group('configuración del asistente', () {
    test('sin configuración de build queda apagado y bloqueado', () {
      const config = DosaAssistantConfig(
        enabled: false,
        scriptUrl: '',
        publishableKey: '',
      );

      expect(config.canMount, isFalse);
      expect(config.blockers, contains(DosaAssistantBlockReason.disabled));
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.missingScriptUrl),
      );
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.missingPublishableKey),
      );
    });

    test('una clave pk_live_ NUNCA permite montar el asistente', () {
      final config = _config(
        publishableKey: 'pk_live_abc123secreto',
        documentedAttributes: const {'attribute': 'value'},
      );

      expect(config.hasProductionKey, isTrue);
      expect(config.canMount, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.productionKeyNotAllowed),
      );
      // El mensaje para el usuario no filtra el valor de la clave.
      expect(config.blockedMessage, isNot(contains('abc123secreto')));
      expect(config.maskedKey, 'pk_live_…');
    });

    test('no se inventan atributos del componente oficial', () {
      // Nadie pasa atributos hoy: el mapa queda vacío y eso bloquea el montaje.
      expect(_config().componentAttributes, isEmpty);
      expect(
        _config().blockers,
        contains(DosaAssistantBlockReason.componentAttributesUndocumented),
      );
      expect(_config().canMount, isFalse);
    });

    test('solo con clave de prueba y atributos documentados se puede montar', () {
      final config = _config(
        documentedAttributes: const {'company': 'demo'},
      );

      expect(config.canMount, isTrue);
      expect(config.blockers, isEmpty);
      expect(config.maskedKey, 'pk_test_…');
    });
  });

  group('vinculación empresa → RNC → postulación', () {
    test('la clave de vinculación aísla por empresa y normaliza el RNC', () {
      final a = _binding();
      final b = _binding(companyId: 'company-b');

      expect(a.dedupeKey, 'dosa:company-a:133020232');
      expect(a.dedupeKey, isNot(b.dedupeKey));
    });

    test('sin RNC no se puede iniciar', () {
      final decision = canStartPostulation(
        binding: _binding(taxId: '   '),
        existing: const [],
      );

      expect(decision.allowed, isFalse);
      expect(decision.status, DosaStartStatus.missingFiscalIdentity);
    });

    test('una postulación en curso bloquea una segunda', () {
      final binding = _binding();
      final decision = canStartPostulation(
        binding: binding,
        existing: [
          DosaAssistantSession(
            binding: binding,
            phase: DosaAssistantPhase.running,
          ),
        ],
      );

      expect(decision.allowed, isFalse);
      expect(decision.status, DosaStartStatus.duplicatePostulation);
    });

    test('una postulación completada también bloquea duplicados', () {
      final binding = _binding();
      final decision = canStartPostulation(
        binding: binding,
        existing: [
          DosaAssistantSession(
            binding: binding,
            phase: DosaAssistantPhase.completed,
          ),
        ],
      );

      expect(decision.status, DosaStartStatus.duplicatePostulation);
    });

    test('un fallo permite reanudar, no crear otra postulación', () {
      final binding = _binding();
      final decision = canStartPostulation(
        binding: binding,
        existing: [
          DosaAssistantSession(
            binding: binding,
            phase: DosaAssistantPhase.failed,
          ),
        ],
      );

      expect(decision.allowed, isTrue);
    });

    test('otra empresa con el mismo RNC no se ve afectada', () {
      final decision = canStartPostulation(
        binding: _binding(companyId: 'company-b'),
        existing: [
          DosaAssistantSession(
            binding: _binding(),
            phase: DosaAssistantPhase.completed,
          ),
        ],
      );

      expect(decision.allowed, isTrue);
    });

    test('finalizar el proceso NO implica autorización fiscal', () {
      final session = DosaAssistantSession(
        binding: _binding(),
        phase: DosaAssistantPhase.completed,
      );

      expect(session.impliesFiscalAuthorization, isFalse);
    });
  });

  group('panel visual del asistente', () {
    testWidgets('con el contrato incompleto muestra el estado bloqueado', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: _config(publishableKey: 'pk_live_noautorizada'),
              session: DosaAssistantSession(
                binding: _binding(),
                phase: DosaAssistantPhase.idle,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Asistente de certificación DOSA'), findsOneWidget);
      expect(find.text('Bloqueado'), findsOneWidget);
      // Muestra con qué identidad fiscal está vinculado.
      expect(find.textContaining('1-33-02023-2'), findsOneWidget);
      expect(find.textContaining('sin iniciar'), findsOneWidget);
      // Y no filtra la clave.
      expect(find.textContaining('noautorizada'), findsNothing);
    });

    testWidgets('no monta el componente cuando el contrato está bloqueado', (
      tester,
    ) async {
      var mountCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: _config(),
              session: DosaAssistantSession(
                binding: _binding(),
                phase: DosaAssistantPhase.running,
              ),
              mountBuilder: (_, __) {
                mountCalls++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(mountCalls, 0);
      expect(find.text('Bloqueado'), findsOneWidget);
    });

    testWidgets('monta el contenedor solo con el contrato completo', (
      tester,
    ) async {
      final config = _config(
        documentedAttributes: const {'company': 'demo'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: config,
              session: DosaAssistantSession(
                binding: _binding(),
                phase: DosaAssistantPhase.running,
              ),
              mountBuilder: (_, __) =>
                  const Center(child: Text('CONTENEDOR-OFICIAL-DOSA')),
            ),
          ),
        ),
      );

      expect(find.text('CONTENEDOR-OFICIAL-DOSA'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
    });

    testWidgets('un proceso finalizado no se presenta como autorizado', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: _config(
                documentedAttributes: const {'company': 'demo'},
              ),
              session: DosaAssistantSession(
                binding: _binding(externalId: 'POST-1'),
                phase: DosaAssistantPhase.completed,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Finalizado por el proveedor'), findsOneWidget);
      expect(find.textContaining('NO autoriza emisión'), findsOneWidget);
      expect(find.textContaining('Postulación: POST-1'), findsOneWidget);
    });

    testWidgets('un error ofrece reanudar, no reiniciar', (tester) async {
      var resumed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: _config(
                documentedAttributes: const {'company': 'demo'},
              ),
              session: DosaAssistantSession(
                binding: _binding(),
                phase: DosaAssistantPhase.failed,
                errorCode: 'PROVIDER_TIMEOUT',
              ),
              onResume: () => resumed++,
            ),
          ),
        ),
      );

      expect(find.text('Reanudar proceso'), findsOneWidget);
      expect(find.textContaining('PROVIDER_TIMEOUT'), findsOneWidget);
      await tester.tap(find.text('Reanudar proceso'));
      expect(resumed, 1);
    });
  });
}
