import 'package:flutter/foundation.dart';

/// Estado visible del asistente dentro del expediente existente.
///
/// No es un flujo nuevo: describe cómo se representa el asistente oficial en la
/// pantalla de Postulación Inteligente que ya existe.
enum DosaAssistantPhase {
  /// El asistente no puede usarse (bandera apagada o contrato incompleto).
  blocked,

  /// Listo para iniciar; todavía no hay postulación.
  idle,

  /// Postulación en curso; el proceso se puede reanudar.
  running,

  /// El contribuyente tiene que hacer algo (`cert:attention`). Sigue en curso.
  attention,

  /// El navegador no permitió enmarcar el asistente (`cert:blocked`): el dominio
  /// de esta instalación no está registrado en el integrador.
  originBlocked,

  /// El proveedor reportó finalización. **No** implica autorización fiscal.
  completed,

  /// Fallo con código estable; se puede reanudar sin duplicar la postulación.
  failed,
}

/// Vinculación explícita FullPOS → RNC → postulación DOSA.
///
/// La identidad fiscal viaja siempre desde el servidor (empresa autenticada),
/// nunca desde un valor que el usuario escriba en el asistente.
@immutable
class DosaAssistantBinding {
  const DosaAssistantBinding({
    required this.companyId,
    required this.taxId,
    this.postulationExternalId,
  });

  /// Empresa de FullPOS dueña del expediente.
  final String companyId;

  /// RNC propio de esa empresa (su identidad fiscal, no la del partner).
  final String taxId;

  /// Identificador de la postulación en el proveedor, si ya existe.
  final String? postulationExternalId;

  bool get isComplete =>
      companyId.trim().isNotEmpty && taxId.trim().isNotEmpty;

  /// Clave estable de la vinculación. Dos empresas con el mismo RNC no pueden
  /// compartir clave porque el `companyId` forma parte de ella.
  String get dedupeKey =>
      'dosa:${companyId.trim()}:${_normalizeTaxId(taxId)}';

  DosaAssistantBinding copyWith({String? postulationExternalId}) =>
      DosaAssistantBinding(
        companyId: companyId,
        taxId: taxId,
        postulationExternalId:
            postulationExternalId ?? this.postulationExternalId,
      );

  static String _normalizeTaxId(String value) =>
      value.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
}

/// Sesión del asistente para una vinculación concreta.
@immutable
class DosaAssistantSession {
  const DosaAssistantSession({
    required this.binding,
    required this.phase,
    this.message,
    this.errorCode,
  });

  const DosaAssistantSession.blocked(this.binding, {this.message})
    : phase = DosaAssistantPhase.blocked,
      errorCode = null;

  final DosaAssistantBinding binding;
  final DosaAssistantPhase phase;

  /// Mensaje apto para el usuario. Nunca contiene claves ni datos del proveedor.
  final String? message;

  /// Código estable para diagnóstico. Tampoco contiene secretos.
  final String? errorCode;

  /// Reanudar solo tiene sentido si había un proceso en marcha o falló.
  bool get isResumable =>
      phase == DosaAssistantPhase.running ||
      phase == DosaAssistantPhase.attention ||
      phase == DosaAssistantPhase.failed;

  /// Un evento del proveedor puede dejar el proceso en `completed`, pero eso
  /// **no** autoriza emisión ni acredita aprobación de la DGII. Ambas cosas
  /// dependen de un acto humano y de las compuertas fiscales del backend.
  bool get impliesFiscalAuthorization => false;

  /// `cert:complete` significa «el asistente terminó», no «la DGII aprobó».
  bool get isDgiiApproval => false;

  DosaAssistantSession copyWith({
    DosaAssistantPhase? phase,
    String? message,
    String? errorCode,
  }) => DosaAssistantSession(
    binding: binding,
    phase: phase ?? this.phase,
    message: message ?? this.message,
    errorCode: errorCode ?? this.errorCode,
  );
}

/// Decisión de apertura de una postulación nueva.
enum DosaStartStatus { allowed, missingFiscalIdentity, duplicatePostulation }

@immutable
class DosaStartDecision {
  const DosaStartDecision(this.status, {this.message});

  final DosaStartStatus status;
  final String? message;

  bool get allowed => status == DosaStartStatus.allowed;
}

/// ¿Se puede abrir una postulación nueva para esta vinculación?
///
/// Evita duplicados sin depender del proveedor: si ya existe una sesión de la
/// MISMA vinculación en curso o completada, no se abre otra. Un fallo sí permite
/// reanudar la existente, no crear una segunda.
DosaStartDecision canStartPostulation({
  required DosaAssistantBinding binding,
  required List<DosaAssistantSession> existing,
}) {
  if (!binding.isComplete) {
    return const DosaStartDecision(
      DosaStartStatus.missingFiscalIdentity,
      message:
          'La empresa no tiene identificada su RNC. Sincroniza los datos de '
          'empresa antes de iniciar la postulación.',
    );
  }
  final same = existing.where(
    (session) =>
        session.binding.dedupeKey == binding.dedupeKey &&
        (session.phase == DosaAssistantPhase.running ||
            session.phase == DosaAssistantPhase.attention ||
            session.phase == DosaAssistantPhase.completed),
  );
  if (same.isNotEmpty) {
    return const DosaStartDecision(
      DosaStartStatus.duplicatePostulation,
      message:
          'Ya existe una postulación de esta empresa. Se reanuda la existente '
          'en lugar de crear otra.',
    );
  }
  return const DosaStartDecision(DosaStartStatus.allowed);
}
