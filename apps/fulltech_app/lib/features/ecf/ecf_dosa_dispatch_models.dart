/// Resultado de un DESPACHO AUTORIZADO al proveedor DOSA.
///
/// Reglas que este modelo hace explícitas y que la interfaz no debe romper:
///
/// * Un rechazo fiscal llega como `ok: false` con un `code` y una lista de
///   `blockingReasons`. **No** es un error de red: hay que mostrar el motivo.
/// * `result: STOPPED_REVIEW_REQUIRED` significa que el comprobante quedó en
///   revisión humana. Nunca es aceptación de la DGII.
/// * `FISCAL_RESULT_RECORDED` identifica un resultado fiscal comunicado por DOSA
///   que el servidor correlacionó y guardó con la evidencia del envío.
/// * `canRetryPost` es siempre `false`: reintentar a ciegas un documento ya
///   intentado puede duplicar el e-CF.
class EcfDosaDispatchOutcome {
  const EcfDosaDispatchOutcome({
    required this.ok,
    required this.code,
    required this.blockingReasons,
    required this.result,
    required this.correlated,
    required this.encf,
    required this.environment,
    required this.httpStatus,
    required this.providerOutcome,
    required this.safeCode,
    required this.sequenceConsumed,
  });

  final bool ok;
  final String? code;
  final List<String> blockingReasons;
  final String? result;
  final bool correlated;
  final String? encf;
  final String? environment;
  final int? httpStatus;
  final String providerOutcome;
  final String? safeCode;
  final bool? sequenceConsumed;

  /// Un reintento ciego está prohibido por diseño.
  static const bool canRetryPost = false;

  /// Mensaje para la persona que opera el POS.
  ///
  /// Traduce los códigos del backend a algo comprensible sin ocultar el motivo
  /// técnico: si el operador tiene que llamar a soporte, necesita el código.
  String get message {
    if (ok) {
      if (result == 'FISCAL_RESULT_RECORDED') {
        if (safeCode == 'ECF_DOSA_OBSERVED_CONDITIONALLY_ACCEPTED') {
          return 'DOSA confirmó una aceptación condicional. '
              'Revisa las observaciones del comprobante; su evidencia quedó registrada.';
        }
        return 'DOSA confirmó la aceptación del comprobante. '
            'El resultado fiscal y su evidencia quedaron registrados.';
      }
      if (result == 'STOPPED_REVIEW_REQUIRED') {
        return 'Enviado. El comprobante queda en revisión: la respuesta del '
            'proveedor no se toma como aceptación de la DGII.';
      }
      return 'Enviado al proveedor.';
    }
    switch (code) {
      case 'ECF_DOSA_GATE_BLOCKED':
        return _gateMessage(blockingReasons);
      case 'ECF_DOSA_DOCUMENT_BLOCKED':
        return 'El comprobante no está listo para transmitirse '
            '(${blockingReasons.join(", ")}).';
      case 'ECF_DOSA_CREDENTIALS_UNAVAILABLE':
        return 'La empresa no tiene credenciales disponibles para este '
            'ambiente. Contacta a soporte.';
      case 'ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED':
        return 'La certificación de la empresa no autoriza la emisión.';
      case 'ECF_DOSA_DISPATCH_PROVIDER_NOT_DOSA':
        return 'La empresa no tiene DOSA como proveedor fiscal.';
      case 'ECF_DOSA_DISPATCH_NOT_PREPARED':
        return 'El comprobante todavía no está preparado.';
      case 'ECF_DOSA_DISPATCH_MAPPING_BLOCKED':
        return 'Los datos fiscales del comprobante no cumplen el contrato del '
            'proveedor (${blockingReasons.join(", ")}).';
      default:
        return 'No se pudo emitir (${code ?? "sin código"}).';
    }
  }

  String _gateMessage(List<String> reasons) {
    if (reasons.any((r) => r.contains('CREDENTIALS_MISSING'))) {
      return 'La empresa no tiene credenciales DOSA.';
    }
    if (reasons.any((r) => r.contains('CREDENTIALS_NOT_ACTIVE'))) {
      return 'Las credenciales están pendientes de confirmación o revocadas.';
    }
    if (reasons.any((r) => r.contains('PRODUCTION_NOT_AUTHORIZED'))) {
      return 'La emisión en producción no está autorizada.';
    }
    if (reasons.any((r) => r.contains('EMISSION_DISABLED'))) {
      return 'La emisión electrónica está deshabilitada en el servidor.';
    }
    if (reasons.any((r) => r.contains('COMPANY_NOT_OPTED_IN'))) {
      return 'La empresa no tiene la facturación electrónica habilitada.';
    }
    if (reasons.any((r) => r.contains('FISCAL_IDENTITY_REJECTED'))) {
      return 'El RNC del comprobante no coincide con el de la empresa.';
    }
    return reasons.isEmpty
        ? 'La compuerta fiscal bloqueó la emisión.'
        : 'La compuerta fiscal bloqueó la emisión (${reasons.join(", ")}).';
  }

  factory EcfDosaDispatchOutcome.fromJson(Map<String, dynamic> json) {
    final observation = json['observation'];
    final map = observation is Map
        ? observation.cast<String, dynamic>()
        : const <String, dynamic>{};
    final reasons = json['blockingReasons'];
    return EcfDosaDispatchOutcome(
      ok: json['ok'] == true,
      code: json['code']?.toString(),
      blockingReasons: reasons is List
          ? reasons.map((entry) => entry.toString()).toList(growable: false)
          : const <String>[],
      result: json['result']?.toString(),
      correlated: json['correlated'] == true,
      encf: json['encf']?.toString(),
      environment: json['environment']?.toString(),
      httpStatus: json['httpStatus'] is num
          ? (json['httpStatus'] as num).toInt()
          : null,
      providerOutcome: (map['providerOutcome'] ?? 'UNKNOWN').toString(),
      safeCode: map['safeCode']?.toString(),
      sequenceConsumed: map['sequenceConsumed'] is bool
          ? map['sequenceConsumed'] as bool
          : null,
    );
  }
}
