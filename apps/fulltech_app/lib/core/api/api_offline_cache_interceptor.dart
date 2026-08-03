import 'dart:convert';

import 'package:dio/dio.dart';

import '../debug/trace_log.dart';
import '../offline/offline_store.dart';

class ApiOfflineCacheInterceptor extends Interceptor {
  ApiOfflineCacheInterceptor({required OfflineStore store}) : _store = store;

  static const Duration defaultMaxAge = Duration(days: 7);
  static const String cacheHitExtraKey = '__offline_cache_hit';
  static const String cacheKeyExtraKey = '__offline_cache_key';

  final OfflineStore _store;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (_shouldCache(response.requestOptions, response.statusCode)) {
      await _writeResponse(response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (!_canServeCached(options, err)) {
      handler.next(err);
      return;
    }

    final cached = await _readResponse(options);
    if (cached == null) {
      handler.next(err);
      return;
    }

    TraceLog.log(
      'offline_cache',
      'serving cached ${options.method.toUpperCase()} ${options.uri}',
    );
    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        data: cached['data'],
        statusCode: (cached['statusCode'] as num?)?.toInt() ?? 200,
        statusMessage: 'OFFLINE_CACHE',
        headers: Headers.fromMap(
          ((cached['headers'] as Map?) ?? const <String, dynamic>{}).map(
            (key, value) => MapEntry(
              key.toString(),
              value is List
                  ? value.map((item) => item.toString()).toList()
                  : [value.toString()],
            ),
          ),
        ),
        extra: {
          ...options.extra,
          cacheHitExtraKey: true,
          cacheKeyExtraKey: _cacheKey(options),
        },
      ),
    );
  }

  bool _shouldCache(RequestOptions options, int? statusCode) {
    if (options.extra['disableOfflineCache'] == true) return false;
    if (options.method.toUpperCase() != 'GET') return false;
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      return false;
    }
    return _isJsonLike(options.responseType);
  }

  bool _canServeCached(RequestOptions options, DioException error) {
    if (options.extra['disableOfflineCache'] == true) return false;
    if (options.method.toUpperCase() != 'GET') return false;
    if (!_isJsonLike(options.responseType)) return false;
    if (error.response?.statusCode != null &&
        error.response!.statusCode! < 500) {
      return false;
    }
    return true;
  }

  bool _isJsonLike(ResponseType responseType) {
    return responseType == ResponseType.json ||
        responseType == ResponseType.plain;
  }

  Future<void> _writeResponse(Response response) async {
    final data = response.data;
    if (!_isJsonSerializable(data)) return;

    try {
      await _store.writeCacheEntry(_cacheKey(response.requestOptions), {
        'data': data,
        'statusCode': response.statusCode ?? 200,
        'headers': response.headers.map,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error, stackTrace) {
      TraceLog.log(
        'offline_cache',
        'write failed ${response.requestOptions.uri}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, dynamic>?> _readResponse(RequestOptions options) async {
    final maxAge = options.extra['offlineCacheMaxAge'] is Duration
        ? options.extra['offlineCacheMaxAge'] as Duration
        : defaultMaxAge;
    try {
      return await _store.readCacheEntry(_cacheKey(options), maxAge: maxAge);
    } catch (error, stackTrace) {
      TraceLog.log(
        'offline_cache',
        'read failed ${options.uri}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  bool _isJsonSerializable(dynamic data) {
    try {
      jsonEncode(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _cacheKey(RequestOptions options) {
    final method = options.method.toUpperCase();
    final uri = options.uri.replace(fragment: '').toString();
    return 'http-cache:$method:$uri';
  }
}
