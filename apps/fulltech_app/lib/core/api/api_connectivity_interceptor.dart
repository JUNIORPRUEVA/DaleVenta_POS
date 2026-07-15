import 'package:dio/dio.dart';

import '../network/network_reachability.dart';
import 'api_error_mapper.dart';

class ApiConnectivityInterceptor extends Interceptor {
  final Dio dio;
  final NetworkReachability reachability;

  ApiConnectivityInterceptor({required this.dio, required this.reachability});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipConnectivityCheck'] == true) {
      handler.next(options);
      return;
    }

    final configError = ApiErrorMapper.validateBaseUrl(
      rawBaseUrl: dio.options.baseUrl,
      requestUri: options.uri,
      method: options.method.toUpperCase(),
    );
    if (configError != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: configError,
          message: configError.message,
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }

    final probe = await reachability.probe(options.uri);

    // Advisory-only connectivity probe: do not block the real HTTP request.
    // On some Windows/mobile networks DNS lookup can timeout intermittently
    // while the backend is still reachable via HTTP.
    if (!probe.isReachable) {
      options.extra['connectivityProbeStatus'] = probe.status.name;
      options.extra['connectivityProbeDetail'] = probe.detail;
    }

    handler.next(options);
  }
}
