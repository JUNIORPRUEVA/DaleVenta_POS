import 'package:dio/dio.dart';

import '../debug/trace_log.dart';
import 'api_error_mapper.dart';
import 'api_offline_cache_interceptor.dart';

typedef ApiOfflineCachedResponseResolver =
    Future<Response<dynamic>?> Function(RequestOptions options);

class ApiOfflineCircuitState {
  ApiOfflineCircuitState({
    this.cooldown = const Duration(seconds: 12),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _now;
  DateTime? _offlineUntil;

  bool get isOfflineFastFailActive {
    final offlineUntil = _offlineUntil;
    return offlineUntil != null && _now().isBefore(offlineUntil);
  }

  void markOffline() {
    _offlineUntil = _now().add(cooldown);
  }

  void markOnline() {
    _offlineUntil = null;
  }
}

class ApiOfflineCircuitBreaker extends Interceptor {
  ApiOfflineCircuitBreaker({
    required ApiOfflineCircuitState state,
    ApiOfflineCachedResponseResolver? cachedResponseResolver,
    this.onReachabilityChanged,
  }) : _state = state,
       _cachedResponseResolver = cachedResponseResolver;

  final ApiOfflineCircuitState _state;
  final ApiOfflineCachedResponseResolver? _cachedResponseResolver;
  final void Function(bool reachable)? onReachabilityChanged;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['disableOfflineFastFail'] == true ||
        options.extra['skipConnectivityCheck'] == true) {
      handler.next(options);
      return;
    }

    if (!_state.isOfflineFastFailActive) {
      handler.next(options);
      return;
    }

    final cachedResponse = await _cachedResponseResolver?.call(options);
    if (cachedResponse != null) {
      TraceLog.log(
        'ApiHttp',
        'OFFLINE_FAST_CACHE ${options.method.toUpperCase()} ${options.uri}',
      );
      handler.resolve(cachedResponse);
      return;
    }

    TraceLog.log(
      'ApiHttp',
      'OFFLINE_FAST_FAIL ${options.method.toUpperCase()} ${options.uri}',
    );
    options.extra['disableRetry'] = true;
    options.extra['__offline_fast_fail'] = true;
    handler.reject(
      DioException.connectionError(
        requestOptions: options,
        reason: 'API marcada temporalmente sin conexión.',
      ),
    );
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.extra[ApiOfflineCacheInterceptor.cacheHitExtraKey] != true) {
      _state.markOnline();
      onReachabilityChanged?.call(true);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      _state.markOnline();
      onReachabilityChanged?.call(true);
    } else if (err.requestOptions.extra['disableOfflineFastFail'] != true &&
        ApiErrorMapper.shouldRetry(err)) {
      _state.markOffline();
      onReachabilityChanged?.call(false);
    }
    handler.next(err);
  }
}
