import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/trace_log.dart';
import 'sale_attempt_reconciliation_providers.dart';
import 'sale_attempt_recovery_engine.dart';
import 'sync_queue_service.dart';

/// Persistencia del estado del motor en `SharedPreferences`.
///
/// Guarda solo dos datos: fallos consecutivos y la hora de la próxima pasada.
/// No guarda ningún dato financiero.
class PreferencesRecoveryEngineStore implements RecoveryEngineStore {
  PreferencesRecoveryEngineStore();

  static const _failuresKey = 'recovery.engine.consecutive_failures';
  static const _nextRunKey = 'recovery.engine.next_run_at';

  @override
  Future<int> readFailures() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failuresKey) ?? 0;
  }

  @override
  Future<DateTime?> readNextRunAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nextRunKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> writeState({required int failures, DateTime? nextRunAt}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_failuresKey, failures);
    if (nextRunAt == null) {
      await prefs.remove(_nextRunKey);
    } else {
      await prefs.setString(_nextRunKey, nextRunAt.toUtc().toIso8601String());
    }
  }
}

final recoveryEngineStoreProvider = Provider<RecoveryEngineStore>((ref) {
  return PreferencesRecoveryEngineStore();
});

/// Motor único de recuperación automática de la app.
final recoveryEngineProvider = Provider<SaleAttemptRecoveryEngine>((ref) {
  final reconciler = ref.watch(saleAttemptReconcilerProvider);
  final store = ref.watch(offlineStoreProvider);
  final engine = SaleAttemptRecoveryEngine(
    reconciler: reconciler,
    countPending: ({companyId, userId}) async {
      // Sin empresa/usuario no hay ámbito: no se consulta nada.
      if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) return 0;
      return store.countUnresolvedSaleAttempts(
        companyId: companyId!,
        userId: userId!,
      );
    },
    store: ref.watch(recoveryEngineStoreProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Arranca el motor: restaura el estado, hace la pasada inicial y mantiene un
/// chequeo periódico que solo actúa cuando hay incidencias pendientes.
final recoveryEngineBootstrapProvider = Provider<void>((ref) {
  final engine = ref.read(recoveryEngineProvider);
  final syncQueue = ref.read(syncQueueServiceProvider.notifier);

  Future<void>.microtask(() async {
    try {
      await engine.restore();
      final outcome = await engine.runOnce(trigger: RecoveryTrigger.startup);
      if (outcome == RecoveryRunOutcome.completed) {
        await syncQueue.refreshStats();
      }
    } catch (error) {
      // Fail-closed: un fallo del motor nunca puede afectar a la venta.
      TraceLog.log('recovery', 'bootstrap.fallido', error: error);
    }
  });

  final timer = Timer.periodic(const Duration(seconds: 15), (_) {
    unawaited(engine.runOnce(trigger: RecoveryTrigger.periodic));
  });
  ref.onDispose(timer.cancel);
});

/// Helpers para que el resto de la app dispare la recuperación sin conocer el
/// motor. Se usan desde la cola de sincronización y desde el centro de
/// recuperación.
extension RecoveryEngineRefTriggers on WidgetRef {
  Future<RecoveryRunOutcome> triggerRecoveryAfterSync() {
    return read(
      recoveryEngineProvider,
    ).runOnce(trigger: RecoveryTrigger.syncCompleted);
  }

  Future<RecoveryRunOutcome> triggerRecoveryAfterReconnect() {
    return read(
      recoveryEngineProvider,
    ).runOnce(trigger: RecoveryTrigger.connectivityRestored);
  }
}
