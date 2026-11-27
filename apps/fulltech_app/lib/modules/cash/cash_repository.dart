import 'dart:math';
import '../../core/app_update/update_critical_operation_gate.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_offline_circuit_breaker.dart';
import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/token_storage.dart';
import '../../core/auth/operation_scope.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/debug/trace_log.dart';
import '../../core/errors/api_exception.dart';
import '../../core/errors/operation_error_message.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/pending_sync_action.dart';
import '../../core/offline/offline_emergency_policy.dart';
import '../../core/usage/client_telemetry_headers.dart';
import '../../core/time/business_time.dart';
import '../../core/offline/sync_queue_service.dart';
import 'cash_models.dart';

/// El turno ya no está abierto (lo cerró este dispositivo u otro). No es un
/// error real: el estado correcto es CERRADO y la UI debe converger a él.
class CashSessionAlreadyClosedException implements Exception {
  const CashSessionAlreadyClosedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// El cierre quedó guardado localmente y pendiente de sincronizar. No equivale
/// a un cierre confirmado contra el backend.
class CashClosePendingSyncException implements Exception {
  const CashClosePendingSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `true` cuando el backend confirma que NO hay turno abierto.
///
/// `GET /cash/summary` (y el resto de lecturas operativas) exige un turno
/// abierto y responde 404 cuando no existe. Es un estado de negocio esperado
/// (p. ej. justo después de cerrar el turno), NO un fallo: la UI debe informar
/// y revalidar el estado, nunca tratarlo como error técnico ni escalarlo al
/// sistema global de errores.
bool isCashNoOpenSessionError(Object? error) {
  if (error is! ApiException) return false;
  return error.code == 404 || error.type == ApiErrorType.notFound;
}

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  final repository = CashRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
    offlineStore: ref.read(offlineStoreProvider),
    offlineCircuitState: ref.read(apiOfflineCircuitStateProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
  repository.registerSyncHandlers();
  return repository;
});

class CashRepository {
  CashRepository(
    this._dio,
    this._syncQueue, {
    OfflineStore? offlineStore,
    ApiOfflineCircuitState? offlineCircuitState,
    TokenStorage? tokenStorage,
  }) : _offlineStore = offlineStore ?? _syncQueue.store,
       _offlineCircuitState = offlineCircuitState,
       _tokenStorage = tokenStorage ?? TokenStorage();

  final Dio _dio;
  final SyncQueueService _syncQueue;
  final OfflineStore _offlineStore;
  final ApiOfflineCircuitState? _offlineCircuitState;
  final LocalJsonCache _cache = LocalJsonCache();
  final TokenStorage _tokenStorage;
  bool _handlersRegistered = false;

  /// `true` si la última llamada a [state] cayó a la caché local por un fallo
  /// de red transitorio. Los consumidores NO deben tratar ese estado como un
  /// turno confirmado contra el backend.
  bool lastStateFromCache = false;

  static const String _openSyncType = 'cash.open';
  static const String _closeSyncType = 'cash.close';
  static const String _movementSyncType = 'cash.movement';
  static const String _pendingMovementsCacheKey = 'cash.pending.movements';
  static const String _activeSessionCacheKey = 'cash.active.session';
  static const String _turnHistoryCacheKey = 'cash.turn.history';

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;
    _syncQueue.registerHandler(_openSyncType, (payload) async {
      if ((payload['openedAt'] ?? '').toString().isEmpty ||
          (payload['offlineOpenPermit'] ?? '').toString().isEmpty) {
        throw const ObsoleteSyncOperationException(
          'Esta apertura antigua no contiene autorización y fecha comprobables. Conserva el turno y solicita revisión administrativa.',
        );
      }
      final session = await _openSessionRemote(
        openingAmount: _requiredReplayAmount(payload['openingAmount']),
        note: payload['note']?.toString(),
        clientSessionId: payload['clientSessionId']?.toString(),
        openedAt: payload['openedAt']?.toString(),
        offlineOpenPermit: payload['offlineOpenPermit']?.toString(),
        deviceFingerprint: payload['deviceFingerprint']?.toString(),
      );
      if ((payload['clientSessionId'] ?? '').toString().isEmpty ||
          session.shiftId != payload['clientSessionId']) {
        throw const ObsoleteSyncOperationException(
          'La apertura no coincide con el turno original. Conserva las operaciones dependientes para revisión.',
        );
      }
      lastStateFromCache = false;
      await _cache.writeMap(_activeSessionCacheKey, {
        'activeSession': _activeSessionToJson(session),
        'businessDate': session.businessDate,
        'canOperate': true,
      });
    });
    _syncQueue.registerHandler(_closeSyncType, (payload) async {
      final sessionId = (payload['sessionId'] ?? '').toString().trim();
      if (sessionId.isEmpty) {
        // Item antiguo/degradado sin identidad de turno. No existe forma segura
        // de saber a qué turno pertenece, así que NO se ejecuta: ejecutarlo
        // cerraría "el turno abierto actual" con un monto ajeno (incidente
        // Asadero). Se marca obsoleto y se descarta.
        TraceLog.log(
          'cash',
          'cash.close.replay.obsolete reason=missing_session_id',
        );
        throw const ObsoleteSyncOperationException(
          'Cierre de turno sin identificación: descartado por seguridad.',
        );
      }
      await _closeSessionRemote(
        sessionId: sessionId,
        closingAmount: _requiredReplayAmount(payload['closingAmount']),
        note: payload['note']?.toString(),
      );
      // Limpiar la caché SOLO si el turno cerrado coincide con el turno que la
      // caché tiene como activo. Si no coinciden, borraríamos el turno actual
      // (otro) y la UI mostraría caja cerrada por error.
      await _clearCachedSessionIfMatches(sessionId);
    });
    _syncQueue.registerHandler(_movementSyncType, (payload) async {
      final sessionId = (payload['sessionId'] ?? '').toString().trim();
      final occurredAt = (payload['occurredAt'] ?? payload['createdAt'] ?? '')
          .toString();
      if (occurredAt.isEmpty) {
        throw const ObsoleteSyncOperationException(
          'El movimiento no tiene fecha original comprobable. Se conserva para revisión.',
        );
      }
      if (sessionId.isEmpty) {
        TraceLog.log(
          'cash',
          'cash.movement.replay.obsolete reason=missing_session_id',
        );
        throw const ObsoleteSyncOperationException(
          'Movimiento de caja sin identificación de turno: descartado por seguridad.',
        );
      }
      final response = await _addMovementRemote(
        sessionId: sessionId,
        operationId: payload['operationId']?.toString(),
        type: payload['type'].toString(),
        amount: _requiredReplayAmount(payload['amount']),
        reason: payload['reason']?.toString() ?? '',
        movementType: payload['movementType']?.toString() ?? 'expense',
        affectsProfit: payload['affectsProfit'] as bool?,
        occurredAt: occurredAt,
      );
      _validateMovementResponse(response.data, payload);
      await _removePendingMovement(payload['id']?.toString() ?? '');
    });
  }

