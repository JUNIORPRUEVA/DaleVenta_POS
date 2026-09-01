import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/token_storage.dart';
import '../debug/app_error_reporter.dart';
import '../debug/trace_log.dart';
import '../errors/api_exception.dart';
import 'offline_store.dart';
import 'pending_sync_action.dart';

typedef SyncQueueHandler = Future<void> Function(Map<String, dynamic> payload);
typedef SyncScopeResolver = Future<OfflineSyncScope?> Function();

class OfflineSyncScope {
  final String? companyId;
  final String? userId;

  const OfflineSyncScope({this.companyId, this.userId});

  bool get hasTenant => (companyId ?? '').trim().isNotEmpty;
  bool get hasUser => (userId ?? '').trim().isNotEmpty;

  OfflineSyncScope normalized() {
    String? clean(String? value) {
      final text = value?.trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return OfflineSyncScope(companyId: clean(companyId), userId: clean(userId));
  }
}

class SyncQueueState {
  final int pendingCount;
  final int syncingCount;
  final int errorCount;
  final int conflictCount;
  final bool isProcessing;
  final DateTime? lastSyncedAt;
  final DateTime? lastAttemptAt;
  final DateTime? lastErrorAt;
  final String? lastError;

  const SyncQueueState({
    this.pendingCount = 0,
    this.syncingCount = 0,
    this.errorCount = 0,
    this.conflictCount = 0,
    this.isProcessing = false,
    this.lastSyncedAt,
    this.lastAttemptAt,
    this.lastErrorAt,
    this.lastError,
  });

