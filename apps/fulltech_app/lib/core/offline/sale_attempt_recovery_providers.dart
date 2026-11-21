import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/trace_log.dart';
import '../auth/auth_repository.dart' show tokenStorageProvider;
import '../api/server_connection.dart';
import '../config/uat_identity.dart';
import 'sale_attempt_reconciliation_providers.dart';
import 'sale_attempt_recovery_engine.dart';
import 'recovery_review_publisher.dart';
import 'sync_queue_service.dart';

/// Persistencia del estado del motor en `SharedPreferences`.
///
/// Guarda solo dos datos: fallos consecutivos y la hora de la próxima pasada.
/// No guarda ningún dato financiero.
class PreferencesRecoveryEngineStore
    implements RecoveryEngineStore, ScopedRecoveryEngineStore {
  PreferencesRecoveryEngineStore();

  String _scope = 'unscoped';
  String get _failuresKey =>
      UatIdentity.storageKey('recovery.engine.$_scope.consecutive_failures');
  String get _nextRunKey =>
      UatIdentity.storageKey('recovery.engine.$_scope.next_run_at');

  @override
  void selectScope(String companyId, String userId) {
    _scope = '${Uri.encodeComponent(companyId)}:${Uri.encodeComponent(userId)}';
  }

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
  final storage = ref.watch(tokenStorageProvider);
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
    scopeResolver: () async {
      final user = await storage.getUserSnapshot();
      return {'companyId': user?.companyId, 'userId': user?.id};
    },
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Arranca el motor: restaura el estado, hace la pasada inicial y mantiene un
/// chequeo periódico que solo actúa cuando hay incidencias pendientes.
final recoveryEngineBootstrapProvider = Provider<void>((ref) {
  final engine = ref.watch(recoveryEngineProvider);
  final syncQueue = ref.read(syncQueueServiceProvider.notifier);
  final publisher = ref.watch(recoveryReviewPublisherProvider);
  Future<void> publish() async {
    try { await publisher.runOnce(); }
    catch (error) { TraceLog.log('recovery', 'publication.deferred', error: error); }
  }
  ref.listen(serverConnectionProvider, (previous, next) {
    if (next == ServerConnection.reachable && previous != next) {
      unawaited(engine.runOnce(trigger: RecoveryTrigger.connectivityRestored));
      unawaited(syncQueue.processPending());
      unawaited(publish());
    }
  });

  Future<void>.microtask(() async {
    try {
      await engine.restore();
      unawaited(publish());
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
    unawaited(publish());
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

/// Estado del motor para la interfaz (solo lectura).
///
/// Se emite con el estado inicial y luego con cada cambio del motor, para que la
/// pantalla muestre «en curso», «sin conexión», «última verificación», etc. sin
/// abrir ninguna ventana emergente.
final recoveryEngineStateProvider = StreamProvider<RecoveryEngineState>((
  ref,
) async* {
  final engine = ref.watch(recoveryEngineProvider);
  yield engine.state;
  yield* engine.states;
});
