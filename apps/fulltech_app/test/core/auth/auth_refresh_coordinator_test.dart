import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/auth/auth_refresh_coordinator.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';

class _FakeTokenStorage extends TokenStorage {
  String? _access;
  String? _refresh;

  _FakeTokenStorage(this._access, this._refresh);

  @override
  Future<String?> getAccessToken() async => _access;

  @override
  Future<String?> getRefreshToken() async => _refresh;

  @override
  Future<void> saveTokens(String access, [String? refresh]) async {
    _access = access;
    if (refresh != null && refresh.isNotEmpty) _refresh = refresh;
  }
}

void main() {
  group('AuthRefreshCoordinator', () {
    test(
      'concurrent ensureRefreshed calls share a single POST /refresh (single-flight)',
      () async {
        var refreshCalls = 0;
        final dio = Dio(
          BaseOptions(baseUrl: 'https://example.test'),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path.endsWith('/auth/refresh')) {
                refreshCalls++;
              }
              handler.next(options);
            },
          ),
        );
        dio.httpClientAdapter = _CountingAdapter(() async {
          return Response(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            statusCode: 200,
            data: {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
          );
        });

        final storage = _FakeTokenStorage('old-access', 'old-refresh');
        final coordinator = AuthRefreshCoordinator(
          storage: storage,
          refreshDio: dio,
        );

        // Dispara 20 llamadas concurrentes (simula 20 requests 401 al volver).
        final futures = List.generate(
          20,
          (_) => coordinator.ensureRefreshed(),
        );
        final results = await Future.wait(futures);

        // Solo debe haber UN POST /refresh.
        expect(refreshCalls, 1);
        // Todas las llamadas deben ser exitosas.
        for (final r in results) {
          expect(r.isSuccess, isTrue);
        }
        // El token rotado se guardó una sola vez.
        expect(await storage.getAccessToken(), 'new-access');
        expect(await storage.getRefreshToken(), 'new-refresh');
      },
    );

    test('timeout/offline/5xx returns failed (no logout)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _CountingAdapter(() async {
        throw DioException(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          type: DioExceptionType.connectionTimeout,
        );
      });

      final storage = _FakeTokenStorage('old-access', 'old-refresh');
      final coordinator = AuthRefreshCoordinator(
        storage: storage,
        refreshDio: dio,
      );

      final result = await coordinator.ensureRefreshed();
      expect(result.isFailed, isTrue);
      expect(result.isInvalid, isFalse);
      // Los tokens NO se borran.
      expect(await storage.getAccessToken(), 'old-access');
      expect(await storage.getRefreshToken(), 'old-refresh');
    });

    test('5xx returns failed (no logout)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _CountingAdapter(() async {
        throw DioException(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            statusCode: 500,
          ),
        );
      });

      final storage = _FakeTokenStorage('old-access', 'old-refresh');
      final coordinator = AuthRefreshCoordinator(
        storage: storage,
        refreshDio: dio,
      );

      final result = await coordinator.ensureRefreshed();
      expect(result.isFailed, isTrue);
      expect(result.isInvalid, isFalse);
      expect(await storage.getAccessToken(), 'old-access');
    });

    test('400/401/403 returns invalid (real revocation)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = _CountingAdapter(() async {
        throw DioException(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            statusCode: 401,
          ),
        );
      });

      final storage = _FakeTokenStorage('old-access', 'old-refresh');
      final coordinator = AuthRefreshCoordinator(
        storage: storage,
        refreshDio: dio,
      );

      final result = await coordinator.ensureRefreshed();
      expect(result.isInvalid, isTrue);
      expect(result.isFailed, isFalse);
    });
  });
}

/// Adapter que delega a un handler sin red real.
class _CountingAdapter implements HttpClientAdapter {
  final Future<Response<dynamic>> Function() _handler;

  _CountingAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await _handler();
    return ResponseBody.fromString(
      response.data is Map ? _encode(response.data) : '{}',
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  String _encode(Map data) {
    final buffer = StringBuffer('{');
    var first = true;
    data.forEach((key, value) {
      if (!first) buffer.write(',');
      first = false;
      buffer.write('"$key":"$value"');
    });
    buffer.write('}');
    return buffer.toString();
  }

  @override
  void close({bool force = false}) {}
}
