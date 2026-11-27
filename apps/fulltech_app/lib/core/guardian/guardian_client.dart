import 'dart:async';
import 'dart:math';

import 'guardian_agent_log.dart';
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
    this.companyIdProvider,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  static GuardianClient? _instance;

  static GuardianClient? get instance => _instance;

  static void install(GuardianClient client) {
    _instance = client;
  }

  final GuardianStore store;
  final GuardianTransport transport;
  final GuardianConfig config;
  final Future<String?> Function()? companyIdProvider;
  final Random _random;
  final DateTime Function() _clock;

  static const Duration _dedupeWindow = Duration(minutes: 5);
  static const int _maxBackoffMs = 30 * 60 * 1000;

  bool _flushing = false;

  /// Registra un incidente. Devuelve `true` si quedó en la cola local.
  Future<bool> record(GuardianEvent event) async {
    if (!config.enabled) return false;
    if (!config.shouldPersist(event.severity)) {
      unawaited(
        GuardianAgentLog.info(
          'descartado por severidad sev=${event.severity} minimo=${config.minSeverityToPersist}',
        ),
      );
      return false;
    }

    try {
      if (companyIdProvider != null) {
        event = event.copyWith(
          context: {
            ...?event.context,
            '_guardianCompanyId': await companyIdProvider!() ?? 'unattributed',
          },
        );
      }
      final alreadySeen = await store.wasRecentlyRecorded(
        '${event.context?['_guardianCompanyId'] ?? ''}:' +
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
        '${event.context?['_guardianCompanyId'] ?? ''}:' +
            guardianFingerprint(
              module: event.module,
              operation: event.operation,
              exceptionType: event.exceptionType,
              stack: event.stack,
            ),
      );
      await _enforceQuotas();
      unawaited(
        GuardianAgentLog.info(
          'evento en cola id=${event.eventId} sev=${event.severity} mod=${event.module} op=${event.operation}',
        ),
      );
      return true;
    } catch (error) {
      // Guardian jamás puede romper el flujo que reporta.
      unawaited(
        GuardianAgentLog.warn('no se pudo encolar ${event.eventId}: $error'),
      );
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
        final companyId = companyIdProvider == null
            ? null
            : await companyIdProvider!();
        if (companyIdProvider != null && companyId == null) break;
        final due = await store.dueEvents(
          limit: config.batchSize,
          now: _clock(),
          companyId: companyId,
        );
        if (due.isEmpty) break;
        attempted += due.length;
        unawaited(GuardianAgentLog.info('flush: ${due.length} pendientes'));

        GuardianSendResult result;
        try {
          result = await transport.send(due);
        } catch (transportError) {
          result = GuardianSendResult(
            retryable: true,
            reason: transportError.toString(),
          );
        }
        unawaited(
          GuardianAgentLog.info(
            'respuesta: ok=${result.acked.length} dup=${result.duplicates.length} '
            'rech=${result.rejected.length} retry=${result.retryable} motivo=${result.reason ?? '-'}',
          ),
        );

        final sentIds = due.map((event) => event.eventId).toSet();
        final durable = <String>{...result.acked, ...result.duplicates}
            .where(
              (id) => sentIds.contains(id) && !result.rejected.contains(id),
            )
            .toList();
        if (durable.isNotEmpty) {
          await store.removeAll(durable);
          acknowledged += durable.length;
          unawaited(GuardianAgentLog.info('enviados=${durable.length}'));
        }

        if (result.rejected.isNotEmpty) {
          unawaited(
            GuardianAgentLog.warn(
              'rechazados=${result.rejected.length} motivo=${result.reason}',
            ),
          );
          for (final eventId in result.rejected) {
            if (!sentIds.contains(eventId)) continue;
            await store.recordDiscard(
              GuardianDiscardRecord(
                eventId: eventId,
                reason: result.reason ?? 'REJECTED_BY_SERVER',
                at: _clock(),
              ),
            );
            await store.markFailure(
              eventId,
              attempts: 1,
              nextAttemptAtMs: 253402300799000,
            );
          }
          rejected += result.rejected.length;
        }

        final pending = due
            .where(
              (event) =>
                  !durable.contains(event.eventId) &&
                  !result.rejected.contains(event.eventId),
            )
            .toList();

        if (pending.isNotEmpty) {
          final attempts = pending.first.attempts + 1;
          final nextAt =
              _clock().millisecondsSinceEpoch +
              max(_backoffMs(attempts), result.retryAfterMs ?? 0).toInt();
          for (final event in pending) {
            await store.markFailure(
              event.eventId,
              attempts: attempts,
              nextAttemptAtMs: nextAt,
            );
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
      return GuardianFlushSummary(
        attempted: attempted,
        error: unexpected.toString(),
      );
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
