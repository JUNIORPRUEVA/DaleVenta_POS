import 'package:flutter/material.dart';

/// Fase OPERATIVA del comprobante: dónde está el trámite localmente.
///
/// Es una lectura del estado persistido, no un estado paralelo. La máquina de
/// estados del backend (`ecf-document-state-machine.ts`) sigue siendo la única
/// autoridad.
enum EcfOperativePhase {
  draft,
  readyToSend,
  sending,
  awaitingResult,
  settled,
  humanReview,
  cancelled;

  String get label {
    switch (this) {
      case EcfOperativePhase.draft:
        return 'Borrador local';
      case EcfOperativePhase.readyToSend:
        return 'Listo para envío';
      case EcfOperativePhase.sending:
        return 'En envío';
      case EcfOperativePhase.awaitingResult:
        return 'Esperando resultado';
      case EcfOperativePhase.settled:
        return 'Resuelto';
      case EcfOperativePhase.humanReview:
        return 'Requiere revisión';
      case EcfOperativePhase.cancelled:
        return 'Anulado';
    }
  }
}

/// Resultado FISCAL confirmado.
///
/// [accepted] requiere evidencia DGII (`DGII_ACCEPTED`). Una aceptación del
/// proveedor NO es una aceptación de la DGII y por eso es [pending].
enum EcfFiscalOutcome {
  none,
  pending,
  accepted,
  rejected;

  String get label {
    switch (this) {
      case EcfFiscalOutcome.none:
        return 'Sin resultado fiscal';
      case EcfFiscalOutcome.pending:
        return 'Pendiente de confirmación';
      case EcfFiscalOutcome.accepted:
        return 'Aceptado DGII';
      case EcfFiscalOutcome.rejected:
        return 'Rechazado';
    }
  }
}

/// Severidad visual del estado. No implica por sí misma un resultado fiscal.
enum EcfStatusTone { neutral, info, success, warning, danger, muted }

/// Presentación de un estado persistido: etiqueta, significado, fase operativa
/// y resultado fiscal. Nunca promueve ni reinterpreta el estado.
class EcfStatusPresentation {
  const EcfStatusPresentation({
    required this.status,
    required this.label,
    required this.description,
    required this.operative,
    required this.fiscal,
    required this.icon,
    required this.tone,
    this.recognized = true,
  });

  /// Estado exacto devuelto por el backend.
  final String status;

  /// Etiqueta corta para el distintivo de la bandeja.
  final String label;

  /// Qué significa, sin atribuirle una condición fiscal que no está confirmada.
  final String description;

  final EcfOperativePhase operative;
  final EcfFiscalOutcome fiscal;
  final IconData icon;
  final EcfStatusTone tone;

  /// `false` cuando esta versión de la aplicación no conoce el estado: se
  /// muestra tal cual en lugar de clasificarlo por su cuenta.
  final bool recognized;

  bool get isFiscallyAccepted => fiscal == EcfFiscalOutcome.accepted;

  Color color(ColorScheme scheme) {
    switch (tone) {
      case EcfStatusTone.neutral:
        return scheme.onSurfaceVariant;
      case EcfStatusTone.info:
        return scheme.primary;
      case EcfStatusTone.success:
        return const Color(0xFF2E7D32);
      case EcfStatusTone.warning:
        return scheme.tertiary;
      case EcfStatusTone.danger:
        return scheme.error;
      case EcfStatusTone.muted:
        return scheme.outline;
    }
  }
}

