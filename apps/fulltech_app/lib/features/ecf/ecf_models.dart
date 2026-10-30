import 'package:flutter/material.dart';

/// Grupo funcional de un comprobante e-CF.
///
/// Es una VISTA del estado persistido, nunca un reemplazo: la máquina de estados
/// fiscal del backend sigue siendo la autoridad. Un resultado desconocido o una
/// observación del proveedor jamás se resuelven solos, por eso viven en
/// [requiresReview] y no en [accepted].
enum EcfStatusGroup {
  pending,
  requiresReview,
  accepted,
  rejected,
  cancelled,
  unknown;

  static EcfStatusGroup fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PENDING':
        return EcfStatusGroup.pending;
      case 'REQUIRES_REVIEW':
        return EcfStatusGroup.requiresReview;
      case 'ACCEPTED':
        return EcfStatusGroup.accepted;
      case 'REJECTED':
        return EcfStatusGroup.rejected;
      case 'CANCELLED':
        return EcfStatusGroup.cancelled;
      default:
        return EcfStatusGroup.unknown;
    }
  }

  /// Valor exacto que espera el backend (`REQUIRES_REVIEW`, no el nombre Dart).
  String get apiValue {
    switch (this) {
      case EcfStatusGroup.pending:
        return 'PENDING';
      case EcfStatusGroup.requiresReview:
        return 'REQUIRES_REVIEW';
      case EcfStatusGroup.accepted:
        return 'ACCEPTED';
      case EcfStatusGroup.rejected:
        return 'REJECTED';
      case EcfStatusGroup.cancelled:
        return 'CANCELLED';
      case EcfStatusGroup.unknown:
        return '';
    }
  }

  String get label {
    switch (this) {
      case EcfStatusGroup.pending:
        return 'En proceso';
      case EcfStatusGroup.requiresReview:
        return 'Requiere revisión';
      case EcfStatusGroup.accepted:
        return 'Aceptado DGII';
      case EcfStatusGroup.rejected:
        return 'Rechazado';
      case EcfStatusGroup.cancelled:
        return 'Anulado';
      case EcfStatusGroup.unknown:
        return 'Desconocido';
    }
  }

  IconData get icon {
    switch (this) {
      case EcfStatusGroup.pending:
        return Icons.hourglass_top_rounded;
      case EcfStatusGroup.requiresReview:
        return Icons.report_problem_outlined;
      case EcfStatusGroup.accepted:
        return Icons.verified_outlined;
      case EcfStatusGroup.rejected:
        return Icons.cancel_outlined;
      case EcfStatusGroup.cancelled:
        return Icons.block_outlined;
      case EcfStatusGroup.unknown:
        return Icons.help_outline_rounded;
    }
  }

  Color color(ColorScheme scheme) {
    switch (this) {
      case EcfStatusGroup.pending:
        return scheme.primary;
      case EcfStatusGroup.requiresReview:
        return scheme.tertiary;
      case EcfStatusGroup.accepted:
        return const Color(0xFF2E7D32);
      case EcfStatusGroup.rejected:
        return scheme.error;
      case EcfStatusGroup.cancelled:
        return scheme.outline;
      case EcfStatusGroup.unknown:
        return scheme.outline;
    }
  }
}

String _string(Map<String, dynamic> json, String key) =>
    (json[key] as String?)?.trim() ?? '';

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = (json[key] as String?)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// Comprobante e-CF tal como lo expone el backend (proyección de solo lectura).
class EcfDocumentSummary {
  const EcfDocumentSummary({
    required this.id,
    required this.documentType,
    required this.status,
    required this.statusGroup,
    required this.encf,
    required this.createdAt,
    this.internalDocumentNumber,
    this.sourceType,
    this.sourceId,
    this.originalDocumentId,
    this.safeErrorCode,
    this.safeErrorMessage,
    this.total,
    this.currency,
    this.originalEncf,
    this.receiverName,
    this.receiverTaxId,
  });

  final String id;
  final String documentType;
  final String status;
  final EcfStatusGroup statusGroup;

  /// e-NCF asignado por el servidor. Es `null` mientras no se haya asignado.
  final String? encf;
  final String? internalDocumentNumber;
  final String? sourceType;
  final String? sourceId;
  final String? originalDocumentId;
  final String? safeErrorCode;
  final String? safeErrorMessage;
  final DateTime? createdAt;

  /// Importe del comprobante tal como se preparó, y su moneda.
  final String? total;
  final String? currency;

  /// e-NCF del comprobante original cuando este documento es una nota E34.
  final String? originalEncf;

  /// Receptor congelado al preparar el comprobante.
  ///
  /// Es `null` cuando el comprobante no exigía receptor o cuando se preparó
  /// antes de persistir este dato. En ese caso la bandeja NO lo reconstruye
  /// desde el cliente actual: mostraría algo distinto de lo preparado.
  final String? receiverName;
  final String? receiverTaxId;