  double _requiredReplayAmount(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null || !amount.isFinite || amount < 0) {
      throw const ObsoleteSyncOperationException(
        'La operación no conserva un importe original válido. Se necesita revisión; no se enviará con un importe supuesto.',
      );
    }
    return amount;
  }

  void _validateMovementResponse(dynamic data, Map<String, dynamic> payload) {
    final expected = _asDouble(payload['amount']);
    final recorded = data is Map ? double.tryParse('${data['amount']}') : null;
    if (data is! Map ||
        data['id'] is! String ||
        (data['id'] as String).trim().isEmpty ||
        data['operationId'] != payload['operationId'] ||
        data['sessionId'] != payload['sessionId'] ||
        data['type'] != payload['type'] ||
        !expected.isFinite ||
        recorded == null ||
        !recorded.isFinite ||
        (recorded - expected).abs() > 0.005) {
      throw const ObsoleteSyncOperationException(
        'La confirmación del movimiento no coincide con la operación original. Se conserva para revisión.',
      );
    }
  }

  String _message(dynamic data, String fallback) {
    final operationMessage = customerOperationErrorMessage(data);
    if (operationMessage != null) return operationMessage;
    if (data is Map) {
      final message = data['message'];
      if (message is String &&
          message.trim().isNotEmpty &&
          !looksTechnical(message)) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && !looksTechnical(first)) return first;
      }
    }
    return fallback;
  }

  Future<CashGateState> state() => _withCurrentOwner(_state);

  Future<CashGateState> _state() async {
    TraceLog.log('cash', 'cash.fetch.start');
    try {
      final res = await _dio.get(
        ApiRoutes.cashState,
        options: Options(extra: const {'skipLoader': true}),
      );
      lastStateFromCache = false;
      final state = CashGateState.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      final rawState = (res.data as Map).cast<String, dynamic>();
      TraceLog.log(
        'cash',
        'cash.fetch.done active=${state.activeSession?.shiftId ?? 'null'}',
      );
      if (state.activeSession != null) {
        await _cache.writeMap(_activeSessionCacheKey, {
          'activeSession': _activeSessionToJson(state.activeSession!),
          'businessDate': state.businessDate,
          'canOperate': state.canOperate,
          'staleBusinessDate': state.staleBusinessDate,
          'requiresClosure': state.requiresClosure,
          'openingAmount': _openingAmountFromStatePayload(rawState),
        });
      } else {
        // Si el backend reporta que NO hay turno abierto, limpiamos el caché
        // local para no quedar con un "turno fantasma" que bloquee abrir/cerrar
        // caja cuando después haya una falla de red o error 5xx.
        await _cache.remove(_activeSessionCacheKey);
        await _cache.remove(_pendingMovementsCacheKey);
      }
      return state;
    } on DioException catch (e) {
      final reviewMessage = _requiresReviewMessage(e);
      if (reviewMessage != null) {
        // El servidor SÍ respondió: detectó un turno abierto ambiguo/legacy
        // (409 CASH_SESSION_REQUIRES_REVIEW). Esto NO es un fallo de red, así
        // que no se cae a caché ni se etiqueta como "sin conexión".
        TraceLog.log('cash', 'cash.fetch.requires_review');
        return CashGateState(
          businessDate: '',
          canOperate: false,
          activeSession: null,
          requiresReview: true,
          reviewMessage: reviewMessage,
        );
      }
      if (_shouldQueueNetworkFailure(e)) {
        final cached = await _cache.readMap(_activeSessionCacheKey);
        if (cached != null) {
          // Fallo de red transitorio: devolvemos el snapshot local, pero
          // marcado como NO verificado. La UI debe mostrarlo como
          // "estado no sincronizado", nunca como un turno confirmado.
          lastStateFromCache = true;
          TraceLog.log('cash', 'cash.cache_fallback');
          final gate = CashGateState.fromJson(cached);
          return CashGateState(
            businessDate: gate.businessDate,
            canOperate: gate.canOperate,
            activeSession: gate.activeSession,
            fromCache: true,
            pendingClose: gate.pendingClose,
            staleBusinessDate: gate.staleBusinessDate,
            requiresClosure: gate.requiresClosure,
          );
        }
      }
      throw ApiException(_message(e.response?.data, 'No se pudo cargar caja'));
    }
  }

  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) => _withCurrentOwner(
    () => _openSession(openingAmount: openingAmount, note: note),
  );

  Future<T> _withCurrentOwner<T>(Future<T> Function() body) =>
      UpdateCriticalOperationGate.instance.run(
        () => _withCurrentOwnerGuarded(body),
      );

  Future<T> _withCurrentOwnerGuarded<T>(Future<T> Function() body) async {
    Future<T> finish() async {
      final result = await body();
      await _assertCurrentOwner();
      return result;
    }

    if (OperationScope.current != null) return finish();
    final user = await _tokenStorage.getUserSnapshot();
    if (user == null || (user.companyId ?? '').isEmpty) return body();
    return OperationScope(user.companyId!, user.id).run(finish);
  }

  Future<PendingSyncAction?> _reserveCashAttempt(
    String type,
    String id,
    Map<String, dynamic> payload,
  ) async {
    if (kIsWeb) return null;
    final pinned = OperationScope.current;
    final active = await _syncQueue.captureScope();
    final companyId = pinned?.companyId ?? active?.companyId;
    final userId = pinned?.userId ?? active?.userId;
    if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) {
      throw ApiException(
        'Vuelve a iniciar sesión antes de registrar esta operación de caja.',
      );
    }
    final existing = await _offlineStore.listPendingActions(
      companyId: companyId,
      userId: userId,
      limit: null,
    );
    if (existing.any((action) => action.id == id)) {
      if (type == _closeSyncType &&
          existing.any(
            (action) => action.id == id && action.status != 'review_resolved',
          )) {
        throw const CashClosePendingSyncException(
          'Este cierre ya está guardado. Consulta su estado antes de repetirlo.',
        );
      }
      throw ApiException(
        'Ya existe una incidencia con esta referencia. Consulta su revisión antes de repetirla.',
      );
    }
    final now = DateTime.now().toUtc();
    final action = PendingSyncAction(
      id: id,
      type: type,
      scope: 'cash',
      companyId: companyId,
      userId: userId,
      idempotencyKey: (payload['operationId'] ?? id).toString(),
      entityId: (payload['sessionId'] ?? payload['clientSessionId'])
          ?.toString(),
      payload: payload,
      status: 'requires_action',
      permanent: true,
      attempts: 0,
      createdAt: now,
      updatedAt: now,
      error:
          'El resultado de esta operación todavía no está comprobado. Consulta el turno original antes de repetirla.',
    );
    await _offlineStore.putPendingAction(action, requireDatabase: true);
    await _syncQueue.refreshStats();
    return action;
  }

  Future<void> _finishCashAttempt(PendingSyncAction? action) async {
    if (action == null) return;
    await _offlineStore.removePendingAction(action.id);
    await _syncQueue.refreshStats();
  }

  Future<void> _assertCurrentOwner() async {
    final original = OperationScope.current;
    if (original == null) return;
    final current = await _syncQueue.captureScope();
    if (current?.companyId != original.companyId ||
        current?.userId != original.userId) {
      throw ApiException(
        'La sesión cambió durante la operación. Consulta el historial o el Centro de recuperación de la cuenta original antes de repetirla.',
      );
    }
  }

  Future<ActiveCashSession> _openSession({
    required double openingAmount,
    String? note,
  }) async {
    if (await _hasPendingClose()) {
      throw ApiException(
        'Hay un cierre de turno pendiente de sincronizar. Espera a que se confirme antes de abrir otro turno.',
      );
    }
    // Identidad generada por el cliente para el turno que se está abriendo.
    // Permite que un turno abierto OFFLINE tenga una identidad real (UUID) que
    // el cierre offline pueda referenciar, y hace la apertura idempotente si el
    // servidor la creó pero la respuesta se perdió.
    final clientSessionId = _newSessionUuid();
    final deviceOpenedAt = DateTime.now().toUtc();
    final actor = await _tokenStorage.getUserSnapshot();
    final owner = OperationScope.current;
    final activeOwner = await _syncQueue.captureScope();
    final companyId =
        owner?.companyId ?? activeOwner?.companyId ?? actor?.companyId ?? '';
    final userId = owner?.userId ?? activeOwner?.userId ?? actor?.id ?? '';
    final headers = await ClientTelemetryHeaders.instance.headers();
    final device = headers['x-client-device-id'] ?? '';
    final authorization = await OfflineEmergencyPolicy()
        .cashOpeningAuthorization(
          companyId: companyId,
          userId: userId,
          deviceFingerprint: device,
          deviceOpenedAt: deviceOpenedAt,
        );
    final permit = authorization?.permit;
    final openedAt = authorization?.openedAt ?? deviceOpenedAt;
    final attempt = await _reserveCashAttempt(
      _openSyncType,
      '$_openSyncType:$clientSessionId',
      {
        'clientSessionId': clientSessionId,
        'openingAmount': openingAmount,
        'openedAt': openedAt.toIso8601String(),
        if (permit != null) 'offlineOpenPermit': permit,
        'deviceFingerprint': device,
        if (note != null) 'note': note,
      },
    );
    try {
      final session = await _openSessionRemote(
        openingAmount: openingAmount,
        note: note,
        clientSessionId: clientSessionId,
        openedAt: permit == null ? null : openedAt.toIso8601String(),
        offlineOpenPermit: permit,
        deviceFingerprint: permit == null ? null : device,
      );
      lastStateFromCache = false;
      await _cache.writeMap(_activeSessionCacheKey, {
        'activeSession': _activeSessionToJson(session),
        'businessDate': session.businessDate,
        'canOperate': true,
        'openingAmount': openingAmount,
      });
      await _finishCashAttempt(attempt);
      await _assertCurrentOwner();
      return session;
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        if (attempt != null) await _syncQueue.retainFailedAttempt(attempt, e);
        await _assertCurrentOwner();
        throw ApiException(_message(e.response?.data, 'No se pudo abrir caja'));
      }
      await _assertCurrentOwner();
      if (permit == null) {
        // An interrupted POST could already have opened the server shift. Keep
        // its identity even when this device has no reconstructible permit.
        final now = DateTime.now().toUtc();
        await _offlineStore.putPendingAction(
          PendingSyncAction(
            id: '$_openSyncType:$clientSessionId',
            type: _openSyncType,
            scope: 'cash',
            companyId: companyId,
            userId: userId,
            entityId: clientSessionId,
            idempotencyKey: '$_openSyncType:$clientSessionId',
            payload: {
              'openingAmount': openingAmount,
              'clientSessionId': clientSessionId,
              'openedAt': openedAt.toIso8601String(),
              'deviceFingerprint': device,
            },
            status: 'requires_action',
            permanent: true,
            attempts: 1,
            createdAt: now,
            updatedAt: now,
            error:
                'No se pudo comprobar la autorización de esta apertura. Revisa su resultado antes de repetirla.',
          ),
          requireDatabase: true,
        );
        await _syncQueue.refreshStats();
        throw ApiException(
          'No podemos confirmar esta apertura sin conexión. Quedó guardada para revisión. Conecta el equipo antes de abrir otro turno.',
        );
      }
      final local = ActiveCashSession(
        userId: userId,
        shiftId: clientSessionId,
        openedAt: openedAt,
        status: 'OPEN',
        userName: 'Caja offline',
        businessDate: businessDateKey(openedAt),
      );
      final cachedSession = {
        'activeSession': _activeSessionToJson(local),
        'businessDate': local.businessDate,
        'canOperate': true,
        'openingAmount': openingAmount,
        'fromCache': true,
      };
      lastStateFromCache = true;
      await _syncQueue.enqueue(
        id: '$_openSyncType:$clientSessionId',
        type: _openSyncType,
        scope: 'cash',
        entityType: 'cash_session',
        entityId: clientSessionId,
        idempotencyKey: '$_openSyncType:$clientSessionId',
        requireDatabase: true,
        createdAt: attempt?.createdAt ?? openedAt,
        cacheKey: await _cache.storageKeyFor(_activeSessionCacheKey),
        cachePayload: cachedSession,
        payload: {
          'openingAmount': openingAmount,
          'note': note,
          'clientSessionId': clientSessionId,
          'openedAt': openedAt.toIso8601String(),
          'offlineOpenPermit': permit,
          'deviceFingerprint': device,
        },
      );
      return local;
    }
  }

  Future<ActiveCashSession> _openSessionRemote({
    required double openingAmount,
    String? note,
    String? clientSessionId,
    String? openedAt,
    String? offlineOpenPermit,
    String? deviceFingerprint,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.cashOpenSession,
        data: {
          'openingAmount': openingAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
          if ((clientSessionId ?? '').trim().isNotEmpty)
            'clientSessionId': clientSessionId!.trim(),
          if (openedAt != null) 'openedAt': openedAt,
          if (offlineOpenPermit != null) 'offlineOpenPermit': offlineOpenPermit,
          if (deviceFingerprint != null) 'deviceFingerprint': deviceFingerprint,
        },
      );
      final data = res.data;
      final recorded = data is Map
          ? double.tryParse('${data['openingAmount']}')
          : null;
      if (data is! Map ||
          data['shiftId'] != clientSessionId ||
          data['status'] != 'OPEN' ||
          recorded == null ||
          !recorded.isFinite ||
          !openingAmount.isFinite ||
          (recorded - openingAmount).abs() > 0.005) {
        throw const ObsoleteSyncOperationException(
          'La apertura no tiene una confirmación coincidente de turno e importe. Conserva la incidencia para revisión.',
        );
      }
      return ActiveCashSession.fromJson(data.cast<String, dynamic>());
    } on DioException {
      rethrow;
    }
  }

  /// Cierra el turno identificado por [sessionId].
  ///
  /// [sessionId] es OBLIGATORIO: es la identidad del turno que estaba abierto
  /// cuando el usuario inició el cierre. Nunca se calcula "el turno actual"
  /// durante un replay, de modo que un cierre offline antiguo jamás puede
  /// cerrar un turno posterior.
  Future<void> closeSession({
    required double closingAmount,
    required String sessionId,
    String? note,
  }) => _withCurrentOwner(
    () => _closeSession(
      closingAmount: closingAmount,
      sessionId: sessionId,
      note: note,
    ),
  );

  Future<void> _closeSession({
    required double closingAmount,
    required String sessionId,
    String? note,
  }) async {
    final resolvedSessionId = sessionId.trim();
    if (resolvedSessionId.isEmpty) {
      // Sin identidad de turno no se puede cerrar de forma segura.
      throw ApiException(
        'No pudimos comprobar qué turno se debe cerrar. Pide al encargado que revise la caja antes de intentar otro cierre.',
      );
    }
    final attempt = await _reserveCashAttempt(
      _closeSyncType,
      '$_closeSyncType:$resolvedSessionId',
      {
        'sessionId': resolvedSessionId,
        'closingAmount': closingAmount,
        if (note != null) 'note': note,
      },
    );
    try {
      final closedId = await _closeSessionRemote(
        sessionId: resolvedSessionId,
        closingAmount: closingAmount,
        note: note,
      );
      lastStateFromCache = false;
      if (closedId != resolvedSessionId) {
        TraceLog.log(
          'cash',
          'cash.close.mismatch requested=$resolvedSessionId closed=$closedId',
        );
      }
      await _clearCachedSessionIfMatches(resolvedSessionId);
      await _finishCashAttempt(attempt);
    } on ObsoleteSyncOperationException {
      await _retainUncertainClose(
        resolvedSessionId,
        closingAmount,
        note,
        original: attempt,
      );
      throw const CashClosePendingSyncException(
        'No se pudo confirmar el cierre. Quedó guardado para revisión del turno original.',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 409) {
        await _retainUncertainClose(
          resolvedSessionId,
          closingAmount,
          note,
          original: attempt,
        );
        throw const CashClosePendingSyncException(
          'El servidor rechazó este cierre. La incidencia sigue guardada para revisión del turno original.',
        );
      }
      if (!_shouldQueueNetworkFailure(e)) {
        if (attempt != null) await _syncQueue.retainFailedAttempt(attempt, e);
        await _assertCurrentOwner();
        throw ApiException(
          _message(e.response?.data, 'No se pudo cerrar turno'),
        );
      }
      // Fallo de red transitorio: se encola el cierre CON la identidad del turno
      // original. El item es único por turno (id determinista), de modo que un
      // reintento/doble clic no duplica la operación.
      await _syncQueue.enqueue(
        id: '$_closeSyncType:$resolvedSessionId',
        type: _closeSyncType,
        scope: 'cash',
        entityType: 'cash_session',
        entityId: resolvedSessionId,
        idempotencyKey: '$_closeSyncType:$resolvedSessionId',
        createdAt: attempt?.createdAt,
        requireDatabase: true,
        payload: {
          'sessionId': resolvedSessionId,
          'closingAmount': closingAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        },
      );
      await _markCachedSessionPendingClose(resolvedSessionId);
      throw const CashClosePendingSyncException(
        'El cierre quedó pendiente de sincronizar.',
      );
    }
  }

  Future<void> _retainUncertainClose(
    String sessionId,
    double amount,
    String? note, {
    PendingSyncAction? original,
  }) async {
    if (original != null) {
      await _offlineStore.updatePendingAction(
        original.copyWith(
          status: 'requires_action',
          permanent: true,
          updatedAt: DateTime.now().toUtc(),
          error:
              'El cierre no está confirmado. Revisa el turno original y el importe con el encargado.',
        ),
      );
      await _markCachedSessionPendingClose(sessionId);
      await _syncQueue.refreshStats();
      return;
    }
    final user = await _tokenStorage.getUserSnapshot();
    if (user == null || (user.companyId ?? '').isEmpty) {
      throw StateError(
        'No se pudo guardar la incidencia del cierre. Conserva esta pantalla y solicita revisión.',
      );
    }
    final now = DateTime.now().toUtc();
    await _offlineStore.putPendingAction(
      PendingSyncAction(
        id: '$_closeSyncType:$sessionId',
        type: _closeSyncType,
        scope: 'cash',
        companyId: OperationScope.current?.companyId ?? user.companyId,
        userId: OperationScope.current?.userId ?? user.id,
        entityId: sessionId,
        idempotencyKey: '$_closeSyncType:$sessionId',
        payload: {
          'sessionId': sessionId,
          'closingAmount': amount,
          if (note != null) 'note': note,
        },
        status: 'requires_action',
        permanent: true,
        attempts: 1,
        createdAt: now,
        updatedAt: now,
        error:
            'El cierre no está confirmado. Revisa el turno original y el importe con el encargado.',
      ),
      requireDatabase: true,
    );
    await _markCachedSessionPendingClose(sessionId);
    await _syncQueue.refreshStats();
  }

  Future<String> _closeSessionRemote({
    required String sessionId,
    required double closingAmount,
    String? note,
  }) async {
    final res = await _dio.post(
      ApiRoutes.cashCloseSession,
      data: {
        'sessionId': sessionId,
        'closingAmount': closingAmount,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    final data = res.data;
    if (data is Map) {
      final session = data['session'];
      if (session is Map) {
        final id = session['id']?.toString().trim();
        final recorded = double.tryParse('${session['closingAmount']}');
        if (id == sessionId &&
            session['status'] == 'CLOSED' &&
            recorded != null &&
            recorded.isFinite &&
            closingAmount.isFinite &&
            (recorded - closingAmount).abs() <= 0.005) {
          return id!;
        }
      }
    }
    throw const ObsoleteSyncOperationException(
      'No pudimos comprobar la identidad y el importe del cierre. Se requiere revisión antes de confirmarlo.',
    );
  }

  Future<CashSummaryModel> summary() => _withCurrentOwner(_summary);

  Future<CashSummaryModel> _summary() async {
    if (_offlineCircuitState?.isOfflineFastFailActive == true) {
      final local = await _localSummaryFromCache();
      if (local != null) return local;
    }
    try {
      final res = await _dio.get(
        ApiRoutes.cashSummary,
        options: Options(
          extra: const {'skipLoader': true, 'disableOfflineCache': true},
        ),
      );
      final summary = CashSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      return await _mergePendingMovementsIntoSummary(summary);
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        final local = await _localSummaryFromCache();
        if (local != null) return local;
      }
      final status = e.response?.statusCode;
      if (status == 404) {
        // `GET /cash/summary` exige un turno abierto (`requireOpenSession`). Un
        // 404 aquí es un ESTADO DE NEGOCIO ("no hay turno abierto"), no un
        // fallo técnico: los llamadores deben informar y revalidar, nunca
        // escalarlo al sistema global de errores.
        TraceLog.log('cash', 'cash.summary.no_open_session');
      }
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar corte'),
        status,
      );
    }
  }

  Future<CashSummaryModel?> cachedSummary() => _localSummaryFromCache();

  Future<List<CashMovementModel>> movements() => _withCurrentOwner(_movements);

  Future<List<CashMovementModel>> _movements() async {
    try {
      final res = await _dio.get(
        ApiRoutes.cashMovements,
        options: Options(extra: const {'skipLoader': true}),
      );
      final rows = _extractRows(res.data);
      final remote = rows
          .whereType<Map>()
          .map((row) => CashMovementModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
      return [...await _pendingMovementModels(), ...remote];
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) return _pendingMovementModels();
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar movimientos'),
      );
    }
  }

  Future<List<CashMovementModel>> movementHistory({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int take = 160,
  }) async {
    final page = await movementHistoryPage(
      type: type,
      movementType: movementType,
      from: from,
      to: to,
      limit: take,
    );
    return page.items;
  }

  Future<CashPage<CashMovementModel>> movementHistoryPage({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    if (_offlineCircuitState?.isOfflineFastFailActive == true) {
      return _localMovementHistoryPage(
        type: type,
        movementType: movementType,
        from: from,
        to: to,
        search: search,
        page: page,
        limit: limit,
      );
    }
    try {
      final res = await _dio.get(
        ApiRoutes.cashMovementsHistory,
        queryParameters: {
          if ((type ?? '').trim().isNotEmpty) 'type': type!.trim(),
          if ((movementType ?? '').trim().isNotEmpty)
            'movementType': movementType!.trim(),
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
          'page': page,
          'limit': limit,
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      return CashPage<CashMovementModel>.fromJson(
        res.data,
        CashMovementModel.fromJson,
      );
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        return _localMovementHistoryPage(
          type: type,
          movementType: movementType,
          from: from,
          to: to,
          search: search,
          page: page,
          limit: limit,
        );
      }
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar historial de caja'),
      );
    }
  }

  String _dateOnly(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<List<CashSessionHistoryModel>> closedSessions() async {
    final page = await closedSessionsPage();
    return page.items;
  }

  Future<CashPage<CashSessionHistoryModel>> closedSessionsPage({
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    if (_offlineCircuitState?.isOfflineFastFailActive == true) {
      return _localTurnHistoryPage(
        from: from,
        to: to,
        search: search,
        page: page,
        limit: limit,
      );
    }
    try {
      final res = await _dio.get(
        ApiRoutes.cashClosedSessions,
        queryParameters: {
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
          'page': page,
          'limit': limit,
        },
        options: Options(
          extra: const {'skipLoader': true, 'disableOfflineCache': true},
        ),
      );
      final parsed = CashPage<CashSessionHistoryModel>.fromJson(
        res.data,
        CashSessionHistoryModel.fromJson,
      );
      if (page == 1 &&
          (from == null && to == null && (search ?? '').trim().isEmpty)) {
        await _cache.writeMap(_turnHistoryCacheKey, {
          'items': parsed.items.map(_historyToJson).toList(growable: false),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return parsed;
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        return _localTurnHistoryPage(
          from: from,
          to: to,
          search: search,
          page: page,
          limit: limit,
        );
      }
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar historial de turnos'),
      );
    }
  }

  List<dynamic> _extractRows(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }

  Future<CashSessionDetailModel> sessionDetail(String id) async {
    if (_offlineCircuitState?.isOfflineFastFailActive == true) {
      final local = await _localSessionDetail(id);
      if (local != null) return local;
    }
    try {
      final res = await _dio.get(
        ApiRoutes.cashSessionDetail(id),
        options: Options(extra: const {'skipLoader': true}),
      );
      final data = res.data is Map
          ? res.data as Map
          : const <String, dynamic>{};
      return CashSessionDetailModel.fromJson(data.cast<String, dynamic>());
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        final local = await _localSessionDetail(id);
        if (local != null) return local;
      }
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar el detalle del turno'),
      );
    }
  }

  Future<ActiveCashSession?> cachedActiveSession() async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    final active = cached?['activeSession'];
    if (active is Map) {
      return ActiveCashSession.fromJson(active.cast<String, dynamic>());
    }
    return null;
  }

  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
    String movementType = 'expense',
    bool? affectsProfit,
  }) => _withCurrentOwner(
    () => _addMovement(
      type: type,
      amount: amount,
      reason: reason,
      sessionId: sessionId,
      movementType: movementType,
      affectsProfit: affectsProfit,
    ),
  );

  Future<void> _addMovement({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    var resolvedSessionId = (sessionId ?? '').trim();
    if (resolvedSessionId.isEmpty) {
      final cached = await cachedActiveSession();
      final actor =
          OperationScope.current?.userId ??
          (await _syncQueue.captureScope())?.userId;
      if (cached != null && cached.userId == actor) {
        resolvedSessionId = cached.shiftId;
      }
    }
    if (resolvedSessionId.isEmpty) {
      throw ApiException(
        'No pudimos comprobar el turno original. Abre o verifica tu turno antes de registrar el movimiento.',
      );
    }
    final localId = 'local_cash_${DateTime.now().microsecondsSinceEpoch}';
    final operationId = 'cash.movement:$localId';
    // Fecha REAL de la operación: el servidor la usa para validar que el
    // movimiento pertenece a la vida del turno y no a un día posterior, sin
    // depender del momento de sincronización (offline).
    final occurredAt = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'id': localId,
      'operationId': operationId,
      'sessionId': resolvedSessionId,
      'type': type,
      'amount': amount,
      'reason': reason,
      'movementType': movementType,
      if (affectsProfit != null) 'affectsProfit': affectsProfit,
      'occurredAt': occurredAt,
      'createdAt': occurredAt,
    };
    final attempt = await _reserveCashAttempt(
      _movementSyncType,
      '$_movementSyncType:$localId',
      payload,
    );
    try {
      final response = await _addMovementRemote(
        type: type,
        amount: amount,
        reason: reason,
        sessionId: resolvedSessionId.isEmpty ? null : resolvedSessionId,
        operationId: operationId,
        movementType: movementType,
        affectsProfit: affectsProfit,
        occurredAt: occurredAt,
      );
      _validateMovementResponse(response.data, payload);
      await _finishCashAttempt(attempt);
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        if (attempt != null) await _syncQueue.retainFailedAttempt(attempt, e);
        await _assertCurrentOwner();
        throw ApiException(
          _message(e.response?.data, 'No se pudo guardar movimiento'),
        );
      }
      if (resolvedSessionId.isEmpty) {
        // Sin identidad de turno no se puede garantizar el destino del
        // movimiento: no se encola (evita aplicarlo a un turno posterior).
        throw ApiException(
          'No pudimos comprobar a qué turno pertenece el movimiento. Pide al encargado que revise la caja antes de registrarlo de nuevo.',
        );
      }
      final cached = await _cache.readMap(_pendingMovementsCacheKey);
      await _syncQueue.enqueue(
        id: '$_movementSyncType:$localId',
        type: _movementSyncType,
        scope: 'cash',
        entityType: 'cash_session',
        entityId: resolvedSessionId,
        idempotencyKey: operationId,
        payload: payload,
        createdAt: attempt?.createdAt,
        requireDatabase: true,
        cacheKey: await _cache.storageKeyFor(_pendingMovementsCacheKey),
        cachePayload: {
          'items': [...((cached?['items'] as List?) ?? const []), payload],
        },
      );
    }
  }

  Future<Response<dynamic>> _addMovementRemote({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
    String? operationId,
    String movementType = 'expense',
    bool? affectsProfit,
    String? occurredAt,
  }) {
    return _dio.post(
      ApiRoutes.cashMovements,
      data: {
        if ((operationId ?? '').trim().isNotEmpty)
          'operationId': operationId!.trim(),
        'type': type,
        'amount': amount,
        'reason': reason,
        if ((sessionId ?? '').trim().isNotEmpty) 'sessionId': sessionId!.trim(),
        'movementType': movementType,
        if (affectsProfit != null) 'affectsProfit': affectsProfit,
        if ((occurredAt ?? '').trim().isNotEmpty)
          'occurredAt': occurredAt!.trim(),
      },
    );
  }

  String? _cachedSessionId(Map<String, dynamic>? cached) {
    final active = cached?['activeSession'];
    if (active is Map) {
      final id = (active['shiftId'] ?? active['id'])?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Elimina la caché del turno activo SOLO cuando corresponde al turno
  /// [sessionId] (o cuando no hay caché). Evita borrar el turno actual por
  /// error si un replay cierra un turno distinto.
  Future<void> _clearCachedSessionIfMatches(String sessionId) async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    final cachedId = _cachedSessionId(cached);
    if (cachedId == null || cachedId == sessionId) {
      await _cache.remove(_activeSessionCacheKey);
      await _cache.remove(_pendingMovementsCacheKey);
    } else {
      TraceLog.log(
        'cash',
        'cash.cache_preserved active=$cachedId closed=$sessionId',
      );
    }
  }

  Future<bool> _hasPendingClose() async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    return cached?['pendingClose'] == true;
  }

  Future<void> _markCachedSessionPendingClose(String sessionId) async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    final cachedId = _cachedSessionId(cached);
    if (cached == null || cachedId != sessionId) return;
    await _cache.writeMap(_activeSessionCacheKey, {
      ...cached,
      'pendingClose': true,
      'canOperate': false,
      'fromCache': true,
    });
  }

  bool _shouldQueueNetworkFailure(DioException error) {
    final status = error.response?.statusCode;
    return status == null || status >= 500;
  }

  /// Devuelve el mensaje cuando el backend rechazó el estado de caja con
  /// 409 `CASH_SESSION_REQUIRES_REVIEW` (turno legacy/ambiguo). Si no aplica,
  /// retorna `null`.
  static String? _requiresReviewMessage(DioException error) {
    if (error.response?.statusCode != 409) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = (data['errorCode'] ?? data['code'])?.toString();
    if (code != 'CASH_SESSION_REQUIRES_REVIEW') return null;
    final message = data['message']?.toString().trim() ?? '';
    return message.isEmpty
        ? 'Este turno abierto necesita revisión antes de operar. Contacta a un administrador.'
        : message;
  }

  Future<void> _removePendingMovement(String id) async {
    if (id.trim().isEmpty) return;
    final cached = await _cache.readMap(_pendingMovementsCacheKey);
    final rows = ((cached?['items'] as List?) ?? const [])
        .where((item) => item is! Map || item['id']?.toString() != id)
        .toList(growable: false);
    await _cache.writeMap(_pendingMovementsCacheKey, {'items': rows});
  }

  Future<List<CashMovementModel>> _pendingMovementModels() async {
    final cached = await _cache.readMap(_pendingMovementsCacheKey);
    final rows = (cached?['items'] as List?) ?? const [];
    if (rows.isEmpty) return const [];
    final user = await _tokenStorage.getUserSnapshot();
    final companyId = OperationScope.current?.companyId ?? user?.companyId;
    final userId = OperationScope.current?.userId ?? user?.id;
    final reviewed = (companyId ?? '').isEmpty || (userId ?? '').isEmpty
        ? <String>{}
        : await _offlineStore.reviewedFinancialOperationIds(
            companyId: companyId!,
            userId: userId!,
            type: _movementSyncType,
          );
    return rows
        .whereType<Map>()
        .where((row) => !reviewed.contains(row['operationId']?.toString()))
        .map((row) {
          final json = row.cast<String, dynamic>();
          return CashMovementModel.fromJson({
            'id': json['id'],
            'sessionId': 'offline',
            'type': json['type'],
            'amount': json['amount'],
            'reason': json['reason'],
            'movementType': json['movementType'],
            'affectsProfit': json['affectsProfit'] ?? true,
            'createdAt': json['createdAt'],
          });
        })
        .toList(growable: false);
  }

  Future<CashSummaryModel> _mergePendingMovementsIntoSummary(
    CashSummaryModel summary,
  ) async {
    final pending = await _pendingMovementModels();
    if (pending.isEmpty) return summary;

    var cashIn = summary.cashInManual;
    var cashOut = summary.cashOutManual;
    var expenses = summary.totalExpenses;
    var withdrawals = summary.totalWithdrawals;
    for (final movement in pending) {
      if (movement.isIn) {
        cashIn += movement.amount;
      } else {
        cashOut += movement.amount;
        if (movement.movementType == 'expense' && movement.affectsProfit) {
          expenses += movement.amount;
        } else {
          withdrawals += movement.amount;
        }
      }
    }
    return CashSummaryModel(
      openingAmount: summary.openingAmount,
      totalSales: summary.totalSales,
      totalExpenses: expenses,
      totalWithdrawals: withdrawals,
      cashInManual: cashIn,
      cashOutManual: cashOut,
      creditAbonos: summary.creditAbonos,
      creditSalesTotal: summary.creditSalesTotal,
      creditInitialCash: summary.creditInitialCash,
      creditInitialTransfer: summary.creditInitialTransfer,
      creditBalanceTotal: summary.creditBalanceTotal,
      creditPaymentCash: summary.creditPaymentCash,
      creditPaymentTransfer: summary.creditPaymentTransfer,
      salesCashTotal: summary.salesCashTotal,
      salesTransferTotal: summary.salesTransferTotal,
      refundsCash: summary.refundsCash,
      // Misma fórmula que el backend (`buildSummaryForSession`): el efectivo
      // recibido al crear las ventas y los abonos de crédito cobrados en el
      // turno son carriles distintos que se suman UNA sola vez.
      expectedCash:
          summary.openingAmount +
          summary.salesCashTotal +
          summary.creditPaymentCash -
          summary.refundsCash +
          cashIn -
          cashOut,
      totalTickets: summary.totalTickets,
      totalRefunds: summary.totalRefunds,
      categorySummary: summary.categorySummary,
    );
  }

  Future<CashSummaryModel?> _localSummaryFromCache() async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    if (cached == null || cached['activeSession'] is! Map) return null;
    final openingAmount = _asDouble(cached['openingAmount']);
    final sessionId = _cachedSessionId(cached);
    var summary = CashSummaryModel(
      openingAmount: openingAmount,
      totalSales: 0,
      totalExpenses: 0,
      totalWithdrawals: 0,
      cashInManual: 0,
      cashOutManual: 0,
      creditAbonos: 0,
      creditSalesTotal: 0,
      creditInitialCash: 0,
      creditInitialTransfer: 0,
      creditBalanceTotal: 0,
      creditPaymentCash: 0,
      creditPaymentTransfer: 0,
      salesCashTotal: 0,
      salesTransferTotal: 0,
      refundsCash: 0,
      expectedCash: openingAmount,
      totalTickets: 0,
      totalRefunds: 0,
      categorySummary: const [],
    );
    if ((sessionId ?? '').isNotEmpty) {
      summary = await _mergeOfflineSalesIntoSummary(summary, sessionId!);
    }
    return _mergePendingMovementsIntoSummary(summary);
  }

  Future<CashPage<CashSessionHistoryModel>> _localTurnHistoryPage({
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    final cachedRows = await _cachedHistoryRows();
    final activeRow = await _activeSessionHistoryRow();
    final byId = <String, CashSessionHistoryModel>{
      for (final row in cachedRows) row.id: row,
      if (activeRow != null) activeRow.id: activeRow,
    };
    var rows = byId.values.toList(growable: false)
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    rows = rows
        .where((row) {
          if (from != null || to != null) {
            final day = DateTime(
              row.openedAt.year,
              row.openedAt.month,
              row.openedAt.day,
            );
            if (from != null) {
              final start = DateTime(from.year, from.month, from.day);
              if (day.isBefore(start)) return false;
            }
            if (to != null) {
              final end = DateTime(to.year, to.month, to.day);
              if (day.isAfter(end)) return false;
            }
          }
          final query = (search ?? '').trim().toLowerCase();
          if (query.isEmpty) return true;
          return [
            row.id,
            row.userName,
            row.businessDate,
            row.status,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);

    final safeLimit = limit <= 0 ? 50 : limit;
    final safePage = page <= 0 ? 1 : page;
    final start = (safePage - 1) * safeLimit;
    final items = start >= rows.length
        ? const <CashSessionHistoryModel>[]
        : rows.skip(start).take(safeLimit).toList(growable: false);
    final hasMore = start + items.length < rows.length;
    return CashPage<CashSessionHistoryModel>(
      items: items,
      page: safePage,
      limit: safeLimit,
      total: rows.length,
      hasMore: hasMore,
      nextPage: hasMore ? safePage + 1 : null,
    );
  }

  Future<CashPage<CashMovementModel>> _localMovementHistoryPage({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    var rows = await _pendingMovementModels();
    rows =
        rows
            .where((movement) {
              final normalizedType = (type ?? '').trim().toLowerCase();
              if (normalizedType.isNotEmpty &&
                  movement.type.trim().toLowerCase() != normalizedType) {
                return false;
              }

              final normalizedMovementType = (movementType ?? '')
                  .trim()
                  .toLowerCase();
              if (normalizedMovementType.isNotEmpty &&
                  movement.movementType.trim().toLowerCase() !=
                      normalizedMovementType) {
                return false;
              }

              if (from != null || to != null) {
                final day = DateTime(
                  movement.createdAt.year,
                  movement.createdAt.month,
                  movement.createdAt.day,
                );
                if (from != null) {
                  final start = DateTime(from.year, from.month, from.day);
                  if (day.isBefore(start)) return false;
                }
                if (to != null) {
                  final end = DateTime(to.year, to.month, to.day);
                  if (day.isAfter(end)) return false;
                }
              }

              final query = (search ?? '').trim().toLowerCase();
              if (query.isEmpty) return true;
              return [
                movement.id,
                movement.reason,
                movement.type,
                movement.movementType,
                movement.amount.toStringAsFixed(2),
              ].join(' ').toLowerCase().contains(query);
            })
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final safeLimit = limit <= 0 ? 50 : limit;
    final safePage = page <= 0 ? 1 : page;
    final start = (safePage - 1) * safeLimit;
    final items = start >= rows.length
        ? const <CashMovementModel>[]
        : rows.skip(start).take(safeLimit).toList(growable: false);
    final hasMore = start + items.length < rows.length;
    return CashPage<CashMovementModel>(
      items: items,
      page: safePage,
      limit: safeLimit,
      total: rows.length,
      hasMore: hasMore,
      nextPage: hasMore ? safePage + 1 : null,
    );
  }

  Future<List<CashSessionHistoryModel>> _cachedHistoryRows() async {
    final cached = await _cache.readMap(_turnHistoryCacheKey);
    final items = cached?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (row) =>
              CashSessionHistoryModel.fromJson(row.cast<String, dynamic>()),
        )
        .where((row) => row.id.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<CashSessionHistoryModel?> _activeSessionHistoryRow() async {
    final cached = await _cache.readMap(_activeSessionCacheKey);
    final active = cached?['activeSession'];
    if (active is! Map) return null;
    final session = ActiveCashSession.fromJson(active.cast<String, dynamic>());
    if (session.shiftId.trim().isEmpty) return null;
    final summary = await _localSummaryFromCache();
    final expected =
        summary?.expectedCash ?? _asDouble(cached?['openingAmount']);
    return CashSessionHistoryModel(
      id: session.shiftId,
      userName: session.userName,
      businessDate: session.businessDate,
      openedAt: session.openedAt,
      closedAt: null,
      initialAmount:
          summary?.openingAmount ?? _asDouble(cached?['openingAmount']),
      closingAmount: 0,
      expectedAmount: expected,
      difference: 0,
      status: cached?['pendingClose'] == true ? 'Pendiente' : 'OPEN',
    );
  }

  Future<CashSessionDetailModel?> _localSessionDetail(String id) async {
    final row = await _activeSessionHistoryRow();
    if (row == null || row.id != id) return null;
    final summary = await _localSummaryFromCache();
    if (summary == null) return null;
    return CashSessionDetailModel(
      id: row.id,
      userName: row.userName,
      businessDate: row.businessDate,
      openedAt: row.openedAt,
      closedAt: row.closedAt,
      initialAmount: row.initialAmount,
      closingAmount: row.closingAmount,
      expectedAmount: row.expectedAmount,
      difference: row.difference,
      status: row.status,
      note: 'Datos locales pendientes de sincronizar.',
      summary: summary,
      movements: await _pendingMovementModels(),
    );
  }

  Map<String, dynamic> _historyToJson(CashSessionHistoryModel row) {
    return {
      'id': row.id,
      'userName': row.userName,
      'businessDate': row.businessDate,
      'openedAt': row.openedAt.toUtc().toIso8601String(),
      'closedAt': row.closedAt?.toUtc().toIso8601String(),
      'initialAmount': row.initialAmount,
      'closingAmount': row.closingAmount,
      'expectedAmount': row.expectedAmount,
      'difference': row.difference,
      'status': row.status,
    };
  }

  double _openingAmountFromStatePayload(Map<String, dynamic> data) {
    final userOpenShift = data['userOpenShift'];
    if (userOpenShift is Map) {
      final amount = _asDouble(
        userOpenShift['initialAmount'] ?? userOpenShift['openingAmount'],
      );
      if (amount != 0) return amount;
    }
    final activeSession = data['activeSession'];
    if (activeSession is Map) {
      return _asDouble(
        activeSession['initialAmount'] ?? activeSession['openingAmount'],
      );
    }
    return 0;
  }

  Future<CashSummaryModel> _mergeOfflineSalesIntoSummary(
    CashSummaryModel summary,
    String sessionId,
  ) async {
    final user = await _tokenStorage.getUserSnapshot();
    final companyId = user?.companyId?.trim() ?? '';
    final userId = user?.id.trim() ?? '';
    if (companyId.isEmpty || userId.isEmpty) return summary;

    final rows = await _offlineStore.listOfflineSales(
      companyId: companyId,
      userId: userId,
      limit: 1000,
    );
    if (rows.isEmpty) return summary;

    final reviewed = await _offlineStore.reviewedFinancialOperationIds(
      companyId: companyId,
      userId: userId,
      type: 'sales.create',
    );

    var totalSales = summary.totalSales;
    var salesCash = summary.salesCashTotal;
    var salesTransfer = summary.salesTransferTotal;
    var tickets = summary.totalTickets;

    for (final row in rows) {
      if (reviewed.contains(row['clientRequestId']?.toString())) continue;
      final status = row['status']?.toString().trim().toLowerCase() ?? '';
      if (status == 'synced') continue;

      final payload = (row['payload'] is Map)
          ? (row['payload'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final originSessionId = (payload['originCashSessionId'] ?? '')
          .toString()
          .trim();
      if (originSessionId != sessionId) continue;

      final aggregate = await _offlineStore.getOfflineSaleAggregate(
        companyId: companyId,
        localSaleId: row['localId']?.toString() ?? '',
      );
      final payment = _firstPaymentPayload(aggregate) ?? payload;
      final method =
          (payment['paymentMethod'] ?? payload['paymentMethod'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      final totalSold = _firstPositiveDouble([
        row['totalSold'],
        payload['expectedTotalSold'],
        payment['totalSold'],
      ]);
      final rawCashAmount = _firstPositiveDouble([
        payment['paymentCashAmount'],
        payload['paymentCashAmount'],
      ]);
      final cashAmount =
          rawCashAmount > 0 ||
              method == 'transfer' ||
              method == 'mixed' ||
              method == 'mixto'
          ? rawCashAmount
          : totalSold;
      final transferAmount = _firstPositiveDouble([
        payment['paymentTransferAmount'],
        payload['paymentTransferAmount'],
      ]);

      totalSales += totalSold;
      salesCash += cashAmount;
      salesTransfer += transferAmount;
      tickets += 1;
    }

    if (tickets == summary.totalTickets) return summary;
    return CashSummaryModel(
      openingAmount: summary.openingAmount,
      totalSales: totalSales,
      totalExpenses: summary.totalExpenses,
      totalWithdrawals: summary.totalWithdrawals,
      cashInManual: summary.cashInManual,
      cashOutManual: summary.cashOutManual,
      creditAbonos: summary.creditAbonos,
      creditSalesTotal: summary.creditSalesTotal,
      creditInitialCash: summary.creditInitialCash,
      creditInitialTransfer: summary.creditInitialTransfer,
      creditBalanceTotal: summary.creditBalanceTotal,
      creditPaymentCash: summary.creditPaymentCash,
      creditPaymentTransfer: summary.creditPaymentTransfer,
      salesCashTotal: salesCash,
      salesTransferTotal: salesTransfer,
      refundsCash: summary.refundsCash,
      expectedCash:
          summary.openingAmount +
          salesCash +
          summary.creditPaymentCash -
          summary.refundsCash +
          summary.cashInManual -
          summary.cashOutManual,
      totalTickets: tickets,
      totalRefunds: summary.totalRefunds,
      categorySummary: summary.categorySummary,
    );
  }

  Map<String, dynamic>? _firstPaymentPayload(Map<String, dynamic>? aggregate) {
    final payments = aggregate?['payments'];
    if (payments is List) {
      for (final payment in payments) {
        if (payment is Map) return payment.cast<String, dynamic>();
      }
    }
    final payment = aggregate?['payment'];
    if (payment is Map) return payment.cast<String, dynamic>();
    return null;
  }

  double _firstPositiveDouble(List<dynamic> values) {
    for (final value in values) {
      final amount = _asDouble(value);
      if (amount > 0) return amount;
    }
    return 0;
  }

  Map<String, dynamic> _activeSessionToJson(ActiveCashSession session) {
    return {
      'userId': session.userId,
      'cashId': session.cashId,
      'shiftId': session.shiftId,
      'openedAt': session.openedAt.toUtc().toIso8601String(),
      'status': session.status,
      'userName': session.userName,
      'businessDate': session.businessDate,
    };
  }
}

extension CashReviewedOperationCache on CashRepository {
  /// Applies only the local cache consequences of an audited review. The
  /// original outbox row remains evidence; no financial request is sent.
  Future<void> applyReviewedOperation(
    PendingSyncAction action, {
    required bool financiallyConfirmed,
  }) async {
    final owner = OperationScope.current;
    if (owner == null ||
        owner.companyId != action.companyId ||
        owner.userId != action.userId) {
      throw ApiException('La revisión no pertenece a la sesión original.');
    }
    if (action.type == CashRepository._movementSyncType) {
      await _removePendingMovement(action.payload['id']?.toString() ?? '');
    } else if ((action.type == CashRepository._closeSyncType &&
            financiallyConfirmed) ||
        (action.type == CashRepository._openSyncType &&
            !financiallyConfirmed)) {
      final id =
          (action.payload['sessionId'] ??
                  action.payload['clientSessionId'] ??
                  '')
              .toString();
      if (id.isNotEmpty) await _clearCachedSessionIfMatches(id);
    } else if (action.type == CashRepository._closeSyncType) {
      final id = action.payload['sessionId']?.toString();
      final cached = await _cache.readMap(
        CashRepository._activeSessionCacheKey,
      );
      if (id != null && _cachedSessionId(cached) == id) {
        await _cache.writeMap(CashRepository._activeSessionCacheKey, {
          ...?cached,
          'pendingClose': false,
          'fromCache': true,
          'canOperate': false,
        });
        lastStateFromCache = true;
      }
    }
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Genera un UUID v4 local (sin dependencias) para identificar de forma
/// inequívoca un turno de caja abierto offline. El backend lo acepta como
/// `clientSessionId` y lo usa como `id` del turno, de modo que el cierre
/// offline apunta a esa misma identidad.
String _newSessionUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante 10xx
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
