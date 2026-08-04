import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/errors/api_exception.dart';
import '../../core/offline/sync_queue_service.dart';
import 'cash_models.dart';

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
      );
      await _cache.writeMap(_activeSessionCacheKey, {
        'activeSession': _activeSessionToJson(session),
        'businessDate': session.businessDate,
        'canOperate': true,
      });
    });
    _syncQueue.registerHandler(_closeSyncType, (payload) async {
      await _closeSessionRemote(
        closingAmount: _asDouble(payload['closingAmount']),
        note: payload['note']?.toString(),
      );
      await _cache.remove(_activeSessionCacheKey);
      await _cache.remove(_pendingMovementsCacheKey);
    });
    _syncQueue.registerHandler(_movementSyncType, (payload) async {
      await _addMovementRemote(
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
    try {
      final res = await _dio.get(
        ApiRoutes.cashState,
        options: Options(extra: const {'skipLoader': true}),
      );
      final state = CashGateState.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      if (state.activeSession != null) {
        await _cache.writeMap(_activeSessionCacheKey, {
          'activeSession': _activeSessionToJson(state.activeSession!),
          'businessDate': state.businessDate,
          'canOperate': state.canOperate,
        });
      }
      return state;
    } on DioException catch (e) {
      if (_shouldQueueNetworkFailure(e)) {
        final cached = await _cache.readMap(_activeSessionCacheKey);
        if (cached != null) return CashGateState.fromJson(cached);
      }
      throw ApiException(_message(e.response?.data, 'No se pudo cargar caja'));
    }
  }

  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async {
    try {
      final session = await _openSessionRemote(
        openingAmount: openingAmount,
        note: note,
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
        shiftId: 'local_shift_${DateTime.now().microsecondsSinceEpoch}',
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
        id: '$_openSyncType:${local.shiftId}',
        type: _openSyncType,
        scope: 'cash',
        payload: {'openingAmount': openingAmount, 'note': note},
      );
      return local;
    }
  }

  Future<ActiveCashSession> _openSessionRemote({
    required double openingAmount,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.cashOpenSession,
        data: {
          'openingAmount': openingAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        },
      );
      return ActiveCashSession.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException {
      rethrow;
    }
  }

  Future<void> closeSession({
    required double closingAmount,
    String? note,
  }) async {
    try {
      await _closeSessionRemote(closingAmount: closingAmount, note: note);
      await _cache.remove(_activeSessionCacheKey);
      await _cache.remove(_pendingMovementsCacheKey);
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        throw ApiException(
          _message(e.response?.data, 'No se pudo cerrar turno'),
        );
      }
      await _syncQueue.enqueue(
        id: '$_closeSyncType:${DateTime.now().microsecondsSinceEpoch}',
        type: _closeSyncType,
        scope: 'cash',
        payload: {'closingAmount': closingAmount, 'note': note},
      );
      await _cache.remove(_activeSessionCacheKey);
    }
  }

  Future<void> _closeSessionRemote({
    required double closingAmount,
    String? note,
  }) {
    return _dio.post(
      ApiRoutes.cashCloseSession,
      data: {
        'closingAmount': closingAmount,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
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
      return _mergePendingMovementsIntoSummary(summary);
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
      final data = res.data is Map ? res.data as Map : const <String, dynamic>{};
      return CashSessionDetailModel.fromJson(data.cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar el detalle del turno'),
      );
    }
  }

  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    try {
      await _addMovementRemote(
        type: type,
        amount: amount,
        reason: reason,
        movementType: movementType,
        affectsProfit: affectsProfit,
      );
    } on DioException catch (e) {
      if (!_shouldQueueNetworkFailure(e)) {
        throw ApiException(
          _message(e.response?.data, 'No se pudo guardar movimiento'),
        );
      }
      final localId = 'local_cash_${DateTime.now().microsecondsSinceEpoch}';
      final payload = {
        'id': localId,
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
        payload: payload,
      );
    }
  }

  Future<void> _addMovementRemote({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) {
    return _dio.post(
      ApiRoutes.cashMovements,
      data: {
        'type': type,
        'amount': amount,
        'reason': reason,
        'movementType': movementType,
        if (affectsProfit != null) 'affectsProfit': affectsProfit,
      },
    );
  }

  bool _shouldQueueNetworkFailure(DioException error) {
    final status = error.response?.statusCode;
    return status == null || status >= 500;
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
      expectedCash:
          summary.openingAmount +
          summary.salesCashTotal -
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
