import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../api/env.dart';
import '../debug/trace_log.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

/// Resultado de un intento de refresh de token.
enum AuthRefreshOutcome { success, invalid, failed }

class AuthRefreshResult {
  final AuthRefreshOutcome outcome;
  final String? accessToken;
  final String? refreshToken;

  const AuthRefreshResult({
    required this.outcome,
    this.accessToken,
    this.refreshToken,
  });

  bool get isSuccess => outcome == AuthRefreshOutcome.success;
  bool get isInvalid => outcome == AuthRefreshOutcome.invalid;
  bool get isFailed => outcome == AuthRefreshOutcome.failed;
}

/// Coordinador único de refresh de token (single-flight).
///
/// Tanto [AuthInterceptor] como [AuthRepository] deben usar este coordinador
/// para garantizar que NUNCA haya dos POST /refresh concurrentes con el mismo
/// refresh token.
///
/// El servidor rota el refresh token en cada uso. Si dos sistemas de refresh
/// independientes usaran el mismo refresh token a la vez, el segundo fallaría
/// con 401 (token ya rotado) y, al interpretarse como revocación, cerraría la
/// sesión por un race interno de la app (bug: logout al volver de otra pestaña).
///
/// Este coordinador centraliza el refresh en un único `_inFlight` compartido:
///   * la primera llamada inicia el POST /refresh;
///   * las llamadas concurrentes reutilizan el mismo future;
///   * timeout/offline/5xx devuelven `failed` (sin logout);
///   * solo 400/401/403 del refresh canonical devuelven `invalid` (revocación real).
class AuthRefreshCoordinator {
  final TokenStorage storage;
  final Dio _refreshDio;
  Future<AuthRefreshResult>? _inFlight;

  AuthRefreshCoordinator({
    required this.storage,
    required Dio refreshDio,
  }) : _refreshDio = refreshDio;

  /// Devuelve el refresh en curso si existe; si no, inicia uno nuevo.
  Future<AuthRefreshResult> ensureRefreshed() {
    _inFlight ??= _perform().whenComplete(() {
      _inFlight = null;
    });
    return _inFlight!;
  }

  Future<AuthRefreshResult> _perform() async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('AuthRefresh', 'refresh start', seq: seq);

    final refresh = await storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      TraceLog.log(
        'AuthRefresh',
        'refresh invalid (no refresh token)',
        seq: seq,
      );
      return const AuthRefreshResult(outcome: AuthRefreshOutcome.invalid);
    }

    try {
      final res = await _refreshDio.post(
        ApiRoutes.refresh,
        data: {'refreshToken': refresh},
      );
      debugPrint(
        '[AUTH_CHANGE] POST /refresh status=${res.statusCode} '
        'caller=auth_refresh_coordinator._perform',
      );
      final data = res.data;
      if (data is Map) {
        final access = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (access != null && access.isNotEmpty) {
          await storage.saveTokens(
            access,
            (newRefresh != null && newRefresh.isNotEmpty)
                ? newRefresh
                : refresh,
          );
          TraceLog.log('AuthRefresh', 'refresh success', seq: seq);
          return AuthRefreshResult(
            outcome: AuthRefreshOutcome.success,
            accessToken: access,
            refreshToken: newRefresh,
          );
        }
      }
      TraceLog.log(
        'AuthRefresh',
        'refresh failed (no access token in response)',
        seq: seq,
      );
      return const AuthRefreshResult(outcome: AuthRefreshOutcome.failed);
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status == 400 || status == 401 || status == 403) {
        TraceLog.log(
          'AuthRefresh',
          'refresh invalid (status=$status)',
          seq: seq,
        );
        return const AuthRefreshResult(outcome: AuthRefreshOutcome.invalid);
      }
      TraceLog.log(
        'AuthRefresh',
        'refresh failed (status=$status)',
        seq: seq,
      );
      return const AuthRefreshResult(outcome: AuthRefreshOutcome.failed);
    } on TimeoutException {
      TraceLog.log('AuthRefresh', 'refresh failed (timeout)', seq: seq);
      return const AuthRefreshResult(outcome: AuthRefreshOutcome.failed);
    } catch (_) {
      TraceLog.log('AuthRefresh', 'refresh failed (unknown)', seq: seq);
      return const AuthRefreshResult(outcome: AuthRefreshOutcome.failed);
    }
  }
}

final authRefreshCoordinatorProvider = Provider<AuthRefreshCoordinator>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
      sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
      receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
      headers: {'Accept': 'application/json'},
    ),
  );
  return AuthRefreshCoordinator(storage: storage, refreshDio: refreshDio);
});