  SyncQueueState copyWith({
    int? pendingCount,
    int? syncingCount,
    int? errorCount,
    int? conflictCount,
    bool? isProcessing,
    DateTime? lastSyncedAt,
    DateTime? lastAttemptAt,
    DateTime? lastErrorAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncQueueState(
      pendingCount: pendingCount ?? this.pendingCount,
      syncingCount: syncingCount ?? this.syncingCount,
      errorCount: errorCount ?? this.errorCount,
      conflictCount: conflictCount ?? this.conflictCount,
      isProcessing: isProcessing ?? this.isProcessing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastErrorAt: clearError ? null : (lastErrorAt ?? this.lastErrorAt),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

final offlineStoreProvider = Provider<OfflineStore>((ref) {
  return OfflineStore.instance;
});

final syncQueueServiceProvider =
    StateNotifierProvider<SyncQueueService, SyncQueueState>((ref) {
      final storage = TokenStorage();
      final service = SyncQueueService(
        ref.read(offlineStoreProvider),
        scopeResolver: () async {
          final user = await storage.getUserSnapshot();
          return OfflineSyncScope(companyId: user?.companyId, userId: user?.id);
        },
      );
      return service;
    });

final syncQueueBootstrapProvider = Provider<void>((ref) {
  Future<void>.microtask(() {
    ref.read(syncQueueServiceProvider.notifier).start();
  });
});

class SyncQueueService extends StateNotifier<SyncQueueState> {
  SyncQueueService(this._store, {SyncScopeResolver? scopeResolver})
    : _scopeResolver = scopeResolver,
      super(const SyncQueueState());

  final OfflineStore _store;
  final SyncScopeResolver? _scopeResolver;
  final Map<String, SyncQueueHandler> _handlers = {};
  static const Duration staleSyncingAge = Duration(minutes: 2);
  static const String _lastSyncedAtKey = 'sync_queue.last_synced_at';
  static const String _lastAttemptAtKey = 'sync_queue.last_attempt_at';
  static const String _lastErrorAtKey = 'sync_queue.last_error_at';
  static const String _lastErrorKey = 'sync_queue.last_error';

  Timer? _timer;
  bool _started = false;
  bool _processing = false;
  final Random _jitter = Random();

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
    unawaited(_restoreSyncMeta());
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
    String? companyId,
    String? userId,
    String? terminalId,
    String? entityType,
    String? entityId,
    String? idempotencyKey,
  }) async {
    final activeScope = await _resolveScope();
    final resolvedCompanyId = _clean(companyId) ?? activeScope?.companyId;
    final resolvedUserId = _clean(userId) ?? activeScope?.userId;
    final resolvedIdempotencyKey =
        _clean(idempotencyKey) ??
        _clean(payload['operationId']?.toString()) ??
        _clean(payload['clientRequestId']?.toString());
    await _store.putPendingAction(
      PendingSyncAction(
        id: id,
        type: type,
        scope: scope,
        companyId: resolvedCompanyId,
        userId: resolvedUserId,
        terminalId: _clean(terminalId),
        entityType: _clean(entityType),
        entityId: _clean(entityId) ?? _clean(payload['id']?.toString()),
        idempotencyKey: resolvedIdempotencyKey,
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
      final scope = await _resolveScope();
      final stats = scope == null || !scope.hasTenant
          ? {'pending': 0, 'syncing': 0, 'error': 0, 'conflict': 0}
          : await _store.pendingActionStats(
              companyId: scope.companyId,
              userId: scope.userId,
            );
      _patchState(
        (current) => current.copyWith(
          pendingCount: stats['pending'] ?? 0,
          syncingCount: stats['syncing'] ?? 0,
          errorCount: stats['error'] ?? 0,
          conflictCount: stats['conflict'] ?? 0,
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
      final scope = await _resolveScope();
      if (scope == null || !scope.hasTenant) {
        TraceLog.log('sync_queue', 'process skipped without tenant scope');
        return;
      }
      await _store.recoverStaleSyncingActions(
        olderThan: staleSyncingAge,
        companyId: scope.companyId,
        userId: scope.userId,
      );

      final actions = await _store.listPendingActions(
        limit: 40,
        companyId: scope.companyId,
        userId: scope.userId,
        dueOnly: true,
      );
      for (final action in actions) {
        final handler = _handlers[action.type];
        if (handler == null) continue;
        if (action.permanent ||
            action.status == 'failed' ||
            action.status == 'conflict' ||
            action.status == 'requires_action' ||
            action.status == 'auth_blocked' ||
            action.status == 'tenant_mismatch') {
          continue;
        }

        final now = DateTime.now().toUtc();
        final syncing = action.copyWith(
          status: 'syncing',
          attempts: action.attempts + 1,
          lastAttemptAt: now,
          updatedAt: now,
          clearError: true,
          clearNextAttemptAt: true,
        );
        await _store.updatePendingAction(syncing);
        await _recordAttempt(now);
        await refreshStats();

        try {
          await handler(action.payload);
          await _store.removePendingAction(action.id);
          final syncedAt = DateTime.now().toUtc();
          TraceLog.log(
            'sync_queue',
            'sync success type=${action.type} id=${action.id}',
          );
          await _recordSuccess(syncedAt);
        } catch (error, stackTrace) {
          final permanent = _isPermanentFailure(error);
          final status = _failureStatus(error, permanent: permanent);
          final nextAttemptAt = permanent
              ? null
              : DateTime.now().toUtc().add(_backoffFor(syncing.attempts));
          TraceLog.log(
            'sync_queue',
            'sync $status type=${action.type} id=${action.id} attempts=${syncing.attempts}',
            error: error,
            stackTrace: stackTrace,
          );
          await _store.updatePendingAction(
            syncing.copyWith(
              status: status,
              error: '$error',
              nextAttemptAt: nextAttemptAt,
              permanent: permanent,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          await _recordError('$error', DateTime.now().toUtc());
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

  Future<OfflineSyncScope?> _resolveScope() async {
    try {
      return (await _scopeResolver?.call())?.normalized();
    } catch (error, stackTrace) {
      TraceLog.log(
        'sync_queue',
        'scope resolver failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _restoreSyncMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncedAt = _parseIso(prefs.getString(_lastSyncedAtKey));
      final lastAttemptAt = _parseIso(prefs.getString(_lastAttemptAtKey));
      final lastErrorAt = _parseIso(prefs.getString(_lastErrorAtKey));
      final lastError = prefs.getString(_lastErrorKey);
      _patchState(
        (current) => current.copyWith(
          lastSyncedAt: lastSyncedAt,
          lastAttemptAt: lastAttemptAt,
          lastErrorAt: lastErrorAt,
          lastError: (lastError ?? '').trim().isEmpty ? null : lastError,
        ),
      );
    } catch (error, stackTrace) {
      TraceLog.log(
        'sync_queue',
        'restore sync metadata failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _recordAttempt(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAttemptAtKey, at.toUtc().toIso8601String());
    } catch (_) {}
    _patchState((current) => current.copyWith(lastAttemptAt: at.toUtc()));
  }

  Future<void> _recordSuccess(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncedAtKey, at.toUtc().toIso8601String());
      await prefs.remove(_lastErrorAtKey);
      await prefs.remove(_lastErrorKey);
    } catch (_) {}
    _patchState(
      (current) => current.copyWith(
        lastSyncedAt: at.toUtc(),
        lastErrorAt: null,
        clearError: true,
      ),
    );
  }

  Future<void> _recordError(String message, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastErrorAtKey, at.toUtc().toIso8601String());
      await prefs.setString(_lastErrorKey, message);
    } catch (_) {}
    _patchState(
      (current) =>
          current.copyWith(lastErrorAt: at.toUtc(), lastError: message),
    );
  }

  DateTime? _parseIso(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  Duration _backoffFor(int attempts) {
    const schedule = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ];
    final index = (attempts - 1).clamp(0, schedule.length - 1);
    final base = schedule[index];
    return base + Duration(milliseconds: _jitter.nextInt(3000));
  }

  bool _isPermanentFailure(Object error) {
    if (error is ApiException) {
      if (error.retryable || error.isNetworkError) return false;
      return error.type == ApiErrorType.badRequest ||
          error.type == ApiErrorType.unauthorized ||
          error.type == ApiErrorType.forbidden ||
          error.type == ApiErrorType.notFound ||
          error.type == ApiErrorType.conflict;
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == null) return false;
      return status == 400 ||
          status == 401 ||
          status == 403 ||
          status == 404 ||
          status == 409 ||
          status == 422;
    }
    return false;
  }

  bool _isConflictFailure(Object error) {
    if (error is ApiException) return error.type == ApiErrorType.conflict;
    if (error is DioException) return error.response?.statusCode == 409;
    return false;
  }

  bool _isProductHistoryDecisionRequired(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        return data['code']?.toString() == 'PRODUCT_HAS_HISTORY' &&
            data['canArchive'] == true;
      }
    }
    if (error is ApiException) {
      return error.displayCode == 'PRODUCT_HAS_HISTORY';
    }
    return false;
  }

  String _failureStatus(Object error, {required bool permanent}) {
    if (_isProductHistoryDecisionRequired(error)) return 'requires_action';
    if (_isConflictFailure(error)) return 'conflict';
    if (error is ApiException &&
        (error.type == ApiErrorType.unauthorized ||
            error.type == ApiErrorType.forbidden)) {
      return 'auth_blocked';
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) return 'auth_blocked';
    }
    return permanent ? 'failed' : 'error';
  }

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
