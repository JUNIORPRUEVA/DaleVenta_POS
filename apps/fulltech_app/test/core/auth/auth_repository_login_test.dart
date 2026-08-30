import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';

void main() {
  test('conserva companyId entregado por users/me', () async {
    final user = await _loginWith(
      me: {'companyId': 'company-from-me'},
      jwtCompanyId: 'company-from-jwt',
    );

    expect(user.companyId, 'company-from-me');
  });

  test('usa companyId del JWT cuando users/me no lo entrega', () async {
    final user = await _loginWith(jwtCompanyId: 'company-from-jwt');

    expect(user.companyId, 'company-from-jwt');
  });

  test('login rechaza sesion sin companyId', () async {
    await expectLater(
      _loginWith(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.displayCode,
          'displayCode',
          'SESSION_INCOMPLETE',
        ),
      ),
    );
  });

  test('login traduce fallos de conexion sin terminos internos', () async {
    final error = await _captureAuthError(
      (repository) => repository.login('user@example.test', 'password'),
      DioException.connectionError(
        requestOptions: RequestOptions(path: '/auth/login'),
        reason: 'Connection reset by peer',
      ),
    );

    expect(error.type, ApiErrorType.network);
    expect(error.message, contains('conexión'));
    expect(_containsInternalTerms(error.message), isFalse);
  });

  test('crear negocio explica fallo DNS sin terminos internos', () async {
    final error = await _captureAuthError(
      (repository) => repository.registerBusiness(const {}),
      DioException.connectionError(
        requestOptions: RequestOptions(path: '/auth/register-business'),
        reason: 'Failed host lookup',
      ),
    );

    expect(error.type, ApiErrorType.dns);
    expect(error.message, contains('servicio'));
    expect(_containsInternalTerms(error.message), isFalse);
  });

  test('crear negocio explica rechazo de conexion segura', () async {
    final error = await _captureAuthError(
      (repository) => repository.registerBusiness(const {}),
      DioException(
        requestOptions: RequestOptions(path: '/auth/register-business'),
        type: DioExceptionType.badCertificate,
        message: 'certificate verify failed',
      ),
    );

    expect(error.type, ApiErrorType.tls);
    expect(error.message, contains('conexión segura'));
    expect(error.message, contains('fecha y hora'));
    expect(_containsInternalTerms(error.message), isFalse);
  });

  test('crear negocio confirma sesion con users/me', () async {
    final user = await _registerWith(
      me: const {'companyId': 'company-from-me'},
    );

    expect(user.companyId, 'company-from-me');
  });

  test(
    'crear negocio conserva companyId desde el token creado si users/me falla',
    () async {
      final user = await _registerWith(
        jwtCompanyId: 'company-from-jwt',
        failMe: true,
      );

      expect(user.companyId, 'company-from-jwt');
    },
  );

  test(
    'crear negocio incompleto limpia sesion local y no entra a medias',
    () async {
      final storage = _FakeTokenStorage();

      await expectLater(
        _registerWith(storage: storage, failMe: true),
        throwsA(
          isA<ApiException>().having(
            (error) => error.displayCode,
            'displayCode',
            'CREATED_SESSION_INCOMPLETE',
          ),
        ),
      );

      expect(storage.savedTokens, isTrue);
      expect(storage.clearedTokens, isTrue);
      expect(storage.savedUserSnapshot, isFalse);
    },
  );
}

Future<UserModel> _loginWith({String? jwtCompanyId, Map<String, dynamic>? me}) {
  final storage = _FakeTokenStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
      if (options.path == '/auth/login') {
        return _jsonResponse({
          'accessToken': _jwt(jwtCompanyId),
          'refreshToken': 'refresh-for-test',
        });
      }
      if (options.path == '/users/me') {
        return _jsonResponse({
          'id': 'user-1',
          'email': 'user@example.test',
          'role': 'ADMIN',
          ...?me,
        });
      }
      throw StateError('Unexpected endpoint: ${options.path}');
    });

  return AuthRepository(
    dio: dio,
    storage: storage,
  ).login('user@example.test', 'password-for-test');
}

Future<UserModel> _registerWith({
  String? jwtCompanyId,
  Map<String, dynamic>? me,
  bool failMe = false,
  _FakeTokenStorage? storage,
}) {
  final tokenStorage = storage ?? _FakeTokenStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
      if (options.path == '/auth/register-business') {
        return _jsonResponse({
          'accessToken': _jwt(jwtCompanyId),
          'refreshToken': 'refresh-for-test',
          'user': {
            'id': 'user-1',
            'email': 'user@example.test',
            'role': 'ADMIN',
          },
        });
      }
      if (options.path == '/users/me') {
        if (failMe) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection reset by peer',
          );
        }
        return _jsonResponse({
          'id': 'user-1',
          'email': 'user@example.test',
          'role': 'ADMIN',
          ...?me,
        });
      }
      throw StateError('Unexpected endpoint: ${options.path}');
    });

  return AuthRepository(
    dio: dio,
    storage: tokenStorage,
  ).registerBusiness(const {});
}

ResponseBody _jsonResponse(Map<String, dynamic> data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Future<ApiException> _captureAuthError(
  Future<void> Function(AuthRepository repository) action,
  DioException failure,
) async {
  final storage = _FakeTokenStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _FailingHttpClientAdapter(failure);
  final repository = AuthRepository(dio: dio, storage: storage);

  try {
    await action(repository);
  } on ApiException catch (error) {
    return error;
  }

  fail('Expected ApiException');
}

bool _containsInternalTerms(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('backend') || normalized.contains('frontend');
}

String _jwt(String? companyId) {
  final payload = <String, dynamic>{
    if (companyId != null) 'companyId': companyId,
  };
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode(payload)}.';
}

class _FakeTokenStorage extends TokenStorage {
  bool savedTokens = false;
  bool clearedTokens = false;
  bool savedUserSnapshot = false;

  @override
  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    savedTokens = true;
  }

  @override
  Future<void> saveUserSnapshot(UserModel user) async {
    savedUserSnapshot = true;
  }

  @override
  Future<void> clearTokens() async {
    clearedTokens = true;
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

class _FailingHttpClientAdapter implements HttpClientAdapter {
  _FailingHttpClientAdapter(this.error);

  final DioException error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw error.copyWith(requestOptions: options);
  }

  @override
  void close({bool force = false}) {}
}
