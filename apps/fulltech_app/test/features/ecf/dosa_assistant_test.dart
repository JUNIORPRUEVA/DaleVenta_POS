import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_events.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_launcher.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_panel.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DosaAssistantConfig _config({
  bool enabled = true,
  String scriptUrl = DosaAssistantConfig.officialScriptUrl,
  String? sessionUrl,
  String? publishableKey = 'pk_publica_de_prueba',
  String? baseUrl,
}) => DosaAssistantConfig(
  enabled: enabled,
  scriptUrl: scriptUrl,
  sessionUrl: sessionUrl,
  publishableKey: publishableKey,
  baseUrl: baseUrl,
);

const String _sessionUrl =
    'https://dosasystem.com/embed/certificacion/s/cs_demo_prueba';

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
      const config = DosaAssistantConfig(enabled: false);

      expect(config.canMount, isFalse);
      expect(config.blockers, contains(DosaAssistantBlockReason.disabled));
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.missingSessionSource),
      );
    });

    test('los atributos son los que declara observedAttributes del script', () {
      // Evidencia: dosa-cert.js ->
      // return ['session-url','publishable-key','base-url','theme','height'];
      expect(DosaAssistantConfig.allowedAttributes, {
        'session-url',
        'publishable-key',
        'base-url',
        'theme',
        'height',
      });
    });

    test('un enlace de sesión produce session-url y no el flujo antiguo', () {
      final config = _config(sessionUrl: _sessionUrl, publishableKey: 'pk_x');
      final attributes = config.componentAttributes;

      expect(config.canMount, isTrue);
      expect(attributes['session-url'], _sessionUrl);
      // El componente prefiere session-url: no se envían los atributos antiguos.
      expect(attributes.containsKey('publishable-key'), isFalse);
      expect(attributes['theme'], 'light');
      expect(attributes['height'], '720');
      // No se añade ningún atributo fuera de la lista observada.
      expect(
        attributes.keys.every(DosaAssistantConfig.allowedAttributes.contains),
        isTrue,
      );
    });

    test('una clave pk_live_ NO se bloquea: el script no distingue entornos', () {
      // Corrección: en Fase 3 se exigía pk_test_ sin evidencia. El script solo
      // documenta publishable-key="pk_...".
      final config = _config(publishableKey: 'pk_live_abc123secreto');

      expect(config.canMount, isTrue);
      expect(config.blockers, isEmpty);
      // Aun así el valor nunca se pinta entero.
      expect(config.maskedKey, isNot(contains('abc123secreto')));
    });

    test('un script fuera del origen oficial bloquea el montaje', () {
      final config = _config(scriptUrl: 'https://atacante.example/dosa-cert.js');

      expect(config.canMount, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.scriptUrlNotOfficial),
      );
    });

    test('un session-url de otro origen o sin https se rechaza', () {
      final otroOrigen = _config(
        sessionUrl: 'https://otro.example/embed/certificacion/s/cs_x',
        publishableKey: null,
      );
      final sinHttps = _config(
        sessionUrl: 'http://dosasystem.com/embed/certificacion/s/cs_x',
        publishableKey: null,
      );

      expect(
        otroOrigen.blockers,
        contains(DosaAssistantBlockReason.sessionUrlNotAllowed),
      );
      expect(
        sinHttps.blockers,
        contains(DosaAssistantBlockReason.sessionUrlNotAllowed),
      );
    });

    test('sin sesión ni clave no hay nada que montar', () {
      final config = _config(publishableKey: null);

      expect(config.canMount, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.missingSessionSource),
      );
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
              config: _config(publishableKey: null),
              session: DosaAssistantSession(
                binding: _binding(),
                phase: DosaAssistantPhase.idle,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Asistente de certificación'), findsOneWidget);
      expect(find.text('Bloqueado'), findsOneWidget);
      // Muestra con qué identidad fiscal está vinculado.
      expect(find.textContaining('1-33-02023-2'), findsOneWidget);
      expect(find.textContaining('sin iniciar'), findsOneWidget);
      expect(find.textContaining('pk_'), findsNothing);
    });

    testWidgets('no monta el componente cuando el contrato está bloqueado', (
      tester,
    ) async {
      var mountCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DosaAssistantPanel(
              config: _config(publishableKey: null),
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
      final config = _config(sessionUrl: _sessionUrl);
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
              config: _config(sessionUrl: _sessionUrl),
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
              config: _config(sessionUrl: _sessionUrl),
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

  group('eventos del componente oficial', () {
    test('la lista blanca es la que declara ALLOWED_EVENTS del script', () {
      expect(DosaAssistantConfig.allowedEvents, {
        'cert:ready',
        'cert:step',
        'cert:postulacion',
        'cert:attention',
        'cert:complete',
        'cert:error',
        'cert:resize',
        'cert:asistida_pago',
        'cert:asistida_pagada',
        'cert:blocked',
      });
    });

    test('un evento desconocido se descarta en vez de adivinarse', () {
      expect(parseDosaAssistantEvent(type: 'cert:hackeado'), isNull);
      expect(parseDosaAssistantEvent(type: 'message'), isNull);
    });

    test('parsea etapa y estado que envía el componente', () {
      final event = parseDosaAssistantEvent(
        type: 'cert:step',
        payload: const {'etapa': 'POSTULACION', 'estado': 'EN_CURSO'},
      );

      expect(event, isNotNull);
      expect(event!.stage, 'POSTULACION');
      expect(event.status, 'EN_CURSO');
      expect(event.phase, DosaAssistantPhase.running);
    });

    test('cert:complete NO es aprobación de la DGII', () {
      final event = parseDosaAssistantEvent(
        type: 'cert:complete',
        payload: const {'id': 'p-1'},
      );

      expect(event!.phase, DosaAssistantPhase.completed);
      expect(event.providerId, 'p-1');
      expect(event.isTrusted, isFalse);
      expect(mayMutateFiscalState(event), isFalse);

      final session = DosaAssistantSession(
        binding: _binding(),
        phase: event.phase!,
      );
      expect(session.isDgiiApproval, isFalse);
      expect(session.impliesFiscalAuthorization, isFalse);
    });

    test('NINGÚN evento permite mutar estado fiscal', () {
      for (final type in DosaAssistantConfig.allowedEvents) {
        final event = parseDosaAssistantEvent(
          type: type,
          payload: const {'id': 'x'},
        );
        expect(event, isNotNull, reason: type);
        expect(mayMutateFiscalState(event!), isFalse, reason: type);
      }
    });

    test('cert:resize no pide refresco del backend', () {
      final event = parseDosaAssistantEvent(type: 'cert:resize');
      expect(event!.impliesRefresh, isFalse);
    });

    test('cert:blocked reporta el origen que el navegador bloqueó', () {
      final event = parseDosaAssistantEvent(
        type: 'cert:blocked',
        payload: const {'origin': 'https://fullposcloud.fulltechrd.com'},
      );

      expect(event!.phase, DosaAssistantPhase.originBlocked);
      expect(event.blockedOrigin, 'https://fullposcloud.fulltechrd.com');
    });

    test('los cuatro eventos obligatorios tienen fase propia y no autorizan nada', () {
      final expected = <String, DosaAssistantPhase>{
        'cert:ready': DosaAssistantPhase.running,
        'cert:step': DosaAssistantPhase.running,
        'cert:blocked': DosaAssistantPhase.originBlocked,
        'cert:error': DosaAssistantPhase.failed,
      };

      for (final entry in expected.entries) {
        final event = parseDosaAssistantEvent(
          type: entry.key,
          payload: const {'id': 'p-1'},
        );
        expect(event, isNotNull, reason: entry.key);
        expect(event!.phase, entry.value, reason: entry.key);
        // Ninguno de los cuatro puede presentarse como aprobación fiscal.
        expect(event.isTrusted, isFalse, reason: entry.key);
        expect(mayMutateFiscalState(event), isFalse, reason: entry.key);
        final session = DosaAssistantSession(
          binding: _binding(),
          phase: event.phase!,
        );
        expect(session.isDgiiApproval, isFalse, reason: entry.key);
        expect(session.impliesFiscalAuthorization, isFalse, reason: entry.key);
      }
    });

    test('un cert:error pide recargar el estado en vez de reintentar en el cliente', () {
      final event = parseDosaAssistantEvent(
        type: 'cert:error',
        payload: const {'message': 'No se pudo contactar con la DGII'},
      );

      expect(event!.impliesRefresh, isTrue);
      expect(event.message, 'No se pudo contactar con la DGII');
      expect(event.phase, DosaAssistantPhase.failed);
    });
  });

  group('apertura en navegador externo (Windows / Android / iOS)', () {
    test('rechaza una URL de otro origen sin siquiera abrirla', () async {
      var opened = false;
      final result = await openDosaAssistantExternally(
        sessionUrl: 'https://otro.example/embed/certificacion/s/cs_x',
        opener: (_) async {
          opened = true;
          return true;
        },
      );

      expect(result, isFalse);
      expect(opened, isFalse);
    });

    test('rechaza http aunque sea el origen oficial', () async {
      var opened = false;
      final result = await openDosaAssistantExternally(
        sessionUrl: 'http://dosasystem.com/embed/certificacion/s/cs_x',
        opener: (_) async {
          opened = true;
          return true;
        },
      );

      expect(result, isFalse);
      expect(opened, isFalse);
    });

    test('abre el enlace de sesión oficial', () async {
      Uri? seen;
      final result = await openDosaAssistantExternally(
        sessionUrl: _sessionUrl,
        opener: (uri) async {
          seen = uri;
          return true;
        },
      );

      expect(result, isTrue);
      expect(seen.toString(), _sessionUrl);
    });
  });
}
