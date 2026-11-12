import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';

/// Cobertura de los defectos confirmados en la auditoria de sesion:
///
///  1. Carrera de renovacion: dos refresh concurrentes con el mismo token. El
///     que pierde recibe 401 del servidor, pero la sesion sigue viva porque el
///     otro ya roto los tokens. El cliente NO debe cerrar sesion.
///  2. Renovacion realmente invalida: la sesion debe invalidarse (comportamiento
///     existente, se mantiene intacto).
///  3. Fallo de red al renovar: no debe cerrar sesion.
///  4. Logout voluntario: debe intentar revocar la sesion solo en el servidor.
///
/// La proteccion anti-replay del servidor no se toca.
class _MutableTokenStorage extends TokenStorage {
  _MutableTokenStorage({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;
  int clearCalls = 0;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    this.accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      this.refreshToken = refreshToken;
    }
  }

  @override
  Future<void> clearTokens() async {
    clearCalls++;
    accessToken = null;
    refreshToken = null;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> data, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Dio _buildDio(
  _MutableTokenStorage storage,
  AuthSessionEvents events,
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _Adapter(handler);
  final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _Adapter(handler);
  dio.interceptors.add(
    AuthInterceptor(storage, events, dio, refreshDio: refreshDio),
  );
  return dio;
}

void main() {
  group('carrera de renovacion', () {
    test('si otra peticion ya renovo, reintenta y no cierra sesion', () async {
      final storage = _MutableTokenStorage(
        accessToken: 'token-acceso-prueba-1',
        refreshToken: 'refresh-1',
      );
      final events = AuthSessionEvents();

      final dio = _buildDio(storage, events, (options) async {
        if (options.path == '/auth/refresh') {
          // Otro refresh gano la carrera: rota tokens y responde 401.
          storage.accessToken = 'token-acceso-prueba-2';
          storage.refreshToken = 'refresh-2';
          return _json({'message': 'Invalid refresh token'}, status: 401);
        }
        final auth = options.headers['Authorization'];
        if (auth == 'Bearer token-acceso-prueba-2') {
          return _json({'ok': true});
        }
        return _json({'message': 'Unauthorized'}, status: 401);
      });

      final response = await dio.get<dynamic>('/settings');

      expect(response.statusCode, 200);
      expect(storage.accessToken, 'token-acceso-prueba-2');
      expect(
        events.unauthorizedLogoutRequested,
        isFalse,
        reason: 'perder la carrera no invalida la sesion',
      );
      expect(storage.clearCalls, 0);
    });

    test('un refresh realmente invalido si pide logout', () async {
      final storage = _MutableTokenStorage(
        accessToken: 'token-acceso-prueba-1',
        refreshToken: 'refresh-1',
      );
      final events = AuthSessionEvents();

      final dio = _buildDio(storage, events, (options) async {
        return _json({'message': 'Invalid refresh token'}, status: 401);
      });

      await expectLater(
        dio.get<dynamic>('/settings'),
        throwsA(isA<DioException>()),
      );

      expect(events.unauthorizedLogoutRequested, isTrue);
    });

    test('un fallo de red al renovar no pide logout', () async {
      final storage = _MutableTokenStorage(
        accessToken: 'token-acceso-prueba-1',
        refreshToken: 'refresh-1',
      );
      final events = AuthSessionEvents();

      final dio = _buildDio(storage, events, (options) async {
        if (options.path == '/auth/refresh') {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        return _json({'message': 'Unauthorized'}, status: 401);
      });

      await expectLater(
        dio.get<dynamic>('/settings'),
        throwsA(isA<DioException>()),
      );

      expect(events.unauthorizedLogoutRequested, isFalse);
      expect(storage.clearCalls, 0);
      expect(storage.refreshToken, 'refresh-1', reason: 'conserva credenciales');
    });
  });

  group('logout voluntario', () {
    test('revoca la sesion actual en el servidor', () async {
      final storage = _MutableTokenStorage(
        accessToken: 'token-acceso-prueba-1',
        refreshToken: 'refresh-1',
      );
      final paths = <String>[];
      final methods = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _Adapter((options) async {
          paths.add(options.path);
          methods.add(options.method);
          return _json({'ok': true});
        });

      await AuthRepository(dio: dio, storage: storage).revokeCurrentSession();

      expect(paths, ['/auth/logout']);
      expect(methods, ['POST']);
    });

    test('no lanza si el servidor no responde', () async {
      final storage = _MutableTokenStorage(
        accessToken: 'token-acceso-prueba-1',
        refreshToken: 'refresh-1',
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _Adapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        });

      await expectLater(
        AuthRepository(dio: dio, storage: storage).revokeCurrentSession(),
        completes,
      );
      expect(storage.accessToken, 'token-acceso-prueba-1', reason: 'no limpia por su cuenta');
    });
  });
}
