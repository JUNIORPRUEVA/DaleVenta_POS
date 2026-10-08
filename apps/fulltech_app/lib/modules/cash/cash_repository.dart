import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/debug/trace_log.dart';
import '../../core/errors/api_exception.dart';
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

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  final repository = CashRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

class CashRepository {
  CashRepository(this._dio, this._syncQueue);

  final Dio _dio;
  final SyncQueueService _syncQueue;
  final LocalJsonCache _cache = LocalJsonCache();
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

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;
    _syncQueue.registerHandler(_openSyncType, (payload) async {
      final session = await _openSessionRemote(
        openingAmount: _asDouble(payload['openingAmount']),
        note: payload['note']?.toString(),
        clientSessionId: payload['clientSessionId']?.toString(),
      );
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
        closingAmount: _asDouble(payload['closingAmount']),
        note: payload['note']?.toString(),
      );
      // Limpiar la caché SOLO si el turno cerrado coincide con el turno que la
      // caché tiene como activo. Si no coinciden, borraríamos el turno actual
      // (otro) y la UI mostraría caja cerrada por error.
      await _clearCachedSessionIfMatches(sessionId);
    });
    _syncQueue.registerHandler(_movementSyncType, (payload) async {
      final sessionId = (payload['sessionId'] ?? '').toString().trim();
      if (sessionId.isEmpty) {
        TraceLog.log(
          'cash',
          'cash.movement.replay.obsolete reason=missing_session_id',
        );
        throw const ObsoleteSyncOperationException(
          'Movimiento de caja sin identificación de turno: descartado por seguridad.',
        );
      }
      await _addMovementRemote(
        sessionId: sessionId,
        operationId: payload['operationId']?.toString(),
        type: payload['type'].toString(),
        amount: _asDouble(payload['amount']),
        reason: payload['reason']?.toString() ?? '',
        movementType: payload['movementType']?.toString() ?? 'expense',
        affectsProfit: payload['affectsProfit'] as bool?,
      );
      await _removePendingMovement(payload['id']?.toString() ?? '');
    });
  }

  String _message(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
    }
    return fallback;
  }

  Future<CashGateState> state() async {
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
      TraceLog.log(
        'cash',
        'cash.fetch.done active=${state.activeSession?.shiftId ?? 'null'}',
      );
      if (state.activeSession != null) {
        await _cache.writeMap(_activeSessionCacheKey, {
          'activeSession': _activeSessionToJson(state.activeSession!),
          'businessDate': state.businessDate,
          'canOperate': state.canOperate,
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
          );
        }
      }
      throw ApiException(_message(e.response?.data, 'No se pudo cargar caja'));
    }
  }

  Future<ActiveCashSession> openSession({
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
    try {
      final session = await _openSessionRemote(
        openingAmount: openingAmount,
        note: note,
        clientSessionId: clientSessionId,
      );
      await _cache.writeMap(_activeSessionCacheKey, {
        'activeSession': _activeSessionToJson(session),
        'businessDate': session.businessDate,
        'canOperate': true,
      });
      return session;
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        throw ApiException(_message(e.response?.data, 'No se pudo abrir caja'));
      }
      final local = ActiveCashSession(
        userId: 'offline',
        shiftId: clientSessionId,
        openedAt: DateTime.now(),
        status: 'OPEN',
        userName: 'Caja offline',
        businessDate: _dateOnly(DateTime.now()),
      );
      await _cache.writeMap(_activeSessionCacheKey, {
        'activeSession': _activeSessionToJson(local),
        'businessDate': local.businessDate,
        'canOperate': true,
      });
      await _syncQueue.enqueue(
        id: '$_openSyncType:$clientSessionId',
        type: _openSyncType,
        scope: 'cash',
        entityType: 'cash_session',
        entityId: clientSessionId,
        idempotencyKey: '$_openSyncType:$clientSessionId',
        payload: {
          'openingAmount': openingAmount,
          'note': note,
          'clientSessionId': clientSessionId,
        },
      );
      return local;
    }
  }

  Future<ActiveCashSession> _openSessionRemote({
    required double openingAmount,
    String? note,
    String? clientSessionId,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.cashOpenSession,
        data: {
          'openingAmount': openingAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
          if ((clientSessionId ?? '').trim().isNotEmpty)
            'clientSessionId': clientSessionId!.trim(),
        },
      );
      return ActiveCashSession.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
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
  }) async {
    final resolvedSessionId = sessionId.trim();
    if (resolvedSessionId.isEmpty) {
      // Sin identidad de turno no se puede cerrar de forma segura.
      throw ApiException(
        'No pudimos identificar el turno a cerrar. Actualiza Fullpos e inténtalo nuevamente.',
      );
    }
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
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 409) {
        // El turno ya fue cerrado (por este dispositivo u otro) o el servidor
        // rechazó el cierre por conflicto de estado. NO es un fallo: el estado
        // real es CERRADO y la UI debe revalidar. Nunca se reintenta contra otro
        // turno.
        lastStateFromCache = false;
        TraceLog.log('cash', 'cash.conflict already_closed status=$status');
        await _clearCachedSessionIfMatches(resolvedSessionId);
        throw const CashSessionAlreadyClosedException(
          'El turno ya estaba cerrado.',
        );
      }
      if (!_shouldQueueNetworkFailure(e)) {
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
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return sessionId;
  }

  Future<CashSummaryModel> summary() async {
    try {
      final res = await _dio.get(
        ApiRoutes.cashSummary,
        options: Options(extra: const {'skipLoader': true}),
      );
      final summary = CashSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      return await _mergePendingMovementsIntoSummary(summary);
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        final cached = e.response?.data;
        if (cached is Map) {
          return _mergePendingMovementsIntoSummary(
            CashSummaryModel.fromJson(cached.cast<String, dynamic>()),
          );
        }
      }
      throw ApiException(_message(e.response?.data, 'No se pudo cargar corte'));
    }
  }

  Future<List<CashMovementModel>> movements() async {
    try {
      final res = await _dio.get(
        ApiRoutes.cashMovements,
        options: Options(extra: const {'skipLoader': true}),
      );
      final rows = res.data is List ? res.data as List : const [];
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
    try {
      final res = await _dio.get(
        ApiRoutes.cashMovementsHistory,
        queryParameters: {
          if ((type ?? '').trim().isNotEmpty) 'type': type!.trim(),
          if ((movementType ?? '').trim().isNotEmpty)
            'movementType': movementType!.trim(),
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          'take': take,
        },
        options: Options(extra: const {'skipLoader': true}),
      );
      final rows = res.data is List ? res.data as List : const [];
      return rows
          .whereType<Map>()
          .map((row) => CashMovementModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
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
    try {
      final res = await _dio.get(
        ApiRoutes.cashClosedSessions,
        options: Options(extra: const {'skipLoader': true}),
      );
      final rows = res.data is List ? res.data as List : const [];
      return rows
          .whereType<Map>()
          .map(
            (row) =>
                CashSessionHistoryModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar historial de turnos'),
      );
    }
  }

  Future<CashSessionDetailModel> sessionDetail(String id) async {
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
  }) async {
    final resolvedSessionId = (sessionId ?? '').trim();
    final localId = 'local_cash_${DateTime.now().microsecondsSinceEpoch}';
    final operationId = 'cash.movement:$localId';
    try {
      await _addMovementRemote(
        type: type,
        amount: amount,
        reason: reason,
        sessionId: resolvedSessionId.isEmpty ? null : resolvedSessionId,
        operationId: operationId,
        movementType: movementType,
        affectsProfit: affectsProfit,
      );
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        throw ApiException(
          _message(e.response?.data, 'No se pudo guardar movimiento'),
        );
      }
      if (resolvedSessionId.isEmpty) {
        // Sin identidad de turno no se puede garantizar el destino del
        // movimiento: no se encola (evita aplicarlo a un turno posterior).
        throw ApiException(
          'No pudimos identificar el turno del movimiento. Actualiza Fullpos e inténtalo nuevamente.',
        );
      }
      final payload = {
        'id': localId,
        'operationId': operationId,
        'sessionId': resolvedSessionId,
        'type': type,
        'amount': amount,
        'reason': reason,
        'movementType': movementType,
        if (affectsProfit != null) 'affectsProfit': affectsProfit,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _appendPendingMovement(payload);
      await _syncQueue.enqueue(
        id: '$_movementSyncType:$localId',
        type: _movementSyncType,
        scope: 'cash',
        entityType: 'cash_session',
        entityId: resolvedSessionId,
        idempotencyKey: operationId,
        payload: payload,
      );
    }
  }

  Future<void> _addMovementRemote({
    required String type,
    required double amount,
    required String reason,
    String? sessionId,
    String? operationId,
    String movementType = 'expense',
    bool? affectsProfit,
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

  Future<void> _appendPendingMovement(Map<String, dynamic> payload) async {
    final cached = await _cache.readMap(_pendingMovementsCacheKey);
    final rows = [...((cached?['items'] as List?) ?? const []), payload];
    await _cache.writeMap(_pendingMovementsCacheKey, {'items': rows});
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
    return rows
        .whereType<Map>()
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
