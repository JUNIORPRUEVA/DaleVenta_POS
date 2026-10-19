import 'dart:convert';

import 'package:dio/dio.dart';

import '../debug/trace_log.dart';
import '../offline/offline_store.dart';

typedef OfflineCacheScopeResolver = Future<String> Function();
typedef OfflineCacheFastFailResolver = bool Function();

class ApiOfflineCacheInterceptor extends Interceptor {
  ApiOfflineCacheInterceptor({
    required OfflineStore store,
    OfflineCacheScopeResolver? scopeResolver,
    OfflineCacheFastFailResolver? fastFailActive,
  }) : _store = store,
       _scopeResolver = scopeResolver,
       _fastFailActive = fastFailActive;

  static const Duration defaultMaxAge = Duration(days: 7);
  static const String cacheHitExtraKey = '__offline_cache_hit';
  static const String cacheKeyExtraKey = '__offline_cache_key';

  final OfflineStore _store;
  final OfflineCacheScopeResolver? _scopeResolver;
  final OfflineCacheFastFailResolver? _fastFailActive;

  Future<Response<dynamic>?> cachedResponseFor(RequestOptions options) async {
    if (!_canServeCachedPreflightRequest(options)) return null;
    final cached = await _readResponse(options);
    if (cached == null) return null;
    return _cachedResponse(options, cached);
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_fastFailActive?.call() != true ||
        !_canServeCachedPreflightRequest(options)) {
      handler.next(options);
      return;
    }

    final response = await cachedResponseFor(options);
    if (response == null) {
      handler.next(options);
      return;
    }

    TraceLog.log(
      'offline_cache',
      'preflight cached ${options.method.toUpperCase()} ${options.uri}',
    );
    handler.resolve(response);
  }

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
    handler.resolve(await _cachedResponse(options, cached));
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
    if (!_canServeCachedRequest(options)) return false;
    if (error.response?.statusCode != null &&
        error.response!.statusCode! < 500) {
      return false;
    }
    return true;
  }

  bool _canServeCachedRequest(RequestOptions options) {
    if (options.extra['disableOfflineCache'] == true) return false;
    if (options.method.toUpperCase() != 'GET') return false;
    if (!_isJsonLike(options.responseType)) return false;
    return true;
  }

  bool _canServeCachedPreflightRequest(RequestOptions options) {
    if (options.extra['disableOfflineCache'] == true) return false;
    return options.method.toUpperCase() == 'GET';
  }

  bool _isJsonLike(ResponseType responseType) {
    return responseType == ResponseType.json ||
        responseType == ResponseType.plain;
  }

  Future<void> _writeResponse(Response response) async {
    final data = response.data;
    if (!_isJsonSerializable(data)) return;

    try {
      await _store.writeCacheEntry(await _cacheKey(response.requestOptions), {
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
      return await _store.readCacheEntry(
        await _cacheKey(options),
        maxAge: maxAge,
      );
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

  Future<String> _cacheKey(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final uri = options.uri.replace(fragment: '').toString();
    final explicitScope = options.extra['offlineCacheScope']?.toString().trim();
    final resolvedScope = explicitScope != null && explicitScope.isNotEmpty
        ? explicitScope
        : await _resolveScope();
    return 'http-cache:v2:$resolvedScope:$method:$uri';
  }

  Future<String> _resolveScope() async {
    try {
      final scope = (await _scopeResolver?.call())?.trim() ?? '';
      if (scope.isNotEmpty) return scope;
    } catch (error, stackTrace) {
      TraceLog.log(
        'offline_cache',
        'scope resolver failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return 'public';
  }

  Future<Response<dynamic>> _cachedResponse(
    RequestOptions options,
    Map<String, dynamic> cached,
  ) async {
    return Response<dynamic>(
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
        cacheKeyExtraKey: await _cacheKey(options),
      },
    );
  }
}
