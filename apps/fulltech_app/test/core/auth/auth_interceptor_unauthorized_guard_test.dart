import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión del UAT de Cafetería La Bomba:
///
/// El cliente encadenaba `GET /settings` -> 401 -> `clearTokens()` ->
/// recreación de `companySettingsRepositoryProvider` (hace
/// `watch(authStateProvider)`) -> nuevo `GET /settings` -> 401 ... en bucle
/// infinito (967 respuestas 401 en 5 minutos). El bucle borraba la sesión recién
/// creada, así que el login "parecía entrar" y volvía al login.
///
/// Regla: una respuesta 401/403 SOLO puede invalidar la sesión si la petición
/// llevaba credenciales. Sin `Authorization` no hay sesión que destruir.
class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage({this.accessToken});

  String? accessToken;
  String? refreshToken;
  int clearCalls = 0;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    clearCalls++;
    accessToken = null;
    refreshToken = null;
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> data, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// Crea un Dio con el interceptor real y un adaptador que siempre responde
/// `status` con [body] (sin red real).
Dio _dioResponding({
  required int status,
  required Map<String, dynamic> body,
  required _FakeTokenStorage storage,
  required AuthSessionEvents events,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
      return _jsonResponse(body, status: status);
    });
  dio.interceptors.add(AuthInterceptor(storage, events, dio));
  return dio;
}

void main() {
  group('AuthInterceptor: no escalar logout sin credenciales', () {
    test(
      '401 de un request sin token NO pide logout ni borra tokens '
      '(corta el bucle de /settings del UAT)',
      () async {
        final storage = _FakeTokenStorage();
        final events = AuthSessionEvents();
        final dio = _dioResponding(
          status: 401,
          body: {'message': 'Unauthorized'},
          storage: storage,
          events: events,
        );

        await expectLater(
          dio.get<dynamic>('/settings'),
          throwsA(isA<DioException>()),
        );

        expect(events.unauthorizedLogoutRequested, isFalse);
        expect(storage.clearCalls, 0);
      },
    );

    test(
      '403 de licencia sin token tampoco pide logout',
      () async {
        final storage = _FakeTokenStorage();
        final events = AuthSessionEvents();
        final dio = _dioResponding(
          status: 403,
          body: {'errorCode': 'LICENSE_BLOCKED', 'message': 'Licencia bloqueada'},
          storage: storage,
          events: events,
        );

        await expectLater(
          dio.get<dynamic>('/settings'),
          throwsA(isA<DioException>()),
        );

        expect(events.unauthorizedLogoutRequested, isFalse);
        expect(storage.clearCalls, 0);
      },
    );

    test(
      '403 de licencia CON token sí pide logout (comportamiento preservado)',
      () async {
        final storage = _FakeTokenStorage(accessToken: 'token-de-prueba');
        final events = AuthSessionEvents();
        final dio = _dioResponding(
          status: 403,
          body: {'errorCode': 'LICENSE_BLOCKED', 'message': 'Licencia bloqueada'},
          storage: storage,
          events: events,
        );

        await expectLater(
          dio.get<dynamic>('/settings'),
          throwsA(isA<DioException>()),
        );

        expect(events.unauthorizedLogoutRequested, isTrue);
        expect(events.isLicenseLogout, isTrue);
      },
    );
  });

  group('AuthController: logout por sesión inválida sin churn de estado', () {
    test(
      'estando ya desautenticado no reescribe AuthState (evita realimentar el bucle)',
      () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
          ],
        );
        addTearDown(container.dispose);

        // En tests, el bootstrap deja el estado desautenticado y asentado.
        expect(container.read(authStateProvider).isAuthenticated, isFalse);

        var authNotifications = 0;
        final subscription = container.listen(
          authStateProvider,
          (_, __) => authNotifications++,
        );
        addTearDown(subscription.close);

        container
            .read(authSessionEventsProvider)
            .requestUnauthorizedLogout(reason: 'license_expired');

        await pumpEventQueue();

        expect(
          authNotifications,
          0,
          reason: 'no debe notificar un nuevo AuthState si ya estaba fuera',
        );
        expect(container.read(authStateProvider).isAuthenticated, isFalse);
      },
    );
  });
}
