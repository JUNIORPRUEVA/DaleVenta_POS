import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';

class EcfConnectionException extends ApiException {
  EcfConnectionException({
    this.uncertain = false,
    this.serviceUnavailable = false,
  }) : super.detailed(
         message: uncertain
             ? 'No se confirmó el resultado. Revisa su estado antes de repetir.'
             : serviceUnavailable
             ? 'El servicio no está disponible. Inténtalo más tarde.'
             : 'La factura electrónica requiere internet.',
         type: ApiErrorType.network,
         displayCode: uncertain
             ? 'ECF_RESULT_UNCONFIRMED'
             : 'ECF_CONNECTION_REQUIRED',
         retryable: false,
       );

  final bool uncertain;
  final bool serviceUnavailable;
  String get noticeTitle => uncertain
      ? 'Resultado pendiente'
      : serviceUnavailable
      ? 'Servicio no disponible'
      : 'Sin conexión';
}

bool ecfCommunicationInterrupted(DioException error) =>
    const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.cancel,
      DioExceptionType.unknown,
    }.contains(error.type) ||
    (error.response?.statusCode ?? 0) >= 500;

/// Real, read-only HTTP reachability. A DNS/Wi-Fi indicator is insufficient.
Future<void> ensureEcfConnection(Dio dio) async {
  try {
    final response = await dio.get<dynamic>(
      '/health',
      options: Options(
        sendTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        extra: const {
          'skipLoader': true,
          'skipConnectivityCheck': true,
          'disableOfflineCache': true,
          'disableRetry': true,
        },
      ),
    );
    if (response.data is! Map || (response.data as Map)['status'] != 'ok') {
      throw EcfConnectionException(serviceUnavailable: true);
    }
  } on DioException catch (error) {
    throw EcfConnectionException(
      serviceUnavailable:
          error.response != null ||
          error.type == DioExceptionType.badCertificate,
    );
  }
}

/// Never turns an interrupted POST into a request with a new identity.
Future<Response<dynamic>> postEcf(Dio dio, String path, {Object? data}) async {
  await ensureEcfConnection(dio);
  try {
    return await dio.post<dynamic>(
      path,
      data: data,
      options: Options(extra: const {'disableRetry': true}),
    );
  } on DioException catch (error) {
    if (ecfCommunicationInterrupted(error)) {
      throw EcfConnectionException(uncertain: true);
    }
    rethrow;
  }
}
