import 'guardian_event.dart';

/// Resultado de un envío al backend.
class GuardianSendResult {
  const GuardianSendResult({
    this.acked = const [],
    this.duplicates = const [],
    this.rejected = const [],
    this.retryable = true,
    this.reason,
  });

  /// Eventos persistidos por el servidor (se pueden borrar localmente).
  final List<String> acked;

  /// Eventos que ya existían (idempotencia del servidor); también son durables.
  final List<String> duplicates;

  /// Eventos rechazados de forma permanente (no se reintentan).
  final List<String> rejected;

  /// Si el fallo es recuperable (red, 5xx, 429).
  final bool retryable;

  final String? reason;
}

abstract class GuardianTransport {
  Future<GuardianSendResult> send(List<GuardianEvent> events);
}