/// Traduce el estado persistido a su presentación. Es una función pura sobre
/// los estados que existen en el esquema; no deduce nada del contexto.
EcfStatusPresentation presentEcfStatus(String rawStatus) {
  final status = rawStatus.trim().toUpperCase();
  switch (status) {
    case 'LOCAL_DRAFT':
      return _of(
        rawStatus,
        'Borrador local',
        'Preparado en el sistema; todavía no pasó la validación local.',
        EcfOperativePhase.draft,
        EcfFiscalOutcome.none,
        Icons.edit_note_outlined,
        EcfStatusTone.neutral,
      );
    case 'LOCAL_VALIDATION_PENDING':
      return _of(
        rawStatus,
        'Validación local pendiente',
        'Pendiente de validación local. No se ha enviado a ningún proveedor.',
        EcfOperativePhase.draft,
        EcfFiscalOutcome.none,
        Icons.pending_actions_outlined,
        EcfStatusTone.info,
      );
    case 'LOCAL_VALIDATED':
      return _of(
        rawStatus,
        'Listo localmente',
        'Validado en local y sin enviar. No tiene resultado fiscal.',
        EcfOperativePhase.readyToSend,
        EcfFiscalOutcome.none,
        Icons.check_circle_outline,
        EcfStatusTone.info,
      );
    case 'READY_TO_SEND':
      return _of(
        rawStatus,
        'Listo para enviar',
        'Validado y en cola de envío. Todavía no se envió.',
        EcfOperativePhase.readyToSend,
        EcfFiscalOutcome.none,
        Icons.outbox_outlined,
        EcfStatusTone.info,
      );
    case 'SEND_PENDING':
      return _of(
        rawStatus,
        'Envío pendiente',
        'El envío está autorizado pero aún no comenzó.',
        EcfOperativePhase.sending,
        EcfFiscalOutcome.none,
        Icons.schedule_send_outlined,
        EcfStatusTone.info,
      );
    case 'SEND_IN_PROGRESS':
      return _of(
        rawStatus,
        'Envío en curso',
        'Se está enviando al proveedor. El resultado aún no se conoce.',
        EcfOperativePhase.sending,
        EcfFiscalOutcome.none,
        Icons.cloud_upload_outlined,
        EcfStatusTone.info,
      );
    case 'UNKNOWN_RESULT':
      return _of(
        rawStatus,
        'Resultado desconocido',
        'No se pudo confirmar el resultado. Requiere conciliación antes de '
            'cualquier nuevo envío.',
        EcfOperativePhase.awaitingResult,
        EcfFiscalOutcome.none,
        Icons.help_outline_rounded,
        EcfStatusTone.warning,
      );
    case 'PROVIDER_ACCEPTED':
      return _of(
        rawStatus,
        'Aceptado por el proveedor',
        'El proveedor aceptó la solicitud. NO es una aceptación de la DGII: '
            'queda pendiente de confirmación.',
        EcfOperativePhase.awaitingResult,
        EcfFiscalOutcome.pending,
        Icons.cloud_done_outlined,
        EcfStatusTone.info,
      );
    case 'PROVIDER_REJECTED':
      return _of(
        rawStatus,
        'Rechazado por el proveedor',
        'El proveedor rechazó la solicitud. No se considera emitido.',
        EcfOperativePhase.humanReview,
        EcfFiscalOutcome.rejected,
        Icons.gpp_bad_outlined,
        EcfStatusTone.danger,
      );
    case 'DGII_STATUS_PENDING':
      return _of(
        rawStatus,
        'Consulta DGII pendiente',
        'Enviado y pendiente de confirmación del estado en la DGII.',
        EcfOperativePhase.awaitingResult,
        EcfFiscalOutcome.pending,
        Icons.hourglass_top_rounded,
        EcfStatusTone.info,
      );
    case 'DGII_ACCEPTED':
      return _of(
        rawStatus,
        'Aceptado DGII',
        'Aceptado con evidencia registrada.',
        EcfOperativePhase.settled,
        EcfFiscalOutcome.accepted,
        Icons.verified_outlined,
        EcfStatusTone.success,
      );
    case 'DGII_REJECTED':
      return _of(
        rawStatus,
        'Rechazado DGII',
        'Rechazado con evidencia registrada.',
        EcfOperativePhase.settled,
        EcfFiscalOutcome.rejected,
        Icons.cancel_outlined,
        EcfStatusTone.danger,
      );
    case 'HUMAN_REVIEW_REQUIRED':
      return _of(
        rawStatus,
        'Requiere revisión',
        'Marcado para revisión humana. No se resuelve automáticamente.',
        EcfOperativePhase.humanReview,
        EcfFiscalOutcome.none,
        Icons.report_problem_outlined,
        EcfStatusTone.warning,
      );
    case 'CANCELLED':
      return _of(
        rawStatus,
        'Anulado',
        'Anulado en local. No se emitió.',
        EcfOperativePhase.cancelled,
        EcfFiscalOutcome.none,
        Icons.block_outlined,
        EcfStatusTone.muted,
      );
    default:
      // Un estado que esta versión no conoce NO se clasifica por su cuenta ni
      // se presenta como aceptado: se muestra literal y se pide revisión.
      return EcfStatusPresentation(
        status: rawStatus,
        label: rawStatus.isEmpty ? 'Sin estado' : rawStatus,
        description:
            'Estado no reconocido por esta versión de la aplicación. Revisa el '
            'comprobante antes de dar por válido su resultado.',
        operative: EcfOperativePhase.humanReview,
        fiscal: EcfFiscalOutcome.none,
        icon: Icons.question_mark_outlined,
        tone: EcfStatusTone.warning,
        recognized: false,
      );
  }
}

EcfStatusPresentation _of(
  String status,
  String label,
  String description,
  EcfOperativePhase operative,
  EcfFiscalOutcome fiscal,
  IconData icon,
  EcfStatusTone tone,
) {
  return EcfStatusPresentation(
    status: status,
    label: label,
    description: description,
    operative: operative,
    fiscal: fiscal,
    icon: icon,
    tone: tone,
  );
}

/// Todos los estados persistidos que esta versión reconoce. Se usa en pruebas
/// para garantizar que el mapeo no queda incompleto cuando el esquema crezca.
const List<String> kEcfKnownStatuses = <String>[
  'LOCAL_DRAFT',
  'LOCAL_VALIDATION_PENDING',
  'LOCAL_VALIDATED',
  'READY_TO_SEND',
  'SEND_PENDING',
  'SEND_IN_PROGRESS',
  'UNKNOWN_RESULT',
  'PROVIDER_ACCEPTED',
  'PROVIDER_REJECTED',
  'DGII_STATUS_PENDING',
  'DGII_ACCEPTED',
  'DGII_REJECTED',
  'HUMAN_REVIEW_REQUIRED',
  'CANCELLED',
];
