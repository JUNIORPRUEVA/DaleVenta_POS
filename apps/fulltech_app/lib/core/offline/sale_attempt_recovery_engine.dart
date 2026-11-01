import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../debug/trace_log.dart';
import 'sale_attempt_reconciliation.dart';

/// Motor de recuperación automática de intentos de cobro inciertos.
///
/// Sustituye el barrido único de arranque por una política con disparadores,
/// deduplicación y backoff. Reglas que NUNCA se relajan:
///
///  - Solo se consultan endpoints de VERIFICACIÓN (solo lectura, idempotentes).
///    Jamás se reenvía un cobro ni se crea una venta.
///  - Un fallo técnico (sin red, 401, 429, 5xx, timeout) no resuelve nada y no
///    se convierte en una decisión financiera.
///  - Si no hay incidencias pendientes, no se hace ni una sola consulta.
///  - Estado persistido: tras cerrar y abrir la app se recuerda el backoff para
///    no martillear el servidor ni reiniciar la espera desde cero.
///
/// El motor es una máquina de estados sin timers propios (los pone el
/// proveedor), para poder probarlo con reloj y persistencia falsos.
enum RecoveryTrigger {
  startup,
  connectivityRestored,
  syncCompleted,
  periodic,
  manual,
}

enum RecoveryRunOutcome {
  /// No había nada pendiente: no se consultó nada.
  idle,

  /// Se ejecutó y todo quedó concluyente o resuelto.
  completed,

  /// Se ejecutó pero el servidor no respondió a alguna consulta.
  partiallyUnreachable,

  /// Se pospuso por backoff, single-flight o rate limit.
  deferred,
}

/// Estado observable del motor para la interfaz.
@immutable
class RecoveryEngineState {
  const RecoveryEngineState({
    this.pendingAttempts = 0,
    this.lastRunAt,
    this.nextRunAt,
    this.consecutiveFailures = 0,
    this.lastOutcome,
    this.suspendedUntil,
    this.running = false,
  });

  final int pendingAttempts;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final int consecutiveFailures;
  final RecoveryRunOutcome? lastOutcome;
  final DateTime? suspendedUntil;
  final bool running;

  bool get waitingForConnection =>
      suspendedUntil != null && suspendedUntil!.isAfter(DateTime.now().toUtc());

  RecoveryEngineState copyWith({
    int? pendingAttempts,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    int? consecutiveFailures,
    RecoveryRunOutcome? lastOutcome,
    DateTime? suspendedUntil,
    bool? running,
    bool clearSuspension = false,
    bool clearNextRun = false,
  }) {
    return RecoveryEngineState(
      pendingAttempts: pendingAttempts ?? this.pendingAttempts,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: clearNextRun ? null : (nextRunAt ?? this.nextRunAt),
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastOutcome: lastOutcome ?? this.lastOutcome,
      suspendedUntil: clearSuspension
          ? null
          : (suspendedUntil ?? this.suspendedUntil),
      running: running ?? this.running,
    );
  }
}

/// Persistencia mínima (SharedPreferences en producción, memoria en pruebas).
abstract class RecoveryEngineStore {
  Future<int> readFailures();
  Future<DateTime?> readNextRunAt();

  Future<void> writeState({required int failures, DateTime? nextRunAt});
}

class InMemoryRecoveryEngineStore implements RecoveryEngineStore {
  int _failures = 0;
  DateTime? _nextRunAt;

  @override
  Future<int> readFailures() async => _failures;

  @override
  Future<DateTime?> readNextRunAt() async => _nextRunAt;

  @override
  Future<void> writeState({required int failures, DateTime? nextRunAt}) async {
    _failures = failures;
    _nextRunAt = nextRunAt;
  }
}

/// Política de espera. Base 30 s, duplica hasta 30 min, con jitter del 20 %.
class RecoveryBackoffPolicy {
  const RecoveryBackoffPolicy({
    this.base = const Duration(seconds: 30),
    this.max = const Duration(minutes: 30),
    this.jitterRatio = 0.2,
    this.maxAttemptsPerRun = 25,
  });

