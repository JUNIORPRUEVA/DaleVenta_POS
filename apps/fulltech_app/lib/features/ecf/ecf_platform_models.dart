/// Modelos de la superficie de PLATAFORMA (personal de Fulltech).
///
/// Son deliberadamente de solo lectura sobre el expediente: la decisión viaja
/// al backend y es él quien aplica la política de estados. Ninguno de estos
/// modelos puede declarar por sí mismo una autorización oficial: el indicador
/// `hasOfficialAuthorization` lo calcula el servidor a partir del registro.
library;

DateTime? _date(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String _text(dynamic value) => value is String ? value : '';

String? _nullableText(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

/// Fila de la bandeja multiempresa.
class EcfPlatformApplication {
  const EcfPlatformApplication({
    required this.companyId,
    required this.companyName,
    required this.state,
    required this.reviewState,
    required this.observations,
    required this.updatedAt,
    required this.hasOfficialAuthorization,
  });

  final String companyId;
  final String? companyName;
  final String state;
  final String? reviewState;
  final String? observations;
  final DateTime? updatedAt;
  final bool hasOfficialAuthorization;

  factory EcfPlatformApplication.fromJson(Map<String, dynamic> json) {
    return EcfPlatformApplication(
      companyId: _text(json['companyId']),
      companyName: _nullableText(json['companyName']),
      state: _text(json['state']),
      reviewState: _nullableText(json['reviewState']),
      observations: _nullableText(json['observations']),
      updatedAt: _date(json['updatedAt']),
      hasOfficialAuthorization: json['hasOfficialAuthorization'] == true,
    );
  }
}

/// Página de la bandeja. El total es el del servidor, nunca una estimación.
class EcfPlatformApplicationPage {
  const EcfPlatformApplicationPage({
    required this.items,
    required this.total,
    required this.take,
    required this.skip,
  });

  final List<EcfPlatformApplication> items;
  final int total;
  final int take;
  final int skip;
}

/// Metadatos de una evidencia del expediente.
///
/// No incluye la referencia de almacenamiento: esa ubicación es interna del
/// servidor y no se expone en la superficie de plataforma.
class EcfPlatformEvidence {
  const EcfPlatformEvidence({
    required this.id,
    required this.kind,
    required this.source,
    required this.reviewStatus,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    required this.reviewedAt,
    required this.reviewNote,
  });

  final String id;
  final String kind;
  final String source;
  final String reviewStatus;
  final String? fileName;
  final String? mimeType;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewNote;

  factory EcfPlatformEvidence.fromJson(Map<String, dynamic> json) {
    return EcfPlatformEvidence(
      id: _text(json['id']),
      kind: _text(json['kind']),
      source: _text(json['source']),
      reviewStatus: _text(json['reviewStatus']),
      fileName: _nullableText(json['fileName']),
      mimeType: _nullableText(json['mimeType']),
      createdAt: _date(json['createdAt']),
      reviewedAt: _date(json['reviewedAt']),
      reviewNote: _nullableText(json['reviewNote']),
    );
  }
}

/// Expediente completo de una empresa para revisión.
class EcfPlatformApplicationDetail {
  const EcfPlatformApplicationDetail({
    required this.companyId,
    required this.companyName,
    required this.rnc,
    required this.state,
    required this.reviewState,
    required this.observations,
    required this.startedAt,
    required this.authorizedAt,
    required this.authorizationSource,
    required this.externalId,
    required this.hasOfficialAuthorization,
    required this.evidence,
  });

  final String companyId;
  final String? companyName;
  final String? rnc;
  final String state;
  final String? reviewState;
  final String? observations;
  final DateTime? startedAt;
  final DateTime? authorizedAt;
  final String authorizationSource;
  final String? externalId;
  final bool hasOfficialAuthorization;
  final List<EcfPlatformEvidence> evidence;

  factory EcfPlatformApplicationDetail.fromJson(Map<String, dynamic> json) {
    final rawEvidence = json['evidence'];
    final evidence = rawEvidence is List
        ? rawEvidence
              .whereType<Map>()
              .map(
                (row) =>
                    EcfPlatformEvidence.fromJson(row.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <EcfPlatformEvidence>[];
    return EcfPlatformApplicationDetail(
      companyId: _text(json['companyId']),
      companyName: _nullableText(json['companyName']),
      rnc: _nullableText(json['rnc']),
      state: _text(json['state']),
      reviewState: _nullableText(json['reviewState']),
      observations: _nullableText(json['observations']),
      startedAt: _date(json['startedAt']),
      authorizedAt: _date(json['authorizedAt']),
      authorizationSource: _text(json['authorizationSource']),
      externalId: _nullableText(json['externalId']),
      hasOfficialAuthorization: json['hasOfficialAuthorization'] == true,
      evidence: evidence,
    );
  }
}

/// Estado de seguimiento de un requisito del catálogo cerrado.
///
/// Coincide con `ECF_DGII_REQUIREMENT_STATUSES` del backend. No es un estado
/// fiscal: describe la gestión administrativa del requisito.
const List<String> ecfPlatformRequirementStatuses = <String>[
  'PENDING',
  'IN_PROGRESS',
  'BLOCKED',
  'COMPLETED',
  'NOT_APPLICABLE',
];

/// Un requisito del expediente con su seguimiento interno.
///
/// `tracking` llega con `status: null` cuando la empresa todavía no lo ha
/// tocado: la pantalla lo muestra como «sin revisar» en vez de inventar un
/// estado.
class EcfPlatformRequirement {
  const EcfPlatformRequirement({
    required this.key,
    required this.label,
    required this.mandatory,
    required this.automatable,
    required this.status,
    required this.note,
    required this.updatedAt,
  });

  final String key;
  final String label;
  final bool mandatory;
  final bool automatable;
  final String? status;
  final String? note;
  final DateTime? updatedAt;

  /// `true` cuando no hay seguimiento registrado todavía.
  bool get isUntouched => status == null;

  factory EcfPlatformRequirement.fromJson(Map<String, dynamic> json) {
    final rawTracking = json['tracking'];
    final tracking = rawTracking is Map
        ? rawTracking.cast<String, dynamic>()
        : const <String, dynamic>{};
    return EcfPlatformRequirement(
      key: _text(json['key']),
      label: _text(json['label']),
      mandatory: json['mandatory'] == true,
      automatable: json['automatable'] == true,
      status: _nullableText(tracking['status']),
      note: _nullableText(tracking['note']),
      updatedAt: _date(tracking['updatedAt']) ?? _date(json['updatedAt']),
    );
  }
}

/// Paso del motor de activación tal como lo ve la plataforma.
class EcfPlatformActivationStep {
  const EcfPlatformActivationStep({
    required this.key,
    required this.label,
    required this.className,
    required this.status,
    required this.resolved,
    required this.executable,
    required this.awaiting,
  });

  final String key;
  final String label;
  final String className;
  final String status;
  final bool resolved;
  final bool executable;
  final String? awaiting;

  /// Lo resuelve el cliente; la plataforma no puede hacerlo por él.
  bool get isClientAction => className == 'CLIENT_ACTION';

  /// No se mueve hasta que la DGII decida.
  bool get isAuthorityWait => className == 'AUTHORITY_WAIT';

  factory EcfPlatformActivationStep.fromJson(Map<String, dynamic> json) {
    return EcfPlatformActivationStep(
      key: _text(json['key']),
      label: _text(json['label']),
      className: _text(json['className']),
      status: _text(json['status']),
      resolved: json['resolved'] == true,
      executable: json['executable'] == true,
      awaiting: _nullableText(json['awaiting']),
    );
  }
}

/// Estado del motor de activación de una empresa.
///
/// Es de solo lectura a propósito: la plataforma supervisa el avance, no lo
/// produce. Ejecutar pasos sigue siendo de la empresa dueña del expediente.
class EcfPlatformActivation {
  const EcfPlatformActivation({
    required this.stage,
    required this.transport,
    required this.realTransportEnabled,
    required this.resolvedCount,
    required this.total,
    required this.percent,
    required this.steps,
  });

  final String stage;
  final String transport;
  final bool realTransportEnabled;
  final int resolvedCount;
  final int total;
  final int percent;
  final List<EcfPlatformActivationStep> steps;

  factory EcfPlatformActivation.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? (json['summary'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawSteps = json['steps'];
    return EcfPlatformActivation(
      stage: _text(summary['stage']),
      transport: _text(json['transport']),
      realTransportEnabled: json['realTransportEnabled'] == true,
      resolvedCount: summary['resolvedCount'] is num
          ? (summary['resolvedCount'] as num).toInt()
          : 0,
      total: summary['total'] is num ? (summary['total'] as num).toInt() : 0,
      percent: summary['percent'] is num
          ? (summary['percent'] as num).toInt()
          : 0,
      steps: rawSteps is List
          ? rawSteps
                .whereType<Map>()
                .map(
                  (row) => EcfPlatformActivationStep.fromJson(
                    row.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <EcfPlatformActivationStep>[],
    );
  }
}

/// Alcance con el que el personal de plataforma está accediendo al expediente.
///
/// Lo concede la empresa y caduca. Se muestra para que la asistencia temporal no
/// se confunda con un permiso permanente, y para que el revisor sepa qué puede
/// hacer y qué no en esta visita.
class EcfPlatformAccess {
  const EcfPlatformAccess({
    required this.companyId,
    this.scopes = const <String>[],
    this.reason,
    this.expiresAt,
  });

  final String companyId;
  final List<String> scopes;
  final String? reason;
  final DateTime? expiresAt;

  bool get hasGrant => scopes.isNotEmpty;

  /// `true` cuando la concesión solo permite mirar: no se pueden revisar
  /// requisitos ni evidencias.
  bool get isReadOnlyOnly =>
      hasGrant &&
      !scopes.contains("REVIEW_EVIDENCE") &&
      !scopes.contains("REQUEST_CORRECTION");

  factory EcfPlatformAccess.fromJson(Map<String, dynamic> json) {
    final grant = json['grant'];
    if (grant is! Map) {
      return EcfPlatformAccess(
        companyId: (json['companyId'] ?? '') as String,
      );
    }
    final map = grant.cast<String, dynamic>();
    final rawScopes = map['scopes'];
    return EcfPlatformAccess(
      companyId: (json['companyId'] ?? '') as String,
      scopes: rawScopes is List
          ? rawScopes.whereType<String>().toList(growable: false)
          : const <String>[],
      reason: map['reason'] as String?,
      expiresAt: map['expiresAt'] is String
          ? DateTime.tryParse(map['expiresAt'] as String)?.toLocal()
          : null,
    );
  }
}
