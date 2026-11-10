/// Resultado de un intento de ACTIVACIÓN y AUTORIZACIÓN de emisión.
///
/// Lo devuelve `POST /ecf/dosa/activation/attempt`, que el propio cliente puede
/// llamar: evalúa la evidencia que él mismo produjo y, si está completa, activa
/// la credencial y autoriza la emisión. No hay ningún paso de Fulltech.
///
/// Reglas que la interfaz NO debe romper:
///
/// * `ok: false` **no es un error de red**: es «todavía no puedes facturar», y
///   trae en `blockingReasons` lo que falta. Hay que mostrarlo, no ocultarlo.
/// * Un motivo desconocido se muestra tal cual: esconderlo dejaría al cliente
///   sin saber qué hacer y sin nada que decirle a soporte.
/// * Repetir la llamada es seguro: el backend es idempotente.
class EcfDosaActivationOutcome {
  const EcfDosaActivationOutcome({
    required this.ok,
    required this.companyId,
    required this.certificationStatus,
    required this.changed,
    required this.code,
    required this.environments,
  });

  final bool ok;
  final String companyId;

  /// `AUTHORIZED_SANDBOX`, `PRODUCTION_READY`, `IN_PROGRESS`, … o `null`.
  final String? certificationStatus;

  /// `true` si esta llamada cambió el estado.
  final bool changed;

  /// Código de rechazo global (por ejemplo, falta la configuración e-CF).
  final String? code;

  final List<EcfDosaActivationEnvironment> environments;

  /// ¿La empresa ya puede facturar electrónicamente?
  ///
  /// Solo cuenta producción y sandbox: son los dos estados que el orquestador
  /// de emisión acepta. Cualquier otro significa «sigue en proceso».
  bool get authorized =>
      certificationStatus == 'PRODUCTION_READY' ||
      certificationStatus == 'AUTHORIZED_SANDBOX';

  /// Todo lo que falta, en español y sin repetir.
  ///
  /// Si no hay motivos y tampoco hay autorización, se devuelve un mensaje
  /// genérico: dejar la lista vacía haría creer que no falta nada.
  List<String> get pendingMessages {
    final seen = <String>{};
    final messages = <String>[];
    for (final environment in environments) {
      for (final reason in environment.blockingReasons) {
        final text = describeActivationReason(reason);
        if (seen.add(text)) messages.add(text);
      }
    }
    if (code != null) {
      final text = describeActivationReason(code!);
      if (seen.add(text)) messages.add(text);
    }
    if (messages.isEmpty && !authorized) {
      messages.add(
        'Todavía no hay evidencia suficiente para autorizar la facturación '
        'electrónica.',
      );
    }
    return messages;
  }

  factory EcfDosaActivationOutcome.fromJson(Map<String, dynamic> json) {
    final environments = json['environments'];
    return EcfDosaActivationOutcome(
      ok: json['ok'] == true,
      companyId: (json['companyId'] ?? '').toString(),
      certificationStatus: json['certificationStatus']?.toString(),
      changed: json['changed'] == true,
      code: json['code']?.toString(),
      environments: environments is List
          ? environments
                .whereType<Map>()
                .map(
                  (row) =>
                      EcfDosaActivationEnvironment.fromJson(row.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <EcfDosaActivationEnvironment>[],
    );
  }
}

/// Estado de UNA credencial (ambiente) tras el intento.
class EcfDosaActivationEnvironment {
  const EcfDosaActivationEnvironment({
    required this.environment,
    required this.status,
    required this.activated,
    required this.blockingReasons,
  });

  /// `test` o `production`.
  final String environment;

  /// `PENDING_CONFIRMATION`, `CONFIRMED`, `ACTIVE`, `REVOKED`.
  final String status;
  final bool activated;
  final List<String> blockingReasons;

  /// Nombre legible del ambiente.
  String get label => environment == 'production' ? 'Producción' : 'Certificación';

  factory EcfDosaActivationEnvironment.fromJson(Map<String, dynamic> json) {
    final reasons = json['blockingReasons'];
    return EcfDosaActivationEnvironment(
      environment: (json['environment'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      activated: json['activated'] == true,
      blockingReasons: reasons is List
          ? reasons.map((entry) => entry.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

/// Traduce un código del backend a algo que el cliente entienda.
///
/// Se conserva el código entre paréntesis cuando es nuevo: si el backend añade
/// un motivo, se muestra en crudo en vez de desaparecer.
String describeActivationReason(String code) {
  switch (code) {
    case 'ECF_DOSA_ACTIVATION_RNC_NOT_LINKED':
      return 'Falta vincular el RNC de tu empresa: abre el asistente de DOSA y '
          'completa la postulación.';
    case 'ECF_DOSA_ACTIVATION_POSTULATION_NOT_BOUND':
      return 'DOSA todavía no te asignó un número de postulación. Espera su '
          'respuesta.';
    case 'ECF_DOSA_ACTIVATION_PROVIDER_NOT_CONFIRMED':
      return 'DOSA aún no ha confirmado que terminó tu certificación. Revisa tu '
          'correo por si te pidieron algo más.';
    case 'ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED':
      return 'La DGII aún no ha aprobado tu facturación electrónica.';
    case 'ECF_DOSA_ACTIVATION_DGII_APPROVAL_STALE':
      return 'La aprobación de la DGII que consta es de un intento anterior: '
          'hay que registrarla de nuevo para esta postulación.';
    case 'ECF_DOSA_ACTIVATION_ADMIN_NOT_AUTHORIZED':
      return 'Falta registrar tu autorización de la DGII.';
    case 'ECF_DOSA_ACTIVATION_ADMIN_AUTHORIZATION_STALE':
      return 'Tu autorización registrada es anterior a esta postulación: hay que '
          'registrarla otra vez.';
    case 'ECF_DOSA_ACTIVATION_ADMIN_DECISION_REVOKED':
      return 'La autorización de emisión de tu empresa está revocada. Contacta a '
          'soporte.';
    case 'ECF_DOSA_CREDENTIALS_REVOKED':
      return 'Las credenciales de este ambiente están revocadas y no se '
          'reactivan solas. Contacta a soporte.';
    case 'ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND':
      return 'Tu empresa todavía no inició el trámite de facturación '
          'electrónica.';
    case 'ECF_CERTIFICATION_STATE_BLOCKED':
      return 'Hay un bloqueo pendiente en tu expediente: resuélvelo antes de '
          'continuar.';
    case 'COMPANY_REQUIRED':
      return 'No se pudo identificar tu empresa. Vuelve a iniciar sesión.';
    default:
      return 'Pendiente: $code';
  }
}
