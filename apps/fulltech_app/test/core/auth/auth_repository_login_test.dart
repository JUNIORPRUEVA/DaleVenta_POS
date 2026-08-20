import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
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

  test('no inventa companyId cuando ninguna fuente lo entrega', () async {
    final user = await _loginWith();

    expect(user.companyId, isNull);
  });
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

  return AuthRepository(dio: dio, storage: storage).login(
    'user@example.test',
    'password-for-test',
  );
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

String _jwt(String? companyId) {
  final payload = <String, dynamic>{if (companyId != null) 'companyId': companyId};
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode(payload)}.';
}

class _FakeTokenStorage extends TokenStorage {
  @override
  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {}

  @override
  Future<void> saveUserSnapshot(UserModel user) async {}
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