  final Duration base;
  final Duration max;
  final double jitterRatio;
  final int maxAttemptsPerRun;

  Duration delayFor(int failures, {required Random random}) {
    if (failures <= 0) return Duration.zero;
    final exponent = min(failures - 1, 20);
    final rawMs = base.inMilliseconds * pow(2, exponent);
    final cappedMs = min(rawMs.toDouble(), max.inMilliseconds.toDouble());
    final jitter = cappedMs * jitterRatio;
    final delta = (random.nextDouble() * 2 - 1) * jitter;
    final result = (cappedMs + delta).clamp(
      base.inMilliseconds.toDouble(),
      max.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: result.round());
  }
}

class SaleAttemptRecoveryEngine {
  SaleAttemptRecoveryEngine({
    required SaleAttemptReconciler reconciler,
    required Future<int> Function({String? companyId, String? userId})
    countPending,
    required RecoveryEngineStore store,
    RecoveryBackoffPolicy policy = const RecoveryBackoffPolicy(),
    DateTime Function()? clock,
    Random? random,
    Map<String, String?> Function()? scopeResolver,
  }) : _reconciler = reconciler,
       _countPending = countPending,
       _store = store,
       _policy = policy,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random(),
       _scopeResolver = scopeResolver;

  final SaleAttemptReconciler _reconciler;
  final Future<int> Function({String? companyId, String? userId}) _countPending;
  final RecoveryEngineStore _store;
  final RecoveryBackoffPolicy _policy;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, String?> Function()? _scopeResolver;

  final StreamController<RecoveryEngineState> _states =
      StreamController<RecoveryEngineState>.broadcast();

  RecoveryEngineState _state = const RecoveryEngineState();
  bool _running = false;
  Duration? _retryAfter;

  Stream<RecoveryEngineState> get states => _states.stream;
  RecoveryEngineState get state => _state;

  /// El proveedor de red avisa aquí cuando el backend responde 429 con
  /// `Retry-After`. La siguiente ejecución lo respeta sin ignorarlo.
  void noteRateLimit(Duration? retryAfter) {
    _retryAfter = retryAfter;
  }

