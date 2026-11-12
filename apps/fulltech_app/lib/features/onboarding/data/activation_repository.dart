import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import 'activation_models.dart';

final activationRepositoryProvider = Provider<ActivationRepository>((ref) {
  return ActivationRepository(ref.watch(dioProvider));
});

/// Cliente del onboarding de activación «Activa tu FullPOS».
///
/// Ninguna llamada envía `companyId`: el backend lo toma del token. El cliente
/// no puede pedir ni modificar el progreso de otra empresa.
class ActivationRepository {
  ActivationRepository(this._dio);

  final Dio _dio;
  static const _timeout = Duration(seconds: 18);
  static final _skipLoader = Options(extra: const {'skipLoader': true});

  Future<ActivationState> getState() => _call(
    () => _dio.get(
      ApiRoutes.onboardingActivation,
      options: _skipLoader,
    ),
  );

  Future<ActivationState> markWelcomeSeen() => _call(
    () => _dio.post(
      ApiRoutes.onboardingActivationWelcomeSeen,
      options: _skipLoader,
    ),
  );

  Future<ActivationState> dismiss() => _call(
    () => _dio.post(
      ApiRoutes.onboardingActivationDismiss,
      options: _skipLoader,
    ),
  );

  Future<ActivationState> reopen() => _call(
    () => _dio.post(
      ApiRoutes.onboardingActivationReopen,
      options: _skipLoader,
    ),
  );

  Future<ActivationState> skipTask(String key) => _call(
    () => _dio.post(
      ApiRoutes.onboardingActivationSkip(key),
      options: _skipLoader,
    ),
  );

  /// Deshace una omisión.
  Future<ActivationState> restoreTask(String key) => _call(
    () => _dio.delete(
      ApiRoutes.onboardingActivationSkip(key),
      options: _skipLoader,
    ),
  );

  Future<ActivationState> setTourStep(String key, int step) => _call(
    () => _dio.patch(
      ApiRoutes.onboardingActivationTour(key),
      data: {'step': step},
      options: _skipLoader,
    ),
  );

  Future<ActivationState> _call(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final res = await request().timeout(_timeout);
      final data = res.data;
      if (data is! Map) {
        throw ApiException('Respuesta inesperada del servidor');
      }
      return ActivationState.fromJson(data.cast<String, dynamic>());
    } on TimeoutException {
      throw ApiException('La preparación inicial tardó demasiado.');
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar la preparación inicial'),
        e.response?.statusCode,
      );
    }
  }

  String _message(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map && data['message'] is String) {
      final text = (data['message'] as String).trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}
