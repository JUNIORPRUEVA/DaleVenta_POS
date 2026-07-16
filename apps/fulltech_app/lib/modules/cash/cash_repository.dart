import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors/api_exception.dart';
import 'cash_models.dart';

final cashRepositoryProvider = Provider<CashRepository>((ref) {
  return CashRepository(ref.watch(dioProvider));
});

class CashRepository {
  CashRepository(this._dio);

  final Dio _dio;

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
      return CashGateState.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data, 'No se pudo cargar caja'));
    }
  }

  Future<ActiveCashSession> openSession({
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
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data, 'No se pudo abrir caja'));
    }
  }

  Future<void> closeSession({
    required double closingAmount,
    String? note,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.cashCloseSession,
        data: {
          'closingAmount': closingAmount,
          if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data, 'No se pudo cerrar turno'));
    }
  }

  Future<CashSummaryModel> summary() async {
    try {
      final res = await _dio.get(
        ApiRoutes.cashSummary,
        options: Options(extra: const {'skipLoader': true}),
      );
      return CashSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
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
      return rows
          .whereType<Map>()
          .map((row) => CashMovementModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
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

  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.cashMovements,
        data: {
          'type': type,
          'amount': amount,
          'reason': reason,
          'movementType': movementType,
          if (affectsProfit != null) 'affectsProfit': affectsProfit,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo guardar movimiento'),
      );
    }
  }
}