  factory EcfDocumentSummary.fromJson(Map<String, dynamic> json) {
    return EcfDocumentSummary(
      id: _string(json, 'id'),
      documentType: _string(json, 'documentType'),
      status: _string(json, 'status'),
      statusGroup: EcfStatusGroup.fromApi(json['statusGroup'] as String?),
      encf: _nullableString(json, 'encf') ??
          _nullableString(json, 'externalDocumentNumber'),
      internalDocumentNumber: _nullableString(json, 'internalDocumentNumber'),
      sourceType: _nullableString(json, 'sourceType'),
      sourceId: _nullableString(json, 'sourceId'),
      originalDocumentId: _nullableString(json, 'originalDocumentId'),
      safeErrorCode: _nullableString(json, 'safeErrorCode'),
      safeErrorMessage: _nullableString(json, 'safeErrorMessage'),
      createdAt: _date(json, 'createdAt'),
      total: _nullableString(json, 'total'),
      currency: _nullableString(json, 'currency'),
      originalEncf: _nullableString(json, 'originalEncf'),
      receiverName: _nullableString(json, 'receiverName'),
      receiverTaxId: _nullableString(json, 'receiverTaxId'),
    );
  }
}

/// Una página de la bandeja tal como la devuelve el backend.
class EcfDocumentPage {
  const EcfDocumentPage({
    required this.items,
    required this.total,
    required this.take,
    required this.skip,
  });

  final List<EcfDocumentSummary> items;

  /// Total de comprobantes que cumplen el filtro. Lo calcula el servidor.
  final int total;
  final int take;
  final int skip;

  /// Quedan filas por traer según el total del servidor.
  bool get hasMore => skip + items.length < total;

  /// Página siguiente a la ya cargada.
  int get nextSkip => skip + items.length;
}

class EcfStatusLogEntry {
  const EcfStatusLogEntry({
    required this.id,
    required this.statusAfter,
    required this.createdAt,
    this.statusBefore,
    this.reasonCode,
  });

  final String id;
  final String? statusBefore;
  final String statusAfter;
  final String? reasonCode;
  final DateTime? createdAt;

  factory EcfStatusLogEntry.fromJson(Map<String, dynamic> json) {
    return EcfStatusLogEntry(
      id: _string(json, 'id'),
      statusBefore: _nullableString(json, 'statusBefore'),
      statusAfter: _string(json, 'statusAfter'),
      reasonCode: _nullableString(json, 'reasonCode'),
      createdAt: _date(json, 'createdAt'),
    );
  }
}

class EcfAttemptEntry {
  const EcfAttemptEntry({
    required this.id,
    required this.operation,
    required this.createdAt,
    this.statusBefore,
    this.statusAfter,
  });

  final String id;
  final String operation;
  final String? statusBefore;
  final String? statusAfter;
  final DateTime? createdAt;

  factory EcfAttemptEntry.fromJson(Map<String, dynamic> json) {
    return EcfAttemptEntry(
      id: _string(json, 'id'),
      operation: _string(json, 'operation'),
      statusBefore: _nullableString(json, 'statusBefore'),
      statusAfter: _nullableString(json, 'statusAfter'),
      createdAt: _date(json, 'createdAt'),
    );
  }
}

class EcfCreditReservationInfo {
  const EcfCreditReservationInfo({
    required this.state,
    required this.amount,
    this.createdAt,
    this.updatedAt,
  });

  final String state;
  final String amount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EcfCreditReservationInfo.fromJson(Map<String, dynamic> json) {
    return EcfCreditReservationInfo(
      state: _string(json, 'state'),
      amount: _string(json, 'amount'),
      createdAt: _date(json, 'createdAt'),
      updatedAt: _date(json, 'updatedAt'),
    );
  }
}

class EcfOriginalReference {
  const EcfOriginalReference({
    required this.id,
    required this.documentType,
    required this.status,
    this.encf,
  });

  final String id;
  final String documentType;
  final String status;
  final String? encf;

  factory EcfOriginalReference.fromJson(Map<String, dynamic> json) {
    return EcfOriginalReference(
      id: _string(json, 'id'),
      documentType: _string(json, 'documentType'),
      status: _string(json, 'status'),
      encf: _nullableString(json, 'externalDocumentNumber'),
    );
  }
}

/// Detalle completo: estado, e-NCF, historial de transiciones e intentos.
class EcfDocumentDetail {
  const EcfDocumentDetail({
    required this.summary,
    required this.statusLogs,
    required this.attempts,
    required this.evidenceReceipts,
    this.creditReservation,
    this.originalDocument,
    this.externalProviderId,
    this.sourceType,
    this.sourceId,
  });

  final EcfDocumentSummary summary;
  final List<EcfStatusLogEntry> statusLogs;
  final List<EcfAttemptEntry> attempts;
  final int evidenceReceipts;
  final EcfCreditReservationInfo? creditReservation;
  final EcfOriginalReference? originalDocument;
  final String? externalProviderId;
  final String? sourceType;
  final String? sourceId;

