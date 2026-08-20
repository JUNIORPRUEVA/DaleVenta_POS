import 'dart:convert';

import 'package:dio/dio.dart';

import '../debug/trace_log.dart';

class ApiDiagnosticsInterceptor extends Interceptor {
  static const String _traceKey = '__api_trace_id';
  static const String _stopwatchKey = '__api_trace_stopwatch';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final traceId = TraceLog.nextSeq();
    final stopwatch = Stopwatch()..start();
    options.extra[_traceKey] = traceId;
    options.extra[_stopwatchKey] = stopwatch;

    TraceLog.log(
      'ApiHttp',
      'REQUEST ${options.method.toUpperCase()} ${options.uri} headers=${_redactHeaders(options.headers)} body=${_compact(options.data)}',
      seq: traceId,
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final requestOptions = response.requestOptions;
    final traceId = requestOptions.extra[_traceKey] as int?;
    final stopwatch = requestOptions.extra[_stopwatchKey] as Stopwatch?;
    final elapsedMs = stopwatch?.elapsedMilliseconds;
    TraceLog.log(
      'ApiHttp',
      'RESPONSE ${requestOptions.method.toUpperCase()} ${requestOptions.uri} status=${response.statusCode} elapsed=${elapsedMs ?? 0}ms body=${_compact(response.data)}',
      seq: traceId,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestOptions = err.requestOptions;
    final traceId = requestOptions.extra[_traceKey] as int?;
    final stopwatch = requestOptions.extra[_stopwatchKey] as Stopwatch?;
    final elapsedMs = stopwatch?.elapsedMilliseconds;
    TraceLog.log(
      'ApiHttp',
      'ERROR ${requestOptions.method.toUpperCase()} ${requestOptions.uri} status=${err.response?.statusCode} type=${err.type} elapsed=${elapsedMs ?? 0}ms detail=${err.error ?? err.message ?? 'unknown'}',
      seq: traceId,
      error: err,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }

  String _redactHeaders(Map<String, dynamic> headers) {
    final sanitized = <String, dynamic>{};
    headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      if (lowerKey == 'authorization' || lowerKey == 'cookie') {
        sanitized[key] = '***';
      } else {
        sanitized[key] = value;
      }
    });
    return jsonEncode(sanitized);
  }

  String _compact(dynamic value) {
    if (value == null) return 'null';
    if (value is FormData) {
      return 'FormData(fields=${value.fields.length}, files=${value.files.length})';
    }
    final text = value is String ? value : jsonEncode(value);
    if (text.length <= 400) return text;
    return '${text.substring(0, 400)}...';
  }
}
