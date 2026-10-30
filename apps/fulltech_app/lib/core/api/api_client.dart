import 'package:dio/dio.dart';
import '../config/uat_network_guard.dart';
import 'env.dart';

class ApiClient {
  final Dio dio;

  ApiClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          headers: {'Accept': 'application/json'},
          // En UAT no se siguen redirecciones: un 3xx hacia un host productivo
          // no debe ejecutarse nunca.
          followRedirects: !UatNetworkGuard.isUat,
        ),
      ) {
    if (UatNetworkGuard.isUat) {
      dio.interceptors.add(_UatDestinationInterceptor());
    }
  }
}

/// Bloquea cualquier petición cuyo destino real no sea un host local permitido.
///
/// `Env.apiBaseUrl` ya valida la URL base, pero una petición puede llevar una
/// URL absoluta o el servidor puede intentar redirigir. Esta comprobación se
/// ejecuta **antes** de enviar credenciales o cabeceras de telemetría.
class _UatDestinationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      UatNetworkGuard.assertAllowedUri(options.uri, key: 'REQUEST');
      handler.next(options);
    } on Object catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
          type: DioExceptionType.unknown,
          message: error.toString(),
        ),
      );
    }
  }
}
