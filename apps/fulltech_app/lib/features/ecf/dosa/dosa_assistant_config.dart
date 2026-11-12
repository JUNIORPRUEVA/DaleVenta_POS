import 'package:flutter/foundation.dart';

/// Motivo por el que el asistente oficial no puede montarse.
///
/// Solo motivos contrastados con `dosa-cert.js`. Se eliminó el bloqueo por
/// `pk_test_` porque el script no distingue `pk_test_`/`pk_live_`: solo documenta
/// `publishable-key="pk_..."`.
enum DosaAssistantBlockReason {
  /// La bandera está apagada. Es el estado por defecto.
  disabled,

  /// La URL del script no es la oficial de DOSA.
  scriptUrlNotOfficial,

  /// No hay ni `session-url` ni `publishable-key`: no hay nada que montar.
  missingSessionSource,

  /// `session-url` no apunta a un origen permitido o no es https.
  sessionUrlNotAllowed,
}

/// Configuración del asistente DOSA.
///
/// Fuente de verdad: el propio script oficial
/// `https://dosasystem.com/static/embed/dosa-cert.js`, que declara
///
/// ```js
/// static get observedAttributes() {
///   return ['session-url', 'publishable-key', 'base-url', 'theme', 'height'];
/// }
/// ```
///
/// y los eventos `cert:ready`, `cert:step`, `cert:postulacion`, `cert:attention`,
/// `cert:complete`, `cert:error`, `cert:resize`, `cert:asistida_pago`,
/// `cert:asistida_pagada` y `cert:blocked`.
///
/// Dos aclaraciones que el script deja explícitas:
///
/// * La forma recomendada es `session-url`: un enlace de sesión que crea **el
///   backend del partner** con `POST /api/certificacion/sesiones` y su *secret
///   key*. El secreto es de servidor y nunca pasa por el cliente.
/// * La `publishable-key` es pública por diseño (viaja en una URL). No se exige
///   ningún prefijo de entorno porque el script no documenta esa distinción.
@immutable
class DosaAssistantConfig {
  const DosaAssistantConfig({
    required this.enabled,
    this.scriptUrl = officialScriptUrl,
    this.sessionUrl,
    this.publishableKey,
    this.baseUrl,
    this.theme = 'light',
    this.height = 720,
  });

  /// Origen oficial del script. Único admitido.
  static const String officialOrigin = 'https://dosasystem.com';
  static const String officialScriptUrl =
      'https://dosasystem.com/static/embed/dosa-cert.js';

  /// Atributos que el componente observa. No se envía ninguno fuera de la lista.
  static const Set<String> allowedAttributes = {
    'session-url',
    'publishable-key',
    'base-url',
    'theme',
    'height',
  };

  /// Eventos que el componente emite. Cualquier otro se descarta.
  static const Set<String> allowedEvents = {
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
  };

  /// Lee la configuración del build. Sin `--dart-define`, todo queda apagado.
  factory DosaAssistantConfig.fromEnvironment() => const DosaAssistantConfig(
    enabled: bool.fromEnvironment(
      'DOSA_ASSISTANT_ENABLED',
      defaultValue: false,
    ),
    scriptUrl: String.fromEnvironment(
      'DOSA_ASSISTANT_SCRIPT_URL',
      defaultValue: officialScriptUrl,
    ),
    sessionUrl: String.fromEnvironment('DOSA_ASSISTANT_SESSION_URL'),
    publishableKey: String.fromEnvironment('DOSA_ASSISTANT_PUBLISHABLE_KEY'),
    baseUrl: String.fromEnvironment('DOSA_ASSISTANT_BASE_URL'),
  );

  final bool enabled;
  final String scriptUrl;

  /// Enlace de sesión creado por NUESTRO backend. Forma recomendada.
  final String? sessionUrl;

  /// Clave publicable (flujo anterior, sigue funcionando). Pública, no secreta.
  final String? publishableKey;

  /// Base para el flujo anterior (`base-url`).
  final String? baseUrl;

  final String theme;
  final double height;

  bool get hasSessionUrl => (sessionUrl ?? '').trim().isNotEmpty;
  bool get hasPublishableKey => (publishableKey ?? '').trim().isNotEmpty;

  /// El script debe servirse desde el origen oficial y por https.
  bool get isScriptUrlOfficial => _isOfficialHttpsUrl(scriptUrl);

  /// La sesión debe ser https y del origen oficial.
  bool get isSessionUrlAllowed {
    if (!hasSessionUrl) return true;
    return _isOfficialHttpsUrl(sessionUrl!);
  }

  /// Atributos a aplicar al elemento: solo los que el script observa y solo si
  /// tienen valor. `session-url` manda sobre el flujo antiguo, igual que en el
  /// componente oficial.
  Map<String, String> get componentAttributes {
    final attributes = <String, String>{};
    void put(String key, String? value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isEmpty) return;
      if (!allowedAttributes.contains(key)) return;
      attributes[key] = trimmed;
    }

    if (hasSessionUrl) {
      put('session-url', sessionUrl);
    } else {
      put('publishable-key', publishableKey);
      put('base-url', baseUrl);
    }
    put('theme', theme);
    put('height', height.round().toString());
    return attributes;
  }

  /// Motivos por los que el asistente no puede montarse. Lista vacía = se puede.
  List<DosaAssistantBlockReason> get blockers {
    final reasons = <DosaAssistantBlockReason>[];
    if (!enabled) reasons.add(DosaAssistantBlockReason.disabled);
    if (!isScriptUrlOfficial) {
      reasons.add(DosaAssistantBlockReason.scriptUrlNotOfficial);
    }
    if (!hasSessionUrl && !hasPublishableKey) {
      reasons.add(DosaAssistantBlockReason.missingSessionSource);
    }
    if (hasSessionUrl && !isSessionUrlAllowed) {
      reasons.add(DosaAssistantBlockReason.sessionUrlNotAllowed);
    }
    return reasons;
  }

  /// `true` solo si no hay ningún bloqueo.
  bool get canMount => blockers.isEmpty;

  /// Etiqueta segura de la clave: solo el prefijo. El valor nunca se muestra.
  String get maskedKey {
    final value = (publishableKey ?? '').trim();
    if (value.isEmpty) return 'sin clave';
    return value.length <= 6 ? 'pk_…' : '${value.substring(0, 6)}…';
  }

  /// Texto de una frase para el administrador. Sin valores sensibles.
  String get blockedMessage {
    final reasons = blockers;
    if (reasons.isEmpty) return 'El asistente está listo para montarse.';
    if (reasons.contains(DosaAssistantBlockReason.disabled)) {
      return 'El asistente de certificación automática está desactivado.';
    }
    if (reasons.contains(DosaAssistantBlockReason.scriptUrlNotOfficial)) {
      return 'El script del asistente no se sirve desde el origen oficial.';
    }
    if (reasons.contains(DosaAssistantBlockReason.sessionUrlNotAllowed)) {
      return 'El enlace de sesión no apunta a un origen permitido.';
    }
    return 'Falta el enlace de sesión que emite el servidor.';
  }

  static bool _isOfficialHttpsUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') return false;
    return 'https://${uri.host}' == officialOrigin;
  }
}
