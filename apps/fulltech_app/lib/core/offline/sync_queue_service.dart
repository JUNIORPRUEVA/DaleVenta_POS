import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/app_error_reporter.dart';
import '../debug/trace_log.dart';
import 'offline_store.dart';
import 'pending_sync_action.dart';

typedef SyncQueueHandler = Future<void> Function(Map<String, dynamic> payload);

class SyncQueueState {
  final int pendingCount;
  final int syncingCount;
  final int errorCount;
  final bool isProcessing;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const SyncQueueState({
    this.pendingCount = 0,
    this.syncingCount = 0,
    this.errorCount = 0,
    this.isProcessing = false,
    this.lastSyncedAt,
    this.lastError,
  });

  SyncQueueState copyWith({
    int? pendingCount,
    int? syncingCount,
    int? errorCount,
    bool? isProcessing,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncQueueState(
      pendingCount: pendingCount ?? this.pendingCount,
      syncingCount: syncingCount ?? this.syncingCount,
      errorCount: errorCount ?? this.errorCount,
      isProcessing: isProcessing ?? this.isProcessing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

final offlineStoreProvider = Provider<OfflineStore>((ref) {
  return OfflineStore.instance;
});

final syncQueueServiceProvider =
    StateNotifierProvider<SyncQueueService, SyncQueueState>((ref) {
      final service = SyncQueueService(ref.read(offlineStoreProvider));
      return service;
    });

final syncQueueBootstrapProvider = Provider<void>((ref) {
  Future<void>.microtask(() {
    ref.read(syncQueueServiceProvider.notifier).start();
  });
});

class SyncQueueService extends StateNotifier<SyncQueueState> {
  SyncQueueService(this._store) : super(const SyncQueueState());

  final OfflineStore _store;
  final Map<String, SyncQueueHandler> _handlers = {};

  Timer? _timer;
  bool _started = false;
  bool _processing = false;

  void _patchState(SyncQueueState Function(SyncQueueState current) update) {
    if (!mounted) return;
    state = update(state);
  }

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(processPending()),
    );
    unawaited(refreshStats());
    unawaited(processPending());
  }

  void registerHandler(String type, SyncQueueHandler handler) {
    _handlers[type] = handler;
  }

  Future<void> enqueue({
    required String id,
    required String type,
    required String scope,
    required Map<String, dynamic> payload,
  }) async {
    await _store.putPendingAction(
      PendingSyncAction(
        id: id,
        type: type,
        scope: scope,
        payload: payload,
        status: 'pending',
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    TraceLog.log('sync_queue', 'enqueued type=$type scope=$scope id=$id');
    await refreshStats();
    unawaited(processPending());
  }

  Future<void> remove(String id) async {
    await _store.removePendingAction(id);
    await refreshStats();
  }

  Future<void> refreshStats() async {
    try {
      final stats = await _store.pendingActionStats();
      _patchState(
        (current) => current.copyWith(
          pendingCount: stats['pending'] ?? 0,
          syncingCount: stats['syncing'] ?? 0,
          errorCount: stats['error'] ?? 0,
        ),
      );
    } catch (error, stackTrace) {
      TraceLog.log(
        'sync_queue',
        'refresh stats failed',
        error: error,
        stackTrace: stackTrace,
      );
      AppErrorReporter.instance.record(
        error,
        stackTrace,
        context: 'SyncQueue.refreshStats',
        title: 'Sincronizacion en segundo plano limitada',
        userMessage:
            'No se pudo actualizar el estado de la cola offline. La app seguira operando y reintentara automaticamente.',
        technicalDetails:
            'Fallo al consultar estadisticas locales de sincronizacion.',
        severity: AppErrorSeverity.warning,
        dedupeKey: 'sync-queue-refresh-stats-failed',
        retryLabel: 'Reintentar',
        onRetry: refreshStats,
      );
      _patchState((current) => current.copyWith(lastError: '$error'));
    }
  }

  Future<void> processPending() async {
    if (_processing) return;
    _processing = true;
    _patchState(
      (current) => current.copyWith(isProcessing: true, clearError: true),
    );

    try {
      final actions = await _store.listPendingActions(limit: 40);
      for (final action in actions) {
        final handler = _handlers[action.type];
        if (handler == null) continue;

        final syncing = action.copyWith(
          status: 'syncing',
          attempts: action.attempts + 1,
          updatedAt: DateTime.now().toUtc(),
          clearError: true,
        );
        await _store.updatePendingAction(syncing);
        await refreshStats();

        try {
          await handler(action.payload);
          await _store.removePendingAction(action.id);
          TraceLog.log(
            'sync_queue',
            'sync success type=${action.type} id=${action.id}',
          );
          _patchState(
            (current) => current.copyWith(lastSyncedAt: DateTime.now().toUtc()),
          );
        } catch (error, stackTrace) {
          TraceLog.log(
            'sync_queue',
            'sync error type=${action.type} id=${action.id}',
            error: error,
            stackTrace: stackTrace,
          );
          await _store.updatePendingAction(
            syncing.copyWith(
              status: 'error',
              error: '$error',
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          _patchState((current) => current.copyWith(lastError: '$error'));
        }
      }
    } catch (error, stackTrace) {
      TraceLog.log(
        'sync_queue',
        'process pending failed',
        error: error,
        stackTrace: stackTrace,
      );
      AppErrorReporter.instance.record(
        error,
        stackTrace,
        context: 'SyncQueue.processPending',
        title: 'Sincronizacion protegida',
        userMessage:
            'La sincronizacion en segundo plano encontro un problema y seguira reintentando sin cerrar la aplicacion.',
        technicalDetails:
            'La cola offline detecto un error no controlado mientras procesaba acciones pendientes.',
        severity: AppErrorSeverity.warning,
        dedupeKey: 'sync-queue-process-pending-failed',
        retryLabel: 'Reintentar',
        onRetry: processPending,
      );
      _patchState((current) => current.copyWith(lastError: '$error'));
    } finally {
      _processing = false;
      _patchState((current) => current.copyWith(isProcessing: false));
      await refreshStats();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
