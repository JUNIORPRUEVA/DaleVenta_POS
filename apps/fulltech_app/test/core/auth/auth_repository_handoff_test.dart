import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/operation_scope.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

String token(String user, String company) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'sub': user, 'companyId': company,
  }))).replaceAll('=', '');
  return 'eyJhbGciOiJub25lIn0.$payload.';
}

Map<String, dynamic> session({String user = 'new-user', String company = 'new-company'}) => {
  'accessToken': token(user, company), 'refreshToken': 'fixture-refresh',
  'user': {'id': user, 'email': 'qa@example.invalid', 'nombreCompleto': 'QA',
    'telefono': '', 'role': 'OWNER', 'companyId': company},
  'requiresOnboarding': true,
};

class Storage extends TokenStorage {
  final writes = <String>[];
  UserModel? user;
  String? access;
  @override
  Future<void> clearTokens() async { writes.add('clear'); access = null; user = null; }
  @override
  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    writes.add('tokens'); access = accessToken;
  }
  @override
  Future<void> saveUserSnapshot(UserModel value) async { writes.add('user'); user = value; }
  @override
  Future<String?> getAccessToken() async => throw StateError('Must not read old identity');
}

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  Future<void>? cancelled;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancelFuture) {
    requests.add(options); cancelled = cancelFuture;
    return respond(options);
  }
  @override
  void close({bool force = false}) {}
}

ResponseBody body(Map<String, dynamic> data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(data), status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authoritative handoff enters directly, preserving company and onboarding', () async {
    final storage = Storage();
    final adapter = Adapter((_) async => body(session()));
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = adapter;
    final user = await AuthRepository(dio: dio, storage: storage).exchangeHandoffTicket('fixture');
    expect(user.id, 'new-user'); expect(user.companyId, 'new-company');
    expect(user.requiresOnboarding, true);
    expect(adapter.requests.map((r) => r.path), [ApiRoutes.handoffExchange]);
    expect(adapter.requests.single.extra['disableRetry'], true);
    expect(storage.writes, ['clear', 'tokens', 'user']);
  });

  for (final failure in ['wrong-user', 'wrong-company', 'missing-user', 'missing-refresh']) {
    test('$failure cannot persist a partial or cross-company session', () async {
      final data = session();
      if (failure == 'wrong-user') data['accessToken'] = token('other-user', 'new-company');
      if (failure == 'wrong-company') data['accessToken'] = token('new-user', 'other-company');
      if (failure == 'missing-user') data.remove('user');
      if (failure == 'missing-refresh') data.remove('refreshToken');
      final storage = Storage();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = Adapter((_) async => body(data));
      await expectLater(AuthRepository(dio: dio, storage: storage).exchangeHandoffTicket('fixture'), throwsA(anything));
      expect(storage.writes, isEmpty);
    });
  }

  test('deadline cancels transport and ignores a late successful exchange', () async {
    final late = Completer<ResponseBody>();
    final adapter = Adapter((_) => late.future);
    final storage = Storage();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = adapter;
    await expectLater(AuthRepository(dio: dio, storage: storage).exchangeHandoffTicket(
      'fixture', timeout: const Duration(milliseconds: 30)), throwsA(isA<TimeoutException>()));
    await adapter.cancelled;
    late.complete(body(session()));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(storage.writes, isEmpty);
    expect(adapter.requests.length, 1);
  });

  test('handoff skips previous tenant token and never refreshes a rejected ticket', () async {
    final storage = Storage();
    final adapter = Adapter((options) async {
      expect(options.headers['Authorization'], isNull);
      return body({'message': 'Invalid ticket'}, 401);
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))..httpClientAdapter = adapter;
    final events = AuthSessionEvents();
    dio.interceptors.add(AuthInterceptor(storage, events, dio));
    await expectLater(OperationScope('previous-company', 'previous-user').run(() =>
      AuthRepository(dio: dio, storage: storage).exchangeHandoffTicket('fixture')), throwsA(isA<DioException>()));
    expect(adapter.requests.length, 1);
    expect(storage.writes, isEmpty);
  });
}
