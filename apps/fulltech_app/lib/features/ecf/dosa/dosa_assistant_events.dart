import 'dosa_assistant_config.dart';
import 'dosa_assistant_session.dart';

/// Evento emitido por el componente oficial `dosa-cert-wizard`.
///
/// **No es de confianza.** Lo genera código que corre en el navegador: el propio
/// iframe del proveedor, pero también cualquier script de la página, una consola
/// de desarrollo o una extensión. Por eso el evento sirve para **pintar estado y
/// pedir una recarga al backend**, nunca para escribir estado fiscal.
///
/// El script declara los tipos válidos en `ALLOWED_EVENTS`:
/// `cert:ready`, `cert:step`, `cert:postulacion`, `cert:attention`,
/// `cert:complete`, `cert:error`, `cert:resize`, `cert:asistida_pago`,
/// `cert:asistida_pagada`, `cert:blocked`.
class DosaAssistantEvent {
  const DosaAssistantEvent({
    required this.type,
    this.payload = const <String, dynamic>{},
  });

  final String type;
  final Map<String, dynamic> payload;

  /// Siempre `false`: un evento del navegador no acredita nada por sí mismo.
  bool get isTrusted => false;

  /// `true` si el componente pidió recargar estado del backend.
  bool get impliesRefresh => type != 'cert:resize';

  /// Identificador que reporta el proveedor, si lo hay. Es solo una pista.
  String? get providerId {
    for (final key in const ['id', 'postulacionId', 'postulacion_id']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
    }
    return null;
  }

  String? get stage {
    final value = payload['etapa'] ?? payload['step'] ?? payload['stage'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  String? get status {
    final value = payload['estado'] ?? payload['status'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Código de «el contribuyente tiene que hacer algo».
  String? get attentionCode {
    final value = payload['codigo'] ?? payload['code'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Mensaje del proveedor. Se usa tal cual, sin interpretarlo.
  String? get message {
    final value = payload['message'] ?? payload['mensaje'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Origen que el componente reporta cuando el navegador bloquea el iframe.
  String? get blockedOrigin {
    final value = payload['origin'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Fase de UI que corresponde al evento. `null` si el evento no cambia fase.
  DosaAssistantPhase? get phase {
    switch (type) {
      case 'cert:ready':
      case 'cert:step':
        return DosaAssistantPhase.running;
      case 'cert:postulacion':
        return DosaAssistantPhase.running;
      case 'cert:attention':
        return DosaAssistantPhase.attention;
      case 'cert:complete':
        return DosaAssistantPhase.completed;
      case 'cert:error':
        return DosaAssistantPhase.failed;
      case 'cert:blocked':
        return DosaAssistantPhase.originBlocked;
      case 'cert:asistida_pago':
      case 'cert:asistida_pagada':
        return DosaAssistantPhase.attention;
      default:
        return null;
    }
  }

  @override
  String toString() => 'DosaAssistantEvent($type)';
}

/// Construye el evento a partir de lo que llegue del componente.
///
/// Devuelve `null` si el tipo no está en la lista blanca del script: un evento
/// desconocido se descarta en lugar de adivinarse.
DosaAssistantEvent? parseDosaAssistantEvent({
  required String type,
  Map<String, dynamic>? payload,
}) {
  if (!DosaAssistantConfig.allowedEvents.contains(type)) return null;
  return DosaAssistantEvent(
    type: type,
    payload: payload ?? const <String, dynamic>{},
  );
}

/// ¿Este evento puede modificar estado fiscal (crear postulación, marcar
/// aceptación, activar emisión)?
///
/// La respuesta es siempre `false` y es deliberado: el navegador no es una
/// fuente de verdad fiscal. La única vía es que el **backend** confirme con el
/// proveedor y que un humano autorice la activación.
bool mayMutateFiscalState(DosaAssistantEvent event) => false;
