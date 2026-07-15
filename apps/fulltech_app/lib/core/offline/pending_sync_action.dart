class PendingSyncAction {
  final String id;
  final String type;
  final String scope;
  final Map<String, dynamic> payload;
  final String status;
  final int attempts;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PendingSyncAction({
    required this.id,
    required this.type,
    required this.scope,
    required this.payload,
    required this.status,
    required this.attempts,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PendingSyncAction.fromMap(Map<String, dynamic> map) {
    return PendingSyncAction(
      id: (map['id'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      scope: (map['scope'] ?? '').toString(),
      payload: ((map['payload'] as Map?) ?? const <String, dynamic>{})
          .cast<String, dynamic>(),
      status: (map['status'] ?? 'pending').toString(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      error: map['error']?.toString(),
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
      'payload': payload,
      'status': status,
      'attempts': attempts,
      'error': error,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  PendingSyncAction copyWith({
    String? status,
    int? attempts,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return PendingSyncAction(
      id: id,
      type: type,
      scope: scope,
      payload: payload,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
