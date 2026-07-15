import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../commissions_models.dart';

final serviceOrderCommissionsApiProvider = Provider<ServiceOrderCommissionsApi>(
  (ref) {
    return ServiceOrderCommissionsApi(ref.watch(dioProvider));
  },
);

class ServiceOrderCommissionsApi {
  ServiceOrderCommissionsApi(this._dio);

  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  Future<ServiceOrderCommissionsResponse> list({
    required String period,
    required int page,
    required int pageSize,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceOrderCommissions,
        queryParameters: {'period': period, 'page': page, 'pageSize': pageSize},
        options: _backgroundOptions,
      );
      final raw = (res.data as Map?)?.cast<String, dynamic>();
      if (raw == null) {
        throw ApiException.detailed(
          message:
              'No se pudieron cargar las comisiones. El servidor devolvió un formato inválido.',
          type: ApiErrorType.parse,
          displayCode: 'PARSE_ERROR',
          retryable: false,
        );
      }
      return ServiceOrderCommissionsResponse.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar las comisiones');
    }
  }

  Future<AdminServiceCommissionUsersSummary> adminSummaryByUser({
    required DateTime from,
    required DateTime to,
    String? userId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminServiceCommissionsSummary,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
        },
        options: _backgroundOptions,
      );
      final raw = (res.data as Map?)?.cast<String, dynamic>();
      if (raw == null) {
        throw ApiException(
          'No se pudo cargar el resumen administrativo de servicios',
        );
      }
      return AdminServiceCommissionUsersSummary.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(
        error,
        'No se pudo cargar el resumen administrativo de servicios',
      );
    }
  }

  Future<List<ServiceOrderCommissionItem>> adminListByUser({
    required DateTime from,
    required DateTime to,
    required String userId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminServiceCommissions,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          'userId': userId.trim(),
        },
        options: _backgroundOptions,
      );
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) => ServiceOrderCommissionItem.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar los servicios del usuario');
    }
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
