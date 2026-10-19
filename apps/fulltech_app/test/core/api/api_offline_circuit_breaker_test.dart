import 'dart:async';

import 'package:daleventa_pos/core/api/api_offline_cache_interceptor.dart';
import 'package:daleventa_pos/core/api/api_offline_circuit_breaker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fast-fails requests after the API is marked offline', () async {
    final state = ApiOfflineCircuitState(cooldown: const Duration(hours: 1));
    final adapter = _FailingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ApiOfflineCircuitBreaker(state: state));

    await expectLater(
      dio.post<dynamic>('/sales'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.calls, 1);
    expect(state.isOfflineFastFailActive, isTrue);

    await expectLater(
      dio.post<dynamic>('/sales'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.calls, 1);
  });

  test(
    'fast-fails cacheable reads without touching the network adapter',
    () async {
      final state = ApiOfflineCircuitState();
      final adapter = _FailingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'))
        ..httpClientAdapter = adapter
        ..interceptors.add(ApiOfflineCircuitBreaker(state: state));

      state.markOffline();

      await expectLater(
        dio.get<dynamic>('/products'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.calls, 0);
    },
  );

  test(
    'uses cached resolver before the offline circuit touches network',
    () async {
      final state = ApiOfflineCircuitState(cooldown: const Duration(hours: 1));
      state.markOffline();
      final adapter = _FailingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'))
        ..httpClientAdapter = adapter
        ..interceptors.add(
          ApiOfflineCircuitBreaker(
            state: state,
            cachedResponseResolver: (options) async => Response<dynamic>(
              requestOptions: options,
              data: const {'source': 'cache'},
              statusCode: 200,
              extra: const {ApiOfflineCacheInterceptor.cacheHitExtraKey: true},
            ),
          ),
        );

      final response = await dio.get<dynamic>('/products');

      expect(response.data, const {'source': 'cache'});
      expect(
        response.extra[ApiOfflineCacheInterceptor.cacheHitExtraKey],
        isTrue,
      );
      expect(adapter.calls, 0);
    },
  );

  test(
    'does not fast-fail requests that explicitly bypass the circuit',
    () async {
      final state = ApiOfflineCircuitState();
      final adapter = _SuccessAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:46548'))
        ..httpClientAdapter = adapter
        ..interceptors.add(ApiOfflineCircuitBreaker(state: state));

      state.markOffline();

      final response = await dio.get<dynamic>(
        '/health',
        options: Options(extra: const {'disableOfflineFastFail': true}),
      );

      expect(response.statusCode, 200);
      expect(adapter.calls, 1);
      expect(state.isOfflineFastFailActive, isFalse);
    },
  );
}

class _FailingAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SuccessAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
