import 'dart:math';

import 'guardian_config.dart';
import 'guardian_event.dart';
import 'guardian_redaction.dart';
import 'guardian_store.dart';
import 'guardian_transport.dart';

class GuardianFlushSummary {
  const GuardianFlushSummary({
    this.attempted = 0,
    this.acknowledged = 0,
    this.rejected = 0,
    this.retried = 0,
    this.skipped = 0,
    this.error,
  });

  final int attempted;
  final int acknowledged;
  final int rejected;
  final int retried;
  final int skipped;
  final String? error;
}

/// Orquestador de la cola local de incidentes.
///
/// Principios:
/// - Registrar es **no bloqueante** para quien llama y nunca lanza.
/// - Un evento solo se borra tras confirmación durable del servidor.
/// - Reintentos con backoff exponencial y jitter.
/// - Cuotas locales con descarte registrado (nunca de SEV1/SEV2).
class GuardianClient {
  GuardianClient({
    required this.store,
    required this.transport,
    required this.config,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random(),
        _clock = clock ?? DateTime.now;

  static GuardianClient? _instance;

  static GuardianClient? get instance => _instance;

  static void install(GuardianClient client) {
    _instance = client;
  }

  final GuardianStore store;
  final GuardianTransport transport;
  final GuardianConfig config;
  final Random _random;
  final DateTime Function() _clock;

  static const Duration _dedupeWindow = Duration(minutes: 5);
  static const int _maxBackoffMs = 30 * 60 * 1000;

  bool _flushing = false;

  /// Registra un incidente. Devuelve `true` si quedó en la cola local.
  Future<bool> record(GuardianEvent event) async {
    if (!config.enabled) return false;
    if (!config.shouldPersist(event.severity)) return false;

    try {
      final alreadySeen = await store.wasRecentlyRecorded(
        guardianFingerprint(
          module: event.module,
          operation: event.operation,
          exceptionType: event.exceptionType,
          stack: event.stack,
        ),
        window: _dedupeWindow,
      );
      if (alreadySeen) return false;

      await store.upsert(event);
      await store.markRecorded(
        guardianFingerprint(
          module: event.module,
          operation: event.operation,
          exceptionType: event.exceptionType,
          stack: event.stack,
        ),
      );
      await _enforceQuotas();
      return true;
    } catch (_) {
      // Guardian jamás puede romper el flujo que reporta.
      return false;
    }
  }

  Future<void> _enforceQuotas() async {
    final count = await store.count();
    final bytes = await store.totalBytes();
    final overflowEvents = count - config.maxEvents;
    final overflowBytes = bytes - config.maxBytes;
    if (overflowEvents <= 0 && overflowBytes <= 0) return;

    final victims = await store.selectForEviction(
      eventsToDrop: overflowEvents > 0 ? overflowEvents : 0,
      bytesToDrop: overflowBytes > 0 ? overflowBytes : 0,
    );
    if (victims.isEmpty) return;

    for (final victim in victims) {
      await store.recordDiscard(
        GuardianDiscardRecord(
          eventId: victim.eventId,
          reason: 'LOCAL_QUOTA',
          at: _clock(),
        ),
      );
    }
    await store.removeAll(victims.map((event) => event.eventId));
  }

  /// Envía los eventos pendientes. Nunca lanza.
  Future<GuardianFlushSummary> flush({int? maxBatches}) async {
    if (!config.enabled || _flushing) {
      return const GuardianFlushSummary(skipped: 1);
    }
    _flushing = true;
    var attempted = 0;
    var acknowledged = 0;
    var rejected = 0;
    var retried = 0;
    String? error;

    try {
      final batches = maxBatches ?? 3;
      for (var batch = 0; batch < batches; batch++) {
        final due = await store.dueEvents(limit: config.batchSize, now: _clock());
        if (due.isEmpty) break;
        attempted += due.length;

        GuardianSendResult result;
        try {
          result = await transport.send(due);
        } catch (transportError) {
          result = GuardianSendResult(retryable: true, reason: transportError.toString());
        }

        final durable = <String>[...result.acked, ...result.duplicates];
        if (durable.isNotEmpty) {
          await store.removeAll(durable);
          acknowledged += durable.length;
        }

        if (result.rejected.isNotEmpty) {
          for (final eventId in result.rejected) {
            await store.recordDiscard(
              GuardianDiscardRecord(
                eventId: eventId,
                reason: result.reason ?? 'REJECTED_BY_SERVER',
                at: _clock(),
              ),
            );
          }
          await store.removeAll(result.rejected);
          rejected += result.rejected.length;
        }

        final pending = due
            .where((event) => !durable.contains(event.eventId) && !result.rejected.contains(event.eventId))
            .toList();

        if (pending.isNotEmpty) {
          final attempts = pending.first.attempts + 1;
          final nextAt = _clock().millisecondsSinceEpoch + _backoffMs(attempts);
          for (final event in pending) {
            await store.markFailure(event.eventId, attempts: attempts, nextAttemptAtMs: nextAt);
          }
          retried += pending.length;
          error = result.reason;
          // Sin conectividad: no seguir insistiendo en este ciclo.
          if (!result.retryable) break;
          break;
        }
      }

      return GuardianFlushSummary(
        attempted: attempted,
        acknowledged: acknowledged,
        rejected: rejected,
        retried: retried,
        error: error,
      );
    } catch (unexpected) {
      return GuardianFlushSummary(attempted: attempted, error: unexpected.toString());
    } finally {
      _flushing = false;
    }
  }

  /// Backoff exponencial con jitter (±25 %).
  int _backoffMs(int attempts) {
    final base = attempts <= 1 ? 30000 : 30000 * pow(2, attempts - 1).toInt();
    final capped = min(_maxBackoffMs, base);
    final jitter = 0.75 + _random.nextDouble() * 0.5;
    return (capped * jitter).round();
  }
}
