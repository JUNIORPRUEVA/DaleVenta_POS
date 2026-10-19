import 'dart:async';

import 'package:dio/dio.dart';

import '../api/api_routes.dart';
import '../auth/token_storage.dart';
import '../debug/trace_log.dart';
import '../usage/client_telemetry_headers.dart';
import 'offline_emergency_policy.dart';

class OfflineEmergencyValidationInterceptor extends Interceptor {
  OfflineEmergencyValidationInterceptor({
    required TokenStorage tokenStorage,
    required Dio dio,
    OfflineEmergencyPolicy? policy,
  }) : _tokenStorage = tokenStorage,
       _dio = dio,
       _policy = policy ?? OfflineEmergencyPolicy();

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final OfflineEmergencyPolicy _policy;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final path = options.uri.path.replaceFirst(RegExp(r'^/api(?=/)'), '');
    final advanced = options.data is Map &&
        ((options.data as Map)['operationId'] ?? '').toString().trim().isNotEmpty &&
        ((options.method == 'POST' && path == '/products') ||
            (options.method == 'PATCH' && RegExp(r'^/products/[^/]+/stock$').hasMatch(path)));
    if (!advanced) {
      handler.next(options);
      return;
    }
    final owner = await _tokenStorage.getUserSnapshot();
    try {
      final headers = await ClientTelemetryHeaders.instance.headers();
      final response = await _dio.post(
        ApiRoutes.offlineEmergencyAuthorize,
        data: <String, dynamic>{},
        options: Options(headers: headers, extra: {'skipLoader': true}),
      );
      final current = await _tokenStorage.getUserSnapshot();
      final data = response.data;
      if (owner?.companyId != current?.companyId || owner?.id != current?.id ||
          data is! Map || data['companyId'] != owner?.companyId ||
          data['userId'] != owner?.id ||
          data['deviceFingerprint'] != headers['x-client-device-id'] ||
          data['authorized'] != true) {
        throw DioException(requestOptions: options, response: Response(
          requestOptions: options, statusCode: 401,
          data: {'message': 'La sesión cambió. Tus pendientes conservan su empresa original.'},
        ), type: DioExceptionType.badResponse);
      }
      await _recordValidation(data);
      if (!OfflineEmergencyPolicy.supportsAdvancedProtocol(data)) {
        await _disableAdvanced(owner?.companyId, owner?.id);
        handler.reject(_incompatible(options));
        return;
      }
      handler.next(options);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 || error.response?.statusCode == 400) {
        await _disableAdvanced(owner?.companyId, owner?.id);
        handler.reject(_incompatible(options));
      } else {
        handler.reject(error.copyWith(requestOptions: options));
      }
    } catch (error, stackTrace) {
      TraceLog.log('OfflineCompatibility', 'No se pudo comprobar compatibilidad', error: error, stackTrace: stackTrace);
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }

  Future<void> _disableAdvanced(String? companyId, String? userId) async {
    if (companyId == null || userId == null) return;
    await _policy.disableAdvancedOperations(companyId: companyId, userId: userId);
  }

  DioException _incompatible(RequestOptions options) {
    // This service is reachable but lacks the protocol. Keep legacy requests online.
    options.extra['disableOfflineFastFail'] = true;
    options.extra['disableRetry'] = true;
    return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: 503, data: {
      'code': 'OFFLINE_PROTOCOL_UNSUPPORTED',
      'message': 'Esta operación necesita una actualización del servicio. Tus pendientes permanecen guardados.',
    }),
    );
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 200 &&
        statusCode < 300 &&
        _isOfflineAuthorizationPath(response.requestOptions.path)) {
      unawaited(_recordValidation(response.data));
    }
    handler.next(response);
  }

  bool _isOfflineAuthorizationPath(String path) {
    return path == ApiRoutes.offlineEmergencyAuthorize ||
        path.endsWith(ApiRoutes.offlineEmergencyAuthorize);
  }

  Future<void> _recordValidation(dynamic data) async {
    try {
      if (data is! Map) return;
      final user = await _tokenStorage.getUserSnapshot();
      final companyId = user?.companyId?.trim();
      final userId = user?.id.trim();
      if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) return;
      final telemetryHeaders = await ClientTelemetryHeaders.instance.headers();
      final deviceFingerprint = telemetryHeaders['x-client-device-id']?.trim();
      if ((deviceFingerprint ?? '').isEmpty) return;

      await _policy.recordAuthorizationResponse(
        data: data.cast<String, dynamic>(),
        companyId: companyId!,
        userId: userId!,
        deviceFingerprint: deviceFingerprint!,
      );
    } catch (e, st) {
      TraceLog.log(
        'OfflineEmergencyValidation',
        'No se pudo registrar validación offline',
        error: e,
        stackTrace: st,
      );
    }
  }
}
