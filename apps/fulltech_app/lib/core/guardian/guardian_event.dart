import 'dart:convert';

/// Evento de incidente listo para el backend Guardian.
///
/// Los nombres de campo coinciden exactamente con el DTO del API
/// (`apps/api/src/guardian/dto/guardian-ingest.dto.ts`).
class GuardianEvent {
  const GuardianEvent({
    required this.eventId,
    required this.severity,
    required this.module,
    required this.operation,
    required this.occurredAt,
    this.exceptionType,
    this.platform,
    this.appVersion,
    this.deviceId,
    this.correlationId,
    this.stack,
    this.message,
    this.offlineMinutes,
    this.context,
    this.attempts = 0,
    this.nextAttemptAtMs = 0,
  });

  final String eventId;
  final String severity;
  final String module;
  final String operation;
  final DateTime occurredAt;
  final String? exceptionType;
  final String? platform;
  final String? appVersion;
  final String? deviceId;
  final String? correlationId;
  final String? stack;
  final String? message;
  final int? offlineMinutes;
  final Map<String, dynamic>? context;

  /// Intentos de envío realizados.
  final int attempts;

  /// Momento (epoch ms) a partir del cual se puede reintentar.
  final int nextAttemptAtMs;

  GuardianEvent copyWith({int? attempts, int? nextAttemptAtMs}) {
    return GuardianEvent(
      eventId: eventId,
      severity: severity,
      module: module,
      operation: operation,
      occurredAt: occurredAt,
      exceptionType: exceptionType,
      platform: platform,
      appVersion: appVersion,
      deviceId: deviceId,
      correlationId: correlationId,
      stack: stack,
      message: message,
      offlineMinutes: offlineMinutes,
      context: context,
      attempts: attempts ?? this.attempts,
      nextAttemptAtMs: nextAttemptAtMs ?? this.nextAttemptAtMs,
    );
  }

  Map<String, dynamic> toApiJson() {
    return <String, dynamic>{
      'eventId': eventId,
      'severity': severity,
      'module': module,
      'operation': operation,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      if (exceptionType != null && exceptionType!.isNotEmpty) 'exceptionType': exceptionType,
      if (platform != null && platform!.isNotEmpty) 'platform': platform,
      if (appVersion != null && appVersion!.isNotEmpty) 'appVersion': appVersion,
      if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
      if (correlationId != null && correlationId!.isNotEmpty) 'correlationId': correlationId,
      if (stack != null && stack!.isNotEmpty) 'stack': stack,
      if (message != null && message!.isNotEmpty) 'message': message,
      if (offlineMinutes != null) 'offlineMinutes': offlineMinutes,
      'schemaVersion': 1,
      if (context != null && context!.isNotEmpty) 'context': context,
    };
  }

  String toDbJson() => jsonEncode(toApiJson());

  static GuardianEvent fromDbRow(Map<String, dynamic> row) {
    final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    return GuardianEvent(
      eventId: payload['eventId'] as String,
      severity: payload['severity'] as String,
      module: payload['module'] as String,
      operation: payload['operation'] as String,
      occurredAt: DateTime.parse(payload['occurredAt'] as String),
      exceptionType: payload['exceptionType'] as String?,
      platform: payload['platform'] as String?,
      appVersion: payload['appVersion'] as String?,
      deviceId: payload['deviceId'] as String?,
      correlationId: payload['correlationId'] as String?,
      stack: payload['stack'] as String?,
      message: payload['message'] as String?,
      offlineMinutes: payload['offlineMinutes'] as int?,
      context: (payload['context'] as Map?)?.cast<String, dynamic>(),
      attempts: (row['attempts'] as int?) ?? 0,
      nextAttemptAtMs: (row['next_attempt_at_ms'] as int?) ?? 0,
    );
  }
}
