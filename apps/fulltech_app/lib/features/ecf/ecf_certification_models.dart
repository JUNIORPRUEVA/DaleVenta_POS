/// Resultado de incorporar el XML de postulación.
///
/// El servidor lo deja en estado `VALIDATED`: validado y asociado al expediente,
/// no presentado ni aprobado por la DGII.
class EcfPostulationXmlResult {
  const EcfPostulationXmlResult({
    required this.id,
    required this.state,
    required this.rootElement,
    required this.duplicate,
    required this.notes,
    required this.sha256Prefix,
  });

  final String id;
  final String state;
  final String rootElement;
  final bool duplicate;
  final List<String> notes;
  final String sha256Prefix;

  factory EcfPostulationXmlResult.fromJson(Map<String, dynamic> json) {
    final notes = json['notes'];
    final sha = (json['sha256'] as String?) ?? '';
    return EcfPostulationXmlResult(
      id: (json['id'] as String?) ?? '',
      state: (json['state'] as String?) ?? 'VALIDATED',
      rootElement: (json['rootElement'] as String?) ?? '',
      duplicate: json['duplicate'] == true,
      notes: notes is List
          ? notes.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      sha256Prefix: sha.length >= 12 ? sha.substring(0, 12) : sha,
    );
  }
}

/// Intento de certificación bloqueado, tal como lo ve un administrador.
///
/// Solo metadatos: no incluye certificados, contraseñas ni documentos.
class EcfBlockedAttempt {
  const EcfBlockedAttempt({
    required this.attemptId,
    required this.operation,
    required this.stepKey,
    required this.createdAt,
    required this.reference,
    required this.errorCode,
    required this.reason,
    required this.safeAction,
  });

  final String attemptId;
  final String operation;
  final String stepKey;
  final String createdAt;
  final String? reference;
  final String? errorCode;
  final String reason;
  final String safeAction;

  factory EcfBlockedAttempt.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    return EcfBlockedAttempt(
      attemptId: (json['attemptId'] as String?) ?? '',
      operation: (json['operation'] as String?) ?? '',
      stepKey: (json['stepKey'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
      reference: text(json['externalId']),
      errorCode: text(json['errorCode']),
      reason: (json['reason'] as String?) ?? '',
      safeAction: (json['safeAction'] as String?) ?? '',
    );
  }
}

/// Metadatos de preparación del módulo e-CF (vídeo y modo de prueba).
class EcfPreparationMetadata {
  const EcfPreparationMetadata({
    required this.videoUrl,
    required this.simulationAvailable,
    required this.simulationBadge,
    required this.simulationReason,
  });

  final String? videoUrl;
  final bool simulationAvailable;
  final String simulationBadge;

  /// Motivo por el que el modo de prueba no está disponible, o `null`.
  final String? simulationReason;

  factory EcfPreparationMetadata.fromJson(Map<String, dynamic> json) {
    final simulation = json['simulation'];
    final map = simulation is Map
        ? simulation.cast<String, dynamic>()
        : const <String, dynamic>{};
    final videoUrl = (json['videoUrl'] as String?)?.trim();
    final reason = (map['reason'] as String?)?.trim();
    return EcfPreparationMetadata(
      videoUrl: videoUrl == null || videoUrl.isEmpty ? null : videoUrl,
      simulationAvailable: map['available'] == true,
      simulationBadge:
          (map['badge'] as String?)?.trim() ??
          'MODO DE PRUEBA — NO SE ENVIARÁ NADA A DGII',
      simulationReason: reason == null || reason.isEmpty ? null : reason,
    );
  }
}

/// Un paso del motor de activación visto por el cliente.
class EcfActivationStepView {
  const EcfActivationStepView({
    required this.key,
    required this.label,
    required this.className,
    required this.status,
    required this.resolved,
    this.awaiting,
  });

  final String key;
  final String label;
  final String className;
  final String status;
  final bool resolved;
  final String? awaiting;

  /// `true` si es el cliente quien debe actuar para desbloquearlo.
  bool get isClientAction => className == 'CLIENT_ACTION';

  /// `true` si depende de una decisión externa (DGII).
  bool get isAuthorityWait => className == 'AUTHORITY_WAIT';

  factory EcfActivationStepView.fromJson(Map<String, dynamic> json) {
    final awaiting = (json['awaiting'] as String?)?.trim();
    return EcfActivationStepView(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? (json['key'] as String?) ?? '',
      className: (json['className'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'PENDING',
      resolved: json['resolved'] == true,
      awaiting: awaiting == null || awaiting.isEmpty ? null : awaiting,
    );
  }
}

/// Progreso del motor de activación (recuperable al reabrir la aplicación).
class EcfActivationProgress {
  const EcfActivationProgress({
    required this.stage,
    required this.percent,
    required this.resolvedCount,
    required this.total,
    required this.steps,
    required this.transportSimulated,
  });

  final String stage;
  final int percent;
  final int resolvedCount;
  final int total;
  final List<EcfActivationStepView> steps;

  /// El motor declara explícitamente si su transporte es simulado.
  final bool transportSimulated;

  List<EcfActivationStepView> get pending =>
      steps.where((step) => !step.resolved).toList(growable: false);

  List<EcfActivationStepView> get clientActions =>
      pending.where((step) => step.isClientAction).toList(growable: false);

  bool get started =>
      resolvedCount > 0 || steps.any((step) => step.status != 'PENDING');

  factory EcfActivationProgress.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final map = summary is Map
        ? summary.cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawSteps = json['steps'];
    final steps = rawSteps is List
        ? rawSteps
              .whereType<Map>()
              .map(
                (row) =>
                    EcfActivationStepView.fromJson(row.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <EcfActivationStepView>[];
    final percent = map['percent'];
    final resolved = map['resolvedCount'];
    final total = map['total'];
    return EcfActivationProgress(
      stage: (map['stage'] as String?) ?? 'NOT_STARTED',
      percent: percent is num ? percent.toInt() : 0,
      resolvedCount: resolved is num
          ? resolved.toInt()
          : steps.where((s) => s.resolved).length,
      total: total is num ? total.toInt() : steps.length,
      steps: steps,
      transportSimulated: (json['transport'] as String?) == 'SIMULATED',
    );
  }
}
