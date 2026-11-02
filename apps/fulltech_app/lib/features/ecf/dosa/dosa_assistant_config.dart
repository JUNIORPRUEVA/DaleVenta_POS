import 'package:flutter/foundation.dart';

/// Por qué el asistente oficial de DOSA no puede montarse todavía.
///
/// Es un motivo CONCRETO: la pantalla lo muestra tal cual al administrador en
/// lugar de un "no disponible" genérico, para que se sepa qué falta.
enum DosaAssistantBlockReason {
  /// La bandera está apagada. Es el estado por defecto.
  disabled,

  /// Falta la URL del script `dosa-cert.js`.
  missingScriptUrl,

  /// Falta la clave publicable del componente.
  missingPublishableKey,

  /// La clave disponible es `pk_live_` (producción). No se usa hasta tener una
  /// configuración de PRUEBA autorizada.
  productionKeyNotAllowed,

  /// DOSA no ha documentado los atributos de `<dosa-cert-wizard>`.
  componentAttributesUndocumented,

  /// La plataforma no puede contener el componente con lo que hay instalado.
  platformUnsupported,
}

/// Configuración del asistente DOSA.
///
/// Reglas de esta clase:
///
/// 1. Todo entra por `--dart-define`. **Nada** se escribe en el código: ni la
///    clave publicable ni la URL del script.
/// 2. `canMount` es `false` mientras exista cualquier motivo de bloqueo. Hoy
///    siempre lo es, porque la clave recibida es `pk_live_` y porque faltan los
///    atributos documentados del componente.
/// 3. `componentAttributes` está **vacío** a propósito: inventar nombres de
///    atributos haría que el componente oficial fallara en silencio.
@immutable
class DosaAssistantConfig {
  const DosaAssistantConfig({
    required this.enabled,
    required this.scriptUrl,
    required this.publishableKey,
    this.documentedAttributes = const <String, String>{},
  });

  /// Lee la configuración del build. Sin `--dart-define`, todo queda apagado.
  factory DosaAssistantConfig.fromEnvironment() => const DosaAssistantConfig(
    enabled: bool.fromEnvironment(
      'DOSA_ASSISTANT_ENABLED',
      defaultValue: false,
    ),
    scriptUrl: String.fromEnvironment('DOSA_ASSISTANT_SCRIPT_URL'),
    publishableKey: String.fromEnvironment(
      'DOSA_ASSISTANT_PUBLISHABLE_KEY',
    ),
  );

  final bool enabled;
  final String scriptUrl;
  final String publishableKey;

  /// Atributos documentados por el proveedor. **Nadie los pasa hoy**: existen
  /// como parámetro para poder probar el camino de montaje sin inventar
  /// atributos en el código de producción.
  final Map<String, String> documentedAttributes;

  /// La clave entregada empieza por `pk_live_`, es decir, es de producción.
  bool get hasProductionKey => publishableKey.trim().startsWith('pk_live_');

  /// Atributos del componente oficial `<dosa-cert-wizard>`.
  ///
  /// **Vacío por decisión.** DOSA entregó el script y el nombre del componente,
  /// pero no documentó sus atributos. Se deja el punto único donde añadirlos:
  /// cuando el proveedor los documente, se completan en `documentedAttributes`
  /// y nada más cambia.
  Map<String, String> get componentAttributes => documentedAttributes;

  /// Motivos por los que el asistente no puede montarse. Lista vacía = se puede.
  List<DosaAssistantBlockReason> get blockers {
    final reasons = <DosaAssistantBlockReason>[];
    if (!enabled) reasons.add(DosaAssistantBlockReason.disabled);
    if (scriptUrl.trim().isEmpty) {
      reasons.add(DosaAssistantBlockReason.missingScriptUrl);
    }
    if (publishableKey.trim().isEmpty) {
      reasons.add(DosaAssistantBlockReason.missingPublishableKey);
    } else if (hasProductionKey) {
      reasons.add(DosaAssistantBlockReason.productionKeyNotAllowed);
    }
    if (componentAttributes.isEmpty) {
      reasons.add(DosaAssistantBlockReason.componentAttributesUndocumented);
    }
    return reasons;
  }

  /// `true` solo si no hay ningún bloqueo. Hoy siempre es `false`.
  bool get canMount => blockers.isEmpty;

  /// Etiqueta segura de la clave: SOLO el prefijo. El valor nunca se muestra.
  String get maskedKey {
    final value = publishableKey.trim();
    if (value.isEmpty) return 'sin clave';
    if (value.startsWith('pk_live_')) return 'pk_live_…';
    if (value.startsWith('pk_test_')) return 'pk_test_…';
    return 'clave configurada';
  }

  /// Texto de una frase para el administrador. Sin códigos técnicos ni valores.
  String get blockedMessage {
    final reasons = blockers;
    if (reasons.isEmpty) return 'El asistente está listo para montarse.';
    if (reasons.contains(DosaAssistantBlockReason.productionKeyNotAllowed)) {
      return 'La única clave disponible es de producción ($maskedKey). '
          'El asistente no se carga hasta disponer de una configuración de '
          'prueba autorizada.';
    }
    if (reasons.contains(DosaAssistantBlockReason.disabled)) {
      return 'El asistente de certificación automática está desactivado.';
    }
    if (reasons.contains(DosaAssistantBlockReason.missingScriptUrl)) {
      return 'Falta la URL del script del asistente en la configuración.';
    }
    if (reasons.contains(DosaAssistantBlockReason.missingPublishableKey)) {
      return 'Falta la clave publicable del componente.';
    }
    return 'Falta el contrato de atributos del componente.';
  }
}
