class PendingSyncAction {
  final String id;
  final String type;
  final String scope;
  final String? companyId;
  final String? userId;
  final String? terminalId;
  final String? entityType;
  final String? entityId;
  final String? idempotencyKey;
  final Map<String, dynamic> payload;
  final String status;
  final int attempts;
  final String? error;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
  final bool permanent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PendingSyncAction({
    required this.id,
    required this.type,
    required this.scope,
    this.companyId,
    this.userId,
    this.terminalId,
    this.entityType,
    this.entityId,
    this.idempotencyKey,
    required this.payload,
    required this.status,
    required this.attempts,
    this.error,
    this.nextAttemptAt,
    this.lastAttemptAt,
    this.permanent = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PendingSyncAction.fromMap(Map<String, dynamic> map) {
    final payload = ((map['payload'] as Map?) ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    final scope = (map['scope'] ?? '').toString();
    String? cleanString(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return PendingSyncAction(
      id: (map['id'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      scope: scope,
      companyId:
          cleanString(map['companyId'] ?? map['company_id']) ??
          _companyFromScope(scope),
      userId: cleanString(map['userId'] ?? map['user_id'] ?? payload['userId']),
      terminalId: cleanString(map['terminalId'] ?? map['terminal_id']),
      entityType: cleanString(map['entityType'] ?? map['entity_type']),
      entityId: cleanString(
        map['entityId'] ?? map['entity_id'] ?? payload['id'],
      ),
      idempotencyKey: cleanString(
        map['idempotencyKey'] ??
            map['idempotency_key'] ??
            payload['operationId'] ??
            payload['clientRequestId'],
      ),
      payload: payload,
      status: (map['status'] ?? 'pending').toString(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      error: map['error']?.toString(),
      nextAttemptAt: _parseDate(map['nextAttemptAt'] ?? map['next_attempt_at']),
      lastAttemptAt: _parseDate(map['lastAttemptAt'] ?? map['last_attempt_at']),
      permanent:
          map['permanent'] == true ||
          map['permanent'] == 1 ||
          map['status'] == 'failed' ||
          map['status'] == 'conflict' ||
          map['status'] == 'requires_action',
      createdAt:
          DateTime.tryParse('${map['createdAt']}') ?? DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse('${map['updatedAt']}') ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'scope': scope,
      'companyId': companyId,
      'userId': userId,
      'terminalId': terminalId,
      'entityType': entityType,
      'entityId': entityId,
      'idempotencyKey': idempotencyKey,
      'payload': payload,
      'status': status,
      'attempts': attempts,
      'error': error,
      'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
      'lastAttemptAt': lastAttemptAt?.toUtc().toIso8601String(),
      'permanent': permanent,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  PendingSyncAction copyWith({
    String? companyId,
    String? userId,
    String? terminalId,
    String? entityType,
    String? entityId,
    String? idempotencyKey,
    String? status,
    int? attempts,
    String? error,
    bool clearError = false,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    DateTime? lastAttemptAt,
    bool? permanent,
    DateTime? updatedAt,
  }) {
    return PendingSyncAction(
      id: id,
      type: type,
      scope: scope,
      companyId: companyId ?? this.companyId,
      userId: userId ?? this.userId,
      terminalId: terminalId ?? this.terminalId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      payload: payload,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      error: clearError ? null : (error ?? this.error),
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      permanent: permanent ?? this.permanent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      if (value <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toUtc();
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static String? _companyFromScope(String scope) {
    final text = scope.trim();
    if (text.startsWith('catalog.')) {
      final company = text.substring('catalog.'.length).trim();
      return company.isEmpty || company == 'default' ? null : company;
    }
    return null;
  }
}
