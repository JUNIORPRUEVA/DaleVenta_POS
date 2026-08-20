import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../debug/trace_log.dart';
import '../api/api_routes.dart';
import 'auth_refresh_coordinator.dart';
import 'auth_session_events.dart';
import 'token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final AuthSessionEvents sessionEvents;
  final Dio dio;
  final AuthRefreshCoordinator refreshCoordinator;

  static const String _retryFlagKey = '__auth_retry';

  AuthInterceptor(
    this.tokenStorage,
    this.sessionEvents,
    this.dio,
    this.refreshCoordinator,
  );

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log(
      'AuthInterceptor',
      'onRequest start -> ${options.method} ${options.uri}',
      seq: seq,
    );

    try {
      if (_isPublicAuthPath(options.path)) {
        TraceLog.log(
          'AuthInterceptor',
          'onRequest public auth path -> skip bearer token',
          seq: seq,
        );
        handler.next(options);
        return;
      }

      // TokenStorage already applies its own timeouts (secure/prefs).
      // Avoid a second outer timeout that can cause requests to go out
      // without Authorization on slower devices (notably Windows).
      final token = await tokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      TraceLog.log(
        'AuthInterceptor',
        'onRequest token=${token == null ? 'null' : (token.isEmpty ? 'empty' : 'present')} (${sw.elapsedMilliseconds}ms)',
        seq: seq,
      );
    } on TimeoutException catch (e, st) {
      TraceLog.log(
        'AuthInterceptor',
        'onRequest getAccessToken() TIMEOUT -> continuing without token',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      TraceLog.log(
        'AuthInterceptor',
        'onRequest getAccessToken() ERROR -> continuing without token',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    }

    handler.next(options);
  }

  bool _isAuthRefreshPath(String path) {
    // `path` puede venir como '/auth/refresh' o con baseUrl ya aplicada en algunos casos.
    return path == ApiRoutes.refresh || path.endsWith(ApiRoutes.refresh);
  }

  bool _isPublicAuthPath(String path) {
    return path == ApiRoutes.login ||
        path.endsWith(ApiRoutes.login) ||
        path == ApiRoutes.registerBusiness ||
        path.endsWith(ApiRoutes.registerBusiness) ||
        _isAuthRefreshPath(path);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final responseData = err.response?.data;
    debugPrint(
      '[AUTH_CHANGE] interceptor onError status=$statusCode '
      'path=${err.requestOptions.path} caller=auth_interceptor.onError',
    );
    final errorCode = responseData is Map
        ? responseData['errorCode']?.toString().toUpperCase()
        : null;
    final errorMessage = responseData is Map
        ? responseData['message']?.toString().toLowerCase()
        : responseData?.toString().toLowerCase();
    final licenseInactive =
        errorCode == 'LICENSE_BLOCKED' ||
        errorCode == 'LICENSE_EXPIRED' ||
        errorCode == 'LICENSE_INACTIVE' ||
        errorMessage?.contains('licencia no activa') == true ||
        errorMessage?.contains('licencia expirada') == true ||
        errorMessage?.contains('licencia bloqueada') == true;
    final publicAuthPath = _isPublicAuthPath(err.requestOptions.path);
    if ((statusCode == 401 || statusCode == 403) && licenseInactive) {
      if (!publicAuthPath) {
        sessionEvents.requestUnauthorizedLogout(reason: 'license_expired');
      }
      return handler.next(err);
    }

    if (statusCode == 403 &&
        (licenseInactive ||
            errorCode == 'LICENSE_PRODUCT_LIMIT_REACHED' ||
            errorCode == 'LICENSE_USER_LIMIT_REACHED')) {
      sessionEvents.requestUnauthorizedLogout(
        reason: licenseInactive ? 'license_expired' : null,
      );
      return handler.next(err);
    }

    final alreadyRetried = err.requestOptions.extra[_retryFlagKey] == true;
    if (statusCode == 401 &&
        !publicAuthPath &&
        !_isAuthRefreshPath(err.requestOptions.path) &&
        !alreadyRetried) {
      final seq = TraceLog.nextSeq();
      TraceLog.log(
        'AuthInterceptor',
        'onError 401 -> attempting refresh',
        seq: seq,
      );

      try {
        final refreshed = await refreshCoordinator.ensureRefreshed();
        if (refreshed.isSuccess && refreshed.accessToken != null) {
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
          opts.extra[_retryFlagKey] = true;

          // Dio no permite reutilizar FormData ya enviada (queda "finalized").
          // Clonamos para que el reintento funcione en uploads multipart.
          final data = opts.data;
          if (data is FormData) {
            opts.data = data.clone();
          }

          final retryResponse = await dio.fetch(opts);
          return handler.resolve(retryResponse);
        }
        if (refreshed.isInvalid) {
          sessionEvents.requestUnauthorizedLogout(
            reason: licenseInactive ? 'license_expired' : null,
          );
        }
      } catch (_) {
        // Fall through to original error.
      }
    }
    handler.next(err);
  }
}
