import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Montaje del asistente en el modo oficial `publishable-key` + `base-url`.
///
/// El flujo documentado por el proveedor es
/// `<dosa-cert-wizard publishable-key="..." base-url="https://dosasystem.com">`,
/// es decir: **sin** `session-url`. Estas pruebas fijan que FullPOS monta el
/// componente en ese modo y que no envía atributos que el componente no observa.
void main() {
  const publishableKey = 'pk_live_abc123';

  group('DosaAssistantConfig — modo publishable-key', () {
    test('monta sin session-url cuando solo hay publishable-key y base-url', () {
      const config = DosaAssistantConfig(
        enabled: true,
        publishableKey: publishableKey,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      expect(config.hasSessionUrl, isFalse);
      expect(config.hasPublishableKey, isTrue);
      expect(config.blockers, isEmpty);
      expect(config.canMount, isTrue);
    });

    test('los atributos del componente son exactamente los documentados', () {
      const config = DosaAssistantConfig(
        enabled: true,
        publishableKey: publishableKey,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      final attributes = config.componentAttributes;
      expect(attributes.keys.toSet(), {
        'publishable-key',
        'base-url',
        'theme',
        'height',
      });
      expect(attributes.containsKey('session-url'), isFalse);
      expect(attributes['publishable-key'], publishableKey);
      expect(attributes['base-url'], DosaAssistantConfig.officialOrigin);
    });

    test('no se envía ningún atributo fuera de la lista permitida', () {
      const config = DosaAssistantConfig(
        enabled: true,
        publishableKey: publishableKey,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      for (final key in config.componentAttributes.keys) {
        expect(
          DosaAssistantConfig.allowedAttributes.contains(key),
          isTrue,
          reason: 'atributo no permitido: $key',
        );
      }
    });

    test('sin clave ni session-url no se monta y el motivo es explícito', () {
      const config = DosaAssistantConfig(
        enabled: true,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      expect(config.canMount, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.missingSessionSource),
      );
    });

    test('desactivado por defecto: no se monta aunque haya clave', () {
      const config = DosaAssistantConfig(
        enabled: false,
        publishableKey: publishableKey,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      expect(config.canMount, isFalse);
      expect(config.blockers, contains(DosaAssistantBlockReason.disabled));
    });
  });

  group('DosaAssistantConfig — session-url tiene prioridad', () {
    test('con session-url no se envía publishable-key', () {
      const config = DosaAssistantConfig(
        enabled: true,
        sessionUrl: 'https://dosasystem.com/s/cert-123',
        publishableKey: publishableKey,
        baseUrl: DosaAssistantConfig.officialOrigin,
      );

      final attributes = config.componentAttributes;
      expect(attributes['session-url'], 'https://dosasystem.com/s/cert-123');
      expect(attributes.containsKey('publishable-key'), isFalse);
      expect(attributes.containsKey('base-url'), isFalse);
    });

    test('un session-url de otro origen se rechaza', () {
      const config = DosaAssistantConfig(
        enabled: true,
        sessionUrl: 'https://evil.example.com/s/cert-123',
      );

      expect(config.canMount, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.sessionUrlNotAllowed),
      );
    });
  });

  group('DosaAssistantConfig — origen y secretos', () {
    test('el script se sirve desde el origen oficial', () {
      const config = DosaAssistantConfig(enabled: true);

      expect(config.isScriptUrlOfficial, isTrue);
      expect(
        config.scriptUrl.startsWith(DosaAssistantConfig.officialOrigin),
        isTrue,
      );
    });

    test('un script de otro origen bloquea el montaje', () {
      const config = DosaAssistantConfig(
        enabled: true,
        scriptUrl: 'https://cdn.example.com/dosa-cert.js',
        publishableKey: publishableKey,
      );

      expect(config.isScriptUrlOfficial, isFalse);
      expect(
        config.blockers,
        contains(DosaAssistantBlockReason.scriptUrlNotOfficial),
      );
    });

    test('la clave se enmascara y nunca se muestra completa', () {
      const config = DosaAssistantConfig(
        enabled: true,
        publishableKey: publishableKey,
      );

      expect(config.maskedKey, 'pk_liv…');
      expect(config.maskedKey.contains(publishableKey), isFalse);
    });

    test('el mensaje de bloqueo no filtra la clave', () {
      const config = DosaAssistantConfig(
        enabled: true,
        publishableKey: publishableKey,
      );

      expect(config.blockedMessage.toLowerCase(), isNot(contains('pk_live')));
    });
  });
}