  factory EcfDocumentDetail.fromJson(Map<String, dynamic> json) {
    final logs = (json['statusLogs'] as List?) ?? const [];
    final attempts = (json['attempts'] as List?) ?? const [];
    final reservation = json['creditReservation'];
    final original = json['originalDocument'];
    return EcfDocumentDetail(
      summary: EcfDocumentSummary.fromJson(json),
      statusLogs: logs
          .whereType<Map>()
          .map((row) => EcfStatusLogEntry.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      attempts: attempts
          .whereType<Map>()
          .map((row) => EcfAttemptEntry.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      evidenceReceipts: (json['evidenceReceipts'] as num?)?.toInt() ?? 0,
      creditReservation: reservation is Map
          ? EcfCreditReservationInfo.fromJson(reservation.cast<String, dynamic>())
          : null,
      originalDocument: original is Map
          ? EcfOriginalReference.fromJson(original.cast<String, dynamic>())
          : null,
      externalProviderId: _nullableString(json, 'externalProviderId'),
      sourceType: _nullableString(json, 'sourceType'),
      sourceId: _nullableString(json, 'sourceId'),
    );
  }
}

class EcfDocumentTypeCapability {
  const EcfDocumentTypeCapability({
    required this.documentType,
    required this.contractStatus,
    required this.contractAllowsEmission,
    required this.allowedForCompany,
    required this.allocatable,
  });

  final String documentType;
  final String contractStatus;
  final bool contractAllowsEmission;
  final bool allowedForCompany;

  /// E32 usa su propio slot de un solo uso y nunca se asigna desde el rango.
  final bool allocatable;

  factory EcfDocumentTypeCapability.fromJson(Map<String, dynamic> json) {
    return EcfDocumentTypeCapability(
      documentType: _string(json, 'documentType'),
      contractStatus: _string(json, 'contractStatus'),
      contractAllowsEmission: json['contractAllowsEmission'] == true,
      allowedForCompany: json['allowedForCompany'] == true,
      allocatable: json['allocatable'] == true,
    );
  }
}

class EcfCapabilities {
  const EcfCapabilities({
    required this.enabled,
    required this.environment,
    required this.certificationStatus,
    required this.productionEnabled,
    required this.allowedTypes,
    required this.emissionPathAvailable,
    required this.documentTypes,
  });

  final bool enabled;
  final String environment;
  final String certificationStatus;
  final bool productionEnabled;
  final List<String> allowedTypes;

  /// `false` mientras no exista un endpoint autorizado de emisión. La interfaz
  /// usa esto para no ofrecer nunca un botón de envío real.
  final bool emissionPathAvailable;
  final List<EcfDocumentTypeCapability> documentTypes;

  factory EcfCapabilities.fromJson(Map<String, dynamic> json) {
    final types = (json['documentTypes'] as List?) ?? const [];
    final allowed = (json['allowedTypes'] as List?) ?? const [];
    return EcfCapabilities(
      enabled: json['enabled'] == true,
      environment: _string(json, 'environment').isEmpty
          ? 'SANDBOX'
          : _string(json, 'environment'),
      certificationStatus: _string(json, 'certificationStatus').isEmpty
          ? 'NOT_STARTED'
          : _string(json, 'certificationStatus'),
      productionEnabled: json['productionEnabled'] == true,
      allowedTypes: allowed.whereType<String>().toList(growable: false),
      emissionPathAvailable: json['emissionPathAvailable'] == true,
      documentTypes: types
          .whereType<Map>()
          .map((row) =>
              EcfDocumentTypeCapability.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// Resultado del DESPACHO SIMULADO contra el proveedor simulado.
///
/// `officialFiscalAcceptance` es `false` por contrato: un 2xx del simulador
/// nunca concede aceptación de la DGII. La interfaz debe mostrar esto como una
/// validación, no como un comprobante aceptado.
class EcfSimulatedDispatchOutcome {
  const EcfSimulatedDispatchOutcome({
    required this.simulated,
    required this.officialFiscalAcceptance,
    required this.scenario,
    required this.correlated,
    required this.documentType,
    required this.providerOutcome,
    required this.safeCode,
  });

  final bool simulated;
  final bool officialFiscalAcceptance;
  final String scenario;
  final bool correlated;
  final String documentType;
  final String providerOutcome;
  final String? safeCode;

  /// ¿Se puede reintentar el envío? Siempre `false`: un reintento ciego de un
  /// documento ya enviado está prohibido por diseño.
  static const bool canRetryPost = false;

  factory EcfSimulatedDispatchOutcome.fromJson(Map<String, dynamic> json) {
    final observation = json['observation'];
    final map = observation is Map
        ? observation.cast<String, dynamic>()
        : const <String, dynamic>{};
    return EcfSimulatedDispatchOutcome(
      simulated: json['simulated'] == true,
      officialFiscalAcceptance: json['officialFiscalAcceptance'] == true,
      scenario: (json['scenario'] ?? '').toString(),
      correlated: json['correlated'] == true,
      documentType: (json['documentType'] ?? '').toString(),
      providerOutcome: (map['providerOutcome'] ?? 'UNKNOWN').toString(),
      safeCode: map['safeCode']?.toString(),
    );
  }
}

/// Paso del proceso INTERNO de habilitación e-CF.
///
/// `status` es un estado interno del proceso administrativo. **No** es un estado
/// oficial de la DGII y no debe presentarse como tal.
class EcfOnboardingStepView {
  const EcfOnboardingStepView({
    required this.stepKey,
    required this.status,
    this.mode,
    this.blockedReason,
    this.resultSummary,
  });

  final String stepKey;
  final String status;
  final String? mode;
  final String? blockedReason;
  final String? resultSummary;

  bool get isDone =>
      status == 'COMPLETED' || status == 'CONFIRMED' || status == 'SKIPPED';

  bool get isBlocked => status == 'BLOCKED';

  /// Solo se puede completar lo que está pendiente o en curso: un paso bloqueado
  /// no se "arregla" marcándolo.
  bool get canComplete => !isDone && !isBlocked;

  String get label {
    switch (stepKey) {
      case 'FISCAL_DATA':
        return 'Datos fiscales';
      case 'REQUIREMENTS':
        return 'Requisitos previos';
      case 'PROVIDER_CREDENTIALS':
        return 'Credenciales del proveedor';
      case 'TEST_SET':
        return 'Set de pruebas';
      case 'CERTIFICATION':
        return 'Certificación';
      case 'PRODUCTION_ENABLEMENT':
        return 'Habilitación productiva';
      default:
        return stepKey;
    }
  }

  factory EcfOnboardingStepView.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    return EcfOnboardingStepView(
      stepKey: (json['stepKey'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      mode: text(json['mode']),
      blockedReason: text(json['blockedReason']),
      resultSummary: text(json['resultSummary']),
    );
  }
}

/// Estado del proceso de habilitación de la empresa.
class EcfOnboardingView {
  const EcfOnboardingView({
    required this.steps,
    required this.certificationStatus,
    required this.productionEnabled,
  });

  final List<EcfOnboardingStepView> steps;
  final String certificationStatus;
  final bool productionEnabled;

  double get progress {
    if (steps.isEmpty) return 0;
    return steps.where((step) => step.isDone).length / steps.length;
  }

  /// El backend devuelve `{ config, steps, latestAudits }`. Se lee de forma
  /// tolerante: si una clave falta, se usa un valor seguro.
  factory EcfOnboardingView.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final config = json['config'];
    final configMap = config is Map
        ? config.cast<String, dynamic>()
        : const <String, dynamic>{};
    return EcfOnboardingView(
      steps: rawSteps is List
          ? rawSteps
                .whereType<Map>()
                .map((row) =>
                    EcfOnboardingStepView.fromJson(row.cast<String, dynamic>()))
                .toList(growable: false)
          : const <EcfOnboardingStepView>[],
      certificationStatus:
          (configMap['certificationStatus'] ?? 'NOT_STARTED').toString(),
      productionEnabled: configMap['productionEnabled'] == true,
    );
  }
}

/// Requisito del proceso de habilitación DGII, cruzado con su estado real.
class EcfDgiiRequirementProgress {
  const EcfDgiiRequirementProgress({
    required this.key,
    required this.label,
    required this.mandatory,
    required this.automatable,
    required this.status,
    required this.resolved,
    this.tracking,
  });

  final String key;
  final String label;
  final bool mandatory;

  /// `false` marca un trámite externo que el producto no puede automatizar.
  final bool automatable;
  final String status;
  final bool resolved;

  /// Seguimiento INTERNO del requisito: quién lo lleva y para cuándo.
  ///
  /// Es gestión, no progreso: no modifica `status` ni `resolved`, que siguen
  /// derivándose del backend. `null` significa que nadie lo ha registrado.
  final EcfDgiiRequirementTracking? tracking;

  factory EcfDgiiRequirementProgress.fromJson(Map<String, dynamic> json) {
    return EcfDgiiRequirementProgress(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? json['key'] ?? '').toString(),
      mandatory: json['mandatory'] == true,
      automatable: json['automatable'] == true,
      status: (json['status'] ?? 'PENDING').toString(),
      resolved: json['resolved'] == true,
      tracking: EcfDgiiRequirementTracking.fromJsonOrNull(json['tracking']),
    );
  }
}

/// Seguimiento interno de un requisito (estado de gestión, responsable, fecha).
///
/// No es una verificación oficial de nada: es la libreta de trabajo de la
/// empresa para saber por dónde va cada trámite.
class EcfDgiiRequirementTracking {
  const EcfDgiiRequirementTracking({
    required this.status,
    this.note,
    this.responsibleUserId,
    this.dueDate,
    this.updatedAt,
  });

  final String status;
  final String? note;
  final String? responsibleUserId;
  final String? dueDate;
  final DateTime? updatedAt;

  /// Los mismos valores que acepta el backend; no se inventan estados locales.
  static const statuses = <String>[
    'PENDING',
    'IN_PROGRESS',
    'BLOCKED',
    'COMPLETED',
    'NOT_APPLICABLE',
  ];

  static String labelForStatus(String status) {
    switch (status) {
      case 'IN_PROGRESS':
        return 'En curso';
      case 'BLOCKED':
        return 'Bloqueado';
      case 'COMPLETED':
        return 'Completado';
      case 'NOT_APPLICABLE':
        return 'No aplica';
      default:
        return 'Pendiente';
    }
  }

  String get statusLabel => labelForStatus(status);

  static EcfDgiiRequirementTracking? fromJsonOrNull(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    String? text(Object? raw) {
      final parsed = raw?.toString().trim();
      return parsed == null || parsed.isEmpty ? null : parsed;
    }

    final status = text(json['status']);
    if (status == null) return null;
    return EcfDgiiRequirementTracking(
      status: status,
      note: text(json['note']),
      responsibleUserId: text(json['responsibleUserId']),
      dueDate: text(json['dueDate']),
      updatedAt: DateTime.tryParse(text(json['updatedAt']) ?? ''),
    );
  }
}

/// Progreso de la habilitación. El porcentaje lo calcula el backend: la
/// aplicación no lo recalcula ni lo estima.
class EcfDgiiProgress {
  const EcfDgiiProgress({
    required this.requirements,
    required this.total,
    required this.resolvedCount,
    required this.mandatoryTotal,
    required this.mandatoryResolved,
    required this.percent,
    required this.pendingMandatory,
  });

  final List<EcfDgiiRequirementProgress> requirements;
  final int total;
  final int resolvedCount;
  final int mandatoryTotal;
  final int mandatoryResolved;
  final int percent;
  final List<String> pendingMandatory;

  double get ratio => total == 0 ? 0 : resolvedCount / total;

  static const empty = EcfDgiiProgress(
    requirements: <EcfDgiiRequirementProgress>[],
    total: 0,
    resolvedCount: 0,
    mandatoryTotal: 0,
    mandatoryResolved: 0,
    percent: 0,
    pendingMandatory: <String>[],
  );

  factory EcfDgiiProgress.fromJson(Map<String, dynamic> json) {
    final list = (json['requirements'] as List?) ?? const [];
    final pending = (json['pendingMandatory'] as List?) ?? const [];
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    return EcfDgiiProgress(
      requirements: list
          .whereType<Map>()
          .map((row) => EcfDgiiRequirementProgress.fromJson(
                row.cast<String, dynamic>(),
              ))
          .toList(growable: false),
      total: asInt(json['total']),
      resolvedCount: asInt(json['resolvedCount']),
      mandatoryTotal: asInt(json['mandatoryTotal']),
      mandatoryResolved: asInt(json['mandatoryResolved']),
      percent: asInt(json['percent']),
      pendingMandatory: pending.whereType<String>().toList(growable: false),
    );
  }
}

/// Motivo por el que una capacidad está bloqueada. El texto lo redacta el
/// backend; la interfaz solo lo muestra.
class EcfDgiiBlocker {
  const EcfDgiiBlocker({required this.code, required this.message});

  final String code;
  final String message;

  factory EcfDgiiBlocker.fromJson(Map<String, dynamic> json) {
    return EcfDgiiBlocker(
      code: (json['code'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

/// Evidencia registrada. `isOfficialDocument` distingue un documento oficial
/// de una declaración manual: la interfaz nunca los presenta igual.
///
/// La REVISIÓN es una dimensión separada del ORIGEN: revisar una declaración
/// manual no la convierte en documento oficial, y por eso el modelo no mezcla
/// ambas cosas en un solo campo.
class EcfDgiiEvidenceView {
  const EcfDgiiEvidenceView({
    required this.id,
    required this.source,
    required this.isOfficialDocument,
    required this.kind,
    this.fileName,
    this.description,
    this.createdAt,
    this.reviewStatus = 'PENDING',
    String? level,
    this.supportsOfficialAuthorization = false,
    this.reviewedAt,
    this.reviewNote,
  }) : _level = level;

  final String id;
  final String source;
  final bool isOfficialDocument;
  final String kind;
  final String? fileName;
  final String? description;
  final DateTime? createdAt;

  /// `PENDING` | `REVIEWED` | `REJECTED`.
  final String reviewStatus;

  final String? _level;

  /// Nivel combinado (origen + revisión).
  ///
  /// Si el backend no lo envía, se DERIVA con la misma regla en vez de asumir
  /// un valor optimista: una versión antigua del servidor no puede hacer que un
  /// documento oficial sin revisar se presente como revisado.
  String get level => _level ?? _deriveLevel(source, reviewStatus);

  static String _deriveLevel(String source, String reviewStatus) {
    switch (source) {
      case 'OFFICIAL_DOCUMENT':
        return reviewStatus == 'REVIEWED'
            ? 'OFFICIAL_DOCUMENT_REVIEWED'
            : 'OFFICIAL_DOCUMENT_PENDING_REVIEW';
      case 'PROVIDER_ARTIFACT':
        return 'PROVIDER_ISSUED';
      default:
        return reviewStatus == 'REVIEWED'
            ? 'INTERNALLY_REVIEWED'
            : 'DECLARED_BY_COMPANY';
    }
  }

  /// Solo un documento OFICIAL ya revisado puede sustentar una autorización.
  final bool supportsOfficialAuthorization;

  final DateTime? reviewedAt;
  final String? reviewNote;

  bool get isReviewed => reviewStatus == 'REVIEWED';
  bool get isRejected => reviewStatus == 'REJECTED';
  bool get isPendingReview => reviewStatus == 'PENDING';

  /// El backend lo afirma explícitamente y siempre es `false`: ninguna evidencia
  /// autoriza nada por sí sola. Se expone para poder decirlo en la interfaz.
  bool get grantsOfficialAuthorization => false;

  String get sourceLabel {
    switch (source) {
      case 'OFFICIAL_DOCUMENT':
        return 'Documento oficial';
      case 'PROVIDER_ARTIFACT':
        return 'Artefacto del proveedor';
      case 'MANUAL_DECLARATION':
        return 'Declaración manual';
      default:
        return source;
    }
  }

  String get reviewStatusLabel {
    switch (reviewStatus) {
      case 'REVIEWED':
        return 'Revisada';
      case 'REJECTED':
        return 'Rechazada';
      default:
        return 'Sin revisar';
    }
  }

  String get levelLabel {
    switch (level) {
      case 'INTERNALLY_REVIEWED':
        return 'Declaración interna revisada';
      case 'PROVIDER_ISSUED':
        return 'Emitida por el proveedor';
      case 'OFFICIAL_DOCUMENT_PENDING_REVIEW':
        return 'Documento oficial sin revisar';
      case 'OFFICIAL_DOCUMENT_REVIEWED':
        return 'Documento oficial revisado';
      default:
        return 'Declaración de la empresa';
    }
  }

  factory EcfDgiiEvidenceView.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    return EcfDgiiEvidenceView(
      id: (json['id'] ?? '').toString(),
      source: (json['source'] ?? 'MANUAL_DECLARATION').toString(),
      isOfficialDocument: json['isOfficialDocument'] == true,
      kind: (json['kind'] ?? '').toString(),
      fileName: text(json['fileName']),
      description: text(json['description']),
      createdAt: DateTime.tryParse(text(json['createdAt']) ?? ''),
      reviewStatus: (json['reviewStatus'] ?? 'PENDING').toString(),
      level: json['level']?.toString(),
      supportsOfficialAuthorization: json['supportsOfficialAuthorization'] == true,
      reviewedAt: DateTime.tryParse(text(json['reviewedAt']) ?? ''),
      reviewNote: text(json['reviewNote']),
    );
  }
}

/// Entrada del historial de habilitación.
class EcfDgiiHistoryEntry {
  const EcfDgiiHistoryEntry({
    required this.id,
    required this.action,
    this.actorUserId,
    this.createdAt,
  });

  final String id;
  final String action;
  final String? actorUserId;
  final DateTime? createdAt;

  String get actionLabel {
    switch (action) {
      case 'DGII_HABILITATION_UPDATED':
        return 'Progreso actualizado';
      case 'DGII_EVIDENCE_REGISTERED':
        return 'Evidencia registrada';
      case 'DGII_AUTHORIZATION_RECORDED':
        return 'Autorización registrada';
      case 'DGII_AUTHORIZATION_REVOKED':
        return 'Autorización revocada';
      default:
        return action;
    }
  }

  factory EcfDgiiHistoryEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['actorUserId']?.toString().trim();
    final created = json['createdAt']?.toString().trim();
    return EcfDgiiHistoryEntry(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      actorUserId: raw == null || raw.isEmpty ? null : raw,
      createdAt: DateTime.tryParse(created ?? ''),
    );
  }
}

/// Estado de emisión según la compuerta del backend.
///
/// `realEmissionAuthorized` es **siempre** `false` mientras la emisión real no
/// esté implementada; la interfaz no lo estima por su cuenta.
class EcfDgiiEmissionState {
  const EcfDgiiEmissionState({
    required this.realEmissionAuthorized,
    required this.simulatedDispatchAuthorized,
    required this.productionEmissionImplemented,
  });

  final bool realEmissionAuthorized;
  final bool simulatedDispatchAuthorized;
  final bool productionEmissionImplemented;

  factory EcfDgiiEmissionState.fromJson(Map<String, dynamic> json) {
    return EcfDgiiEmissionState(
      realEmissionAuthorized: json['realEmissionAuthorized'] == true,
      simulatedDispatchAuthorized: json['simulatedDispatchAuthorized'] == true,
      productionEmissionImplemented: json['productionEmissionImplemented'] == true,
    );
  }
}

/// Habilitación DGII de la empresa.
///
/// Es un registro de SEGUIMIENTO INTERNO (`isInternalTrackingOnly`). La pantalla
/// debe presentar por separado el avance interno y la autorización oficial: el
/// primero lo gestiona la empresa, la segunda solo existe si hay un registro
/// oficial verificado con evidencia.
class EcfDgiiHabilitationView {
  const EcfDgiiHabilitationView({
    required this.companyId,
    required this.state,
    this.reviewState,
    this.observations,
    this.externalId,
    this.startedAt,
    this.updatedAt,
    required this.officialAuthorization,
    required this.officialAuthorizationBlockers,
    required this.authorizationSource,
    this.authorizedAt,
    required this.moduleEnabled,
    required this.certificationStatus,
    required this.providerIntegrationConfigured,
    required this.progress,
    required this.evidence,
    required this.emission,
    required this.blockers,
  });

  final String companyId;
  final String state;
  final String? reviewState;
  final String? observations;
  final String? externalId;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final bool officialAuthorization;
  final List<EcfDgiiBlocker> officialAuthorizationBlockers;
  final String authorizationSource;
  final DateTime? authorizedAt;
  final bool moduleEnabled;
  final String certificationStatus;
  final bool providerIntegrationConfigured;
  final EcfDgiiProgress progress;
  final List<EcfDgiiEvidenceView> evidence;
  final EcfDgiiEmissionState emission;
  final List<EcfDgiiBlocker> blockers;

  /// Etiqueta legible del estado de seguimiento interno.
  String get stateLabel {
    switch (state) {
      case 'NOT_STARTED':
        return 'Sin iniciar';
      case 'PREPARING_REQUIREMENTS':
        return 'Preparando requisitos';
      case 'APPLICATION_PENDING':
        return 'Solicitud pendiente';
      case 'IN_PROGRESS':
        return 'En proceso';
      case 'TESTS_PENDING':
        return 'Pruebas pendientes';
      case 'IN_CERTIFICATION':
        return 'En certificación';
      case 'APPROVED':
        return 'Aprobado (registro interno)';
      case 'REJECTED':
        return 'Rechazado';
      case 'REQUIRES_CORRECTION':
        return 'Requiere corrección';
      default:
        return state;
    }
  }

  /// Estados a los que el usuario puede avanzar desde el actual. `APPROVED`
  /// **nunca** aparece aquí: no se aprueba desde la interfaz.
  List<String> get allowedNextStates {
    switch (state) {
      case 'NOT_STARTED':
        return const ['PREPARING_REQUIREMENTS', 'APPLICATION_PENDING'];
      case 'PREPARING_REQUIREMENTS':
        return const ['APPLICATION_PENDING', 'REQUIRES_CORRECTION'];
      case 'APPLICATION_PENDING':
        return const ['IN_PROGRESS', 'REQUIRES_CORRECTION'];
      case 'IN_PROGRESS':
        return const ['TESTS_PENDING', 'IN_CERTIFICATION', 'REQUIRES_CORRECTION'];
      case 'TESTS_PENDING':
        return const ['IN_CERTIFICATION', 'REQUIRES_CORRECTION'];
      case 'IN_CERTIFICATION':
        return const ['REQUIRES_CORRECTION'];
      case 'APPROVED':
        return const ['REQUIRES_CORRECTION'];
      case 'REJECTED':
        return const ['PREPARING_REQUIREMENTS', 'APPLICATION_PENDING'];
      case 'REQUIRES_CORRECTION':
        return const ['PREPARING_REQUIREMENTS', 'APPLICATION_PENDING', 'IN_PROGRESS'];
      default:
        return const [];
    }
  }

  static String labelForState(String value) {
    switch (value) {
      case 'PREPARING_REQUIREMENTS':
        return 'Preparando requisitos';
      case 'APPLICATION_PENDING':
        return 'Solicitud pendiente';
      case 'IN_PROGRESS':
        return 'En proceso';
      case 'TESTS_PENDING':
        return 'Pruebas pendientes';
      case 'IN_CERTIFICATION':
        return 'En certificación';
      case 'APPROVED':
        return 'Aprobado (registro interno)';
      case 'REJECTED':
        return 'Rechazado';
      case 'REQUIRES_CORRECTION':
        return 'Requiere corrección';
      case 'NOT_STARTED':
        return 'Sin iniciar';
      default:
        return value;
    }
  }

  factory EcfDgiiHabilitationView.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    List<EcfDgiiBlocker> blockersOf(Object? value) {
      if (value is! List) return const <EcfDgiiBlocker>[];
      return value
          .whereType<Map>()
          .map((row) => EcfDgiiBlocker.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    }

    final progress = json['progress'];
    final emission = json['emission'];
    final evidence = json['evidence'];
    final authorizedAt = text(json['authorizedAt']);
    final startedAt = text(json['startedAt']);
    final updatedAt = text(json['updatedAt']);

    return EcfDgiiHabilitationView(
      companyId: (json['companyId'] ?? '').toString(),
      state: (json['state'] ?? 'NOT_STARTED').toString(),
      reviewState: text(json['reviewState']),
      observations: text(json['observations']),
      externalId: text(json['externalId']),
      startedAt: DateTime.tryParse(startedAt ?? ''),
      updatedAt: DateTime.tryParse(updatedAt ?? ''),
      officialAuthorization: json['officialAuthorization'] == true,
      officialAuthorizationBlockers: blockersOf(
        json['officialAuthorizationBlockers'],
      ),
      authorizationSource: (json['authorizationSource'] ?? 'NONE').toString(),
      authorizedAt: DateTime.tryParse(authorizedAt ?? ''),
      moduleEnabled: json['moduleEnabled'] == true,
      certificationStatus:
          (json['certificationStatus'] ?? 'NOT_STARTED').toString(),
      providerIntegrationConfigured:
          json['providerIntegrationConfigured'] == true,
      progress: progress is Map
          ? EcfDgiiProgress.fromJson(progress.cast<String, dynamic>())
          : EcfDgiiProgress.empty,
      evidence: evidence is List
          ? evidence
                .whereType<Map>()
                .map((row) => EcfDgiiEvidenceView.fromJson(
                      row.cast<String, dynamic>(),
                    ))
                .toList(growable: false)
          : const <EcfDgiiEvidenceView>[],
      emission: emission is Map
          ? EcfDgiiEmissionState.fromJson(emission.cast<String, dynamic>())
          : const EcfDgiiEmissionState(
              realEmissionAuthorized: false,
              simulatedDispatchAuthorized: false,
              productionEmissionImplemented: false,
            ),
      blockers: blockersOf(json['blockers']),
    );
  }
}

class EcfCounters {
  const EcfCounters({required this.total, required this.byGroup});

  final int total;
  final Map<EcfStatusGroup, int> byGroup;

  int count(EcfStatusGroup group) => byGroup[group] ?? 0;

  factory EcfCounters.fromJson(Map<String, dynamic> json) {
    final raw = (json['byGroup'] as Map?) ?? const {};
    final byGroup = <EcfStatusGroup, int>{};
    raw.forEach((key, value) {
      final group = EcfStatusGroup.fromApi(key?.toString());
      if (group != EcfStatusGroup.unknown && value is num) {
        byGroup[group] = value.toInt();
      }
    });
    return EcfCounters(
      total: (json['total'] as num?)?.toInt() ?? 0,
      byGroup: byGroup,
    );
  }
}

/// Factura original elegible para una nota de crédito E34.
class EcfEligibleOriginal {
  const EcfEligibleOriginal({
    required this.id,
    required this.documentType,
    required this.encf,
    required this.availableAmount,
    this.createdAt,
  });

  final String id;
  final String documentType;
  final String? encf;

  /// Saldo disponible calculado por la política fiscal compartida del backend.
  final String availableAmount;
  final DateTime? createdAt;

  factory EcfEligibleOriginal.fromJson(Map<String, dynamic> json) {
    return EcfEligibleOriginal(
      id: _string(json, 'id'),
      documentType: _string(json, 'documentType'),
      encf: _nullableString(json, 'encf') ??
          _nullableString(json, 'externalDocumentNumber'),
      availableAmount: _string(json, 'availableAmount'),
      createdAt: _date(json, 'createdAt'),
    );
  }
}

class EcfSequenceInfo {
  const EcfSequenceInfo({
    required this.id,
    required this.documentType,
    required this.prefix,
    required this.startNumber,
    required this.nextNumber,
    required this.endNumber,
    required this.active,
    required this.consumed,
    required this.remaining,
    this.validUntil,
  });

  final String id;
  final String documentType;
  final String prefix;
  final int startNumber;
  final int nextNumber;
  final int endNumber;
  final bool active;

  /// Números ya consumidos. El consumo es permanente: nunca se libera.
  final int consumed;
  final int remaining;
  final DateTime? validUntil;

  factory EcfSequenceInfo.fromJson(Map<String, dynamic> json) {
    return EcfSequenceInfo(
      id: _string(json, 'id'),
      documentType: _string(json, 'documentType'),
      prefix: _string(json, 'prefix'),
      startNumber: (json['startNumber'] as num?)?.toInt() ?? 0,
      nextNumber: (json['nextNumber'] as num?)?.toInt() ?? 0,
      endNumber: (json['endNumber'] as num?)?.toInt() ?? 0,
      active: json['active'] == true,
      consumed: (json['consumed'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      validUntil: _date(json, 'validUntil'),
    );
  }
}

/// Partida de una venta cuyo estado de clasificación fiscal hay que revisar.
///
/// La aplicación NO decide si una partida está bien clasificada: solo muestra lo
/// que el backend responde. `canConfirm` viene del servidor y ya tiene en cuenta
/// si el comprobante salió del equipo.
class EcfPendingClassificationLine {
  const EcfPendingClassificationLine({
    required this.saleItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.needsClassification,
    required this.canConfirm,
    this.fiscallyFrozen = false,
    this.frozenClassification,
    this.supervisedClassification,
    this.supervisedReason,
    this.supervisedAt,
    this.effectiveClassification,
  });

  final String saleItemId;
  final String name;
  final String quantity;
  final String unitPrice;

  /// `true` mientras no haya forma de saber si es bien o servicio.
  final bool needsClassification;

  /// El backend ya decidió si se puede confirmar (p. ej. `false` si el
  /// comprobante ya salió). La interfaz no lo recalcula.
  final bool canConfirm;

  /// Algún comprobante de la venta ya salió del equipo.
  final bool fiscallyFrozen;

  /// Lo congelado en la venta al momento de vender, si existe.
  final String? frozenClassification;
  final String? supervisedClassification;
  final String? supervisedReason;
  final DateTime? supervisedAt;
  final String? effectiveClassification;

  /// Etiqueta del estado que se muestra al usuario.
  String get statusLabel {
    final effective = effectiveClassification;
    if (effective == 'PRODUCT') return 'Bien';
    if (effective == 'SERVICE') return 'Servicio';
    return 'Sin clasificar';
  }

  factory EcfPendingClassificationLine.fromJson(Map<String, dynamic> json) {
    return EcfPendingClassificationLine(
      saleItemId: _string(json, 'saleItemId'),
      name: _string(json, 'name'),
      quantity: _string(json, 'quantity'),
      unitPrice: _string(json, 'unitPrice'),
      needsClassification: json['needsClassification'] == true,
      canConfirm: json['canConfirm'] == true,
      fiscallyFrozen: false,
      frozenClassification: _nullableString(json, 'frozenClassification'),
      supervisedClassification:
          _nullableString(json, 'supervisedClassification'),
      supervisedReason: _nullableString(json, 'supervisedReason'),
      supervisedAt: _date(json, 'supervisedAt'),
      effectiveClassification:
          _nullableString(json, 'effectiveClassification'),
    );
  }

  EcfPendingClassificationLine withFrozen(bool frozen) {
    return EcfPendingClassificationLine(
      saleItemId: saleItemId,
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      needsClassification: needsClassification,
      canConfirm: canConfirm,
      fiscallyFrozen: frozen,
      frozenClassification: frozenClassification,
      supervisedClassification: supervisedClassification,
      supervisedReason: supervisedReason,
      supervisedAt: supervisedAt,
      effectiveClassification: effectiveClassification,
    );
  }
}

/// Respuesta completa de clasificaciones pendientes de una venta.
class EcfPendingClassifications {
  const EcfPendingClassifications({
    required this.saleId,
    required this.fiscallyFrozen,
    required this.lines,
  });

  final String saleId;
  final bool fiscallyFrozen;
  final List<EcfPendingClassificationLine> lines;

  /// Partidas que siguen sin poder clasificarse.
  List<EcfPendingClassificationLine> get pending =>
      lines.where((line) => line.needsClassification).toList(growable: false);

  factory EcfPendingClassifications.fromJson(Map<String, dynamic> json) {
    final fiscallyFrozen = json['fiscallyFrozen'] == true;
    final raw = (json['lines'] as List?) ?? const [];
    return EcfPendingClassifications(
      saleId: _string(json, 'saleId'),
      fiscallyFrozen: fiscallyFrozen,
      lines: raw
          .whereType<Map>()
          .map((row) => EcfPendingClassificationLine.fromJson(
                row.cast<String, dynamic>(),
              ))
          .map((line) => line.withFrozen(fiscallyFrozen))
          .toList(growable: false),
    );
  }
}
