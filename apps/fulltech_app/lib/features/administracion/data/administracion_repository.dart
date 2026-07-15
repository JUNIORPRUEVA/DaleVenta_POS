import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../models/admin_panel_models.dart';

final administracionRepositoryProvider = Provider<AdministracionRepository>((
  ref,
) {
  return AdministracionRepository(ref.watch(dioProvider));
});

class AdministracionRepository {
  final Dio _dio;

  AdministracionRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  Future<AdminPanelOverview> getOverview({int days = 7}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminPanelOverview,
        queryParameters: {'days': days},
        options: Options(extra: const {'skipLoader': true}),
      );
      return AdminPanelOverview.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final attendance = await getAttendanceSummary(days: days);
        final sales = await getSalesSummary(days: days);
        final totalsAtt = (attendance['totals'] is Map)
            ? (attendance['totals'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final totalsSales = (sales['totals'] is Map)
            ? (sales['totals'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        return AdminPanelOverview(
          generatedAt: DateTime.now().toIso8601String(),
          metrics: {
            'activeUsers': totalsAtt['usersCount'] ?? 0,
            'missingPunchToday': 0,
            'noSalesInWindow': 0,
            'lateArrivalsToday': totalsAtt['tardyCount'] ?? 0,
            'salesInWindow': totalsSales['totalSales'] ?? 0,
          },
          alerts: const [],
        );
      }
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar resumen de administración',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<AdminAiInsights> getAiInsights({int days = 7}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminPanelAiInsights,
        queryParameters: {'days': days},
        options: Options(extra: const {'skipLoader': true}),
      );
      return AdminAiInsights.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final attendance = await getAttendanceSummary(days: days);
        final sales = await getSalesSummary(days: days);
        final totalsAtt = (attendance['totals'] is Map)
            ? (attendance['totals'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final totalsSales = (sales['totals'] is Map)
            ? (sales['totals'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        return AdminAiInsights(
          source: 'rules',
          message:
              'La API de panel avanzado aún no está desplegada en nube. Mostrando resumen base con endpoints compatibles.',
          metrics: {
            'tardyCount': totalsAtt['tardyCount'] ?? 0,
            'incompleteCount': totalsAtt['incompleteCount'] ?? 0,
            'totalSales': totalsSales['totalSales'] ?? 0,
            'totalSold': totalsSales['totalSold'] ?? 0,
          },
          alerts: const [],
        );
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar informe IA'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getAttendanceSummary({int days = 7}) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    String dateOnly(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    try {
      final res = await _dio.get(
        ApiRoutes.punchAttendanceSummary,
        queryParameters: {'from': dateOnly(from), 'to': dateOnly(now)},
        options: Options(extra: const {'skipLoader': true}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar resumen de ponches',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getSalesSummary({int days = 7}) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    String dateOnly(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    try {
      final res = await _dio.get(
        ApiRoutes.adminSalesSummary,
        queryParameters: {'from': dateOnly(from), 'to': dateOnly(now)},
        options: Options(extra: const {'skipLoader': true}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar resumen de ventas',
        ),
        e.response?.statusCode,
      );
    }
  }
}
