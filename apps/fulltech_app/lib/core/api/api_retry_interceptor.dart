import 'dart:async';

import 'package:dio/dio.dart';

import '../debug/trace_log.dart';
import 'api_error_mapper.dart';
import 'retry_after.dart';

class ApiRetryInterceptor extends Interceptor {
  static const String _retryAttemptKey = '__api_retry_attempt';

  final Dio dio;
  final int maxRetries;

  ApiRetryInterceptor({required this.dio, this.maxRetries = 2});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final currentAttempt = (options.extra[_retryAttemptKey] as int?) ?? 0;
    if (!_shouldRetry(err, options, currentAttempt)) {
      handler.next(err);
      return;
    }

    final nextAttempt = currentAttempt + 1;
    options.extra[_retryAttemptKey] = nextAttempt;
    final serverDelay = parseRetryAfter(err.response?.headers.value('retry-after'));
    final delay = serverDelay ?? Duration(milliseconds: 350 * nextAttempt);
    // Long server deadlines belong to the durable outbox, not a suspended
    // in-memory request that could disappear when the app is closed.
    if (delay > const Duration(seconds: 5)) {
      handler.next(err);
      return;
    }
    final traceId = options.extra['__api_trace_id'] as int?;
    TraceLog.log(
      'ApiHttp',
      'RETRY ${options.method.toUpperCase()} ${options.uri} attempt=$nextAttempt/$maxRetries wait=${delay.inMilliseconds}ms',
      seq: traceId,
    );

    await Future.delayed(delay);
    try {
      final data = options.data;
      if (data is FormData) {
        options.data = data.clone();
      }
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldRetry(
    DioException error,
    RequestOptions options,
    int currentAttempt,
  ) {
    if (options.extra['disableRetry'] == true) return false;
    if (currentAttempt >= maxRetries) return false;

    final method = options.method.toUpperCase();
    final allowUnsafeMethods = options.extra['retryUnsafeMethods'] == true;
    final methodAllowed =
        method == 'GET' ||
        method == 'HEAD' ||
        method == 'OPTIONS' ||
        allowUnsafeMethods;
    if (!methodAllowed) return false;

    return ApiErrorMapper.shouldRetry(error);
  }
}