  void _emit(RecoveryEngineState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> restore() async {
    final failures = await _store.readFailures();
    final nextRunAt = await _store.readNextRunAt();
    _emit(
      _state.copyWith(
        consecutiveFailures: failures,
        nextRunAt: nextRunAt,
        clearNextRun: nextRunAt == null,
      ),
    );
  }

  /// Decide si toca ejecutar. Un disparador explícito (reconexión, manual)
  /// puede adelantar la espera; el periódico no.
  bool shouldRunNow(RecoveryTrigger trigger) {
    if (_running) return false;
    if (trigger == RecoveryTrigger.connectivityRestored ||
        trigger == RecoveryTrigger.manual) {
      return true;
    }
    final next = _state.nextRunAt;
    if (next == null) return true;
    return !_clock().isBefore(next);
  }

  /// Una pasada. Nunca lanza: los fallos se convierten en backoff.
  Future<RecoveryRunOutcome> runOnce({
    RecoveryTrigger trigger = RecoveryTrigger.periodic,
    String? companyId,
    String? userId,
  }) async {
    if (_running) {
      TraceLog.log(
        'recovery',
        'pasada.ignorada ya.en.curso trigger=${trigger.name}',
      );
      return RecoveryRunOutcome.deferred;
    }

    // Rate limit explícito del servidor: se respeta aunque el disparador sea
    // manual o de reconexión.
    final retryAfter = _retryAfter;
    if (retryAfter != null && retryAfter > Duration.zero) {
      _retryAfter = null;
      final until = _clock().add(retryAfter);
      await _store.writeState(
        failures: _state.consecutiveFailures,
        nextRunAt: until,
      );
      _emit(_state.copyWith(nextRunAt: until, suspendedUntil: until));
      TraceLog.log('recovery', 'rate.limit espera=${retryAfter.inSeconds}s');
      return RecoveryRunOutcome.deferred;
    }

    if (!shouldRunNow(trigger)) {
      TraceLog.log('recovery', 'pasada.pospuesta trigger=${trigger.name}');
      return RecoveryRunOutcome.deferred;
    }

    final scope = _scopeResolver?.call();
    final resolvedCompany = companyId ?? scope?['companyId'];
    final resolvedUser = userId ?? scope?['userId'];

    _running = true;
    _emit(_state.copyWith(running: true));
    try {
      // Sin pendientes no se consulta nada: ni una petición.
      final pending = await _countPending(
        companyId: resolvedCompany,
        userId: resolvedUser,
      );
      if (pending <= 0) {
        await _persist(failures: 0, nextRunAt: null);
        _emit(
          _state.copyWith(
            pendingAttempts: 0,
            lastRunAt: _clock(),
            consecutiveFailures: 0,
            lastOutcome: RecoveryRunOutcome.idle,
            running: false,
            clearSuspension: true,
            clearNextRun: true,
          ),
        );
        return RecoveryRunOutcome.idle;
      }

      final summary = await _reconciler.syncPendingAttempts(
        companyId: resolvedCompany,
        userId: resolvedUser,
        maxAttempts: _policy.maxAttemptsPerRun,
      );

      final unreachable = summary.unreachable > 0;
      final failures = unreachable ? _state.consecutiveFailures + 1 : 0;
      final delay = _policy.delayFor(failures, random: _random);
      final nextRunAt = failures == 0 ? null : _clock().add(delay);

      await _persist(failures: failures, nextRunAt: nextRunAt);

      final remaining = await _countPending(
        companyId: resolvedCompany,
        userId: resolvedUser,
      );
      final outcome = unreachable
          ? RecoveryRunOutcome.partiallyUnreachable
          : RecoveryRunOutcome.completed;

      TraceLog.log(
        'recovery',
        'pasada.fin trigger=${trigger.name} pendientes=$pending restantes=$remaining '
            'confirmados=${summary.confirmed} conservados=${summary.inconclusive} '
            'sinRespuesta=${summary.unreachable} fallos=$failures',
      );

      _emit(
        _state.copyWith(
          pendingAttempts: remaining,
          lastRunAt: _clock(),
          consecutiveFailures: failures,
          lastOutcome: outcome,
          suspendedUntil: unreachable ? nextRunAt : null,
          clearSuspension: !unreachable,
          nextRunAt: nextRunAt,
          clearNextRun: nextRunAt == null,
          running: false,
        ),
      );
      return outcome;
    } catch (error) {
      // Un fallo inesperado tampoco puede convertirse en decisión financiera:
      // solo se cuenta para el backoff.
      final failures = _state.consecutiveFailures + 1;
      final delay = _policy.delayFor(failures, random: _random);
      final nextRunAt = _clock().add(delay);
      await _persist(failures: failures, nextRunAt: nextRunAt);
      TraceLog.log(
        'recovery',
        'pasada.error trigger=${trigger.name} fallos=$failures',
        error: error,
      );
      _emit(
        _state.copyWith(
          consecutiveFailures: failures,
          nextRunAt: nextRunAt,
          suspendedUntil: nextRunAt,
          lastOutcome: RecoveryRunOutcome.partiallyUnreachable,
          lastRunAt: _clock(),
          running: false,
        ),
      );
      return RecoveryRunOutcome.partiallyUnreachable;
    } finally {
      _running = false;
      if (_state.running) _emit(_state.copyWith(running: false));
    }
  }

  Future<void> _persist({required int failures, DateTime? nextRunAt}) async {
    try {
      await _store.writeState(failures: failures, nextRunAt: nextRunAt);
    } catch (error) {
      TraceLog.log('recovery', 'estado.no.persistido', error: error);
    }
  }

  Future<void> dispose() async {
    await _states.close();
  }
}
