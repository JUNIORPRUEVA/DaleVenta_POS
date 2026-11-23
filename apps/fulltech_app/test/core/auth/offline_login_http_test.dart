import 'dart:convert';
import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/offline_login.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_login_test.dart' show MemorySecure, MemorySeal, token;

class ActiveSession extends TokenStorage {
  String? access;
  String? refresh;
  UserModel? user;
  int clears = 0;
  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<UserModel?> getUserSnapshot() async => user;
  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
    user = null;
    clears++;
  }

  @override
  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> saveUserSnapshot(UserModel value) async {
    user = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttp = HttpOverrides.current;
  // Only this local suite opts out of Flutter's synthetic HTTP-400 override.
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = previousHttp);
  late HttpServer server;
  late Dio dio;
  late int loginStatus;
  late int meStatus;
  late bool wrongCompany;
  late ActiveSession active;
  late OfflineLogin local;
  late MemorySecure secure;
  late AuthSessionEvents events;
  late String candidateHeader;
  final at = DateTime.now().toUtc();
  final alice = UserModel(
    id: 'alice',
    companyId: 'company-a',
    email: 'alice@example.test',
    nombreCompleto: 'Alice',
    telefono: '',
    role: 'CAJERO',
  );
  final bob = UserModel(
    id: 'bob',
    companyId: 'company-b',
    email: 'bob@example.test',
    nombreCompleto: 'Bob',
    telefono: '',
    role: 'ADMIN',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'daleventas.usage.device_id.v1': 'device-a',
    });
    loginStatus = 503;
    meStatus = 200;
    wrongCompany = false;
    candidateHeader = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/auth/login') {
        req.response.statusCode = loginStatus;
        req.response.write(
          jsonEncode(
            loginStatus == 200
                ? {
                    'accessToken': token('alice', 'company-a'),
                    'refreshToken': 'local-test-refresh',
                    'user': alice.toJson(),
                  }
                : {'message': 'Controlled test response'},
          ),
        );
      } else if (req.uri.path == '/users/me') {
        candidateHeader = req.headers.value('authorization') ?? '';
        req.response.statusCode = meStatus;
        req.response.write(
          jsonEncode({
            ...alice.toJson(),
            if (wrongCompany) 'companyId': 'company-b',
          }),
        );
      } else {
        req.response.statusCode = 503;
        req.response.write('{}');
      }
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    dio = Dio(
      BaseOptions(baseUrl: base, connectTimeout: const Duration(seconds: 1)),
    );
    active = ActiveSession()
      ..access = token('bob', 'company-b')
      ..refresh = 'bob-test-refresh'
      ..user = bob;
    events = AuthSessionEvents();
    dio.interceptors.add(AuthInterceptor(active, events, dio));
    secure = MemorySecure();
    final policy = OfflineEmergencyPolicy(sealStore: MemorySeal());
    await policy.recordServerValidation(
      companyId: 'company-a',
      userId: 'alice',
      deviceFingerprint: 'device-a',
      serverUtc: at,
      observedAtUtc: at,
    );
    local = OfflineLogin(
      server: base,
      storage: secure,
      policy: policy,
      deviceId: () async => 'device-a',
      now: () => at,
      enabled: true,
    );
    await local.enroll(
      email: alice.email,
      password: 'local-fixture-password',
      session: OfflineLoginSession(
        alice,
        token('alice', 'company-a'),
        'local-test-refresh',
      ),
      stillCurrent: () async => true,
    );
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
    events.dispose();
  });

  AuthRepository repository() =>
      AuthRepository(dio: dio, storage: active, offlineLogin: local);

  test(
    'real local HTTP outage uses password verification and switches only to its own company',
    () async {
      final user = await repository().login(
        alice.email,
        'local-fixture-password',
      );
      expect(user.companyId, 'company-a');
      expect(active.user?.id, 'alice');
      expect(active.access, token('alice', 'company-a'));
      expect(events.unauthorizedLogoutRequested, isFalse);
    },
  );

  test(
    'outage with wrong password preserves the previous durable identity',
    () async {
      await expectLater(
        repository().login(alice.email, 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(active.user?.id, 'bob');
      expect(active.access, token('bob', 'company-b'));
      expect(active.clears, 0);
    },
  );

  for (final status in [401, 403]) {
    test(
      'HTTP $status never falls back to local credentials and revokes that profile only',
      () async {
        loginStatus = status;
        await expectLater(
          repository().login(alice.email, 'local-fixture-password'),
          throwsA(isA<ApiException>()),
        );
        expect(active.user?.id, 'bob');
        expect(active.clears, 0);
        expect(secure.values.keys, isEmpty);
      },
    );
  }

  test(
    'candidate bearer is used before replacing the previous active identity',
    () async {
      loginStatus = 200;
      final user = await repository().login(
        alice.email,
        'local-fixture-password',
      );
      expect(candidateHeader, 'Bearer ${token('alice', 'company-a')}');
      expect(user.id, 'alice');
      expect(active.user?.companyId, 'company-a');
      expect(active.clears, 1);
      // Background authorization failure cannot retain the previous password verifier.
      expect(secure.values, isEmpty);
    },
  );

  test(
    'a 403 from candidate users/me does not log out or replace the old user',
    () async {
      loginStatus = 200;
      meStatus = 403;
      await expectLater(
        repository().login(alice.email, 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
      expect(events.unauthorizedLogoutRequested, isFalse);
      expect(active.user?.id, 'bob');
      expect(active.clears, 0);
    },
  );

  test(
    'contradictory company identity is rejected before storage changes',
    () async {
      loginStatus = 200;
      wrongCompany = true;
      await expectLater(
        repository().login(alice.email, 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
      expect(active.user?.id, 'bob');
      expect(active.clears, 0);
    },
  );

  test('TLS rejection never enables the local credential fallback', () async {
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badCertificate,
            ),
          );
        },
      ),
    );
    await expectLater(
      repository().login(alice.email, 'local-fixture-password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.type,
          'type',
          ApiErrorType.tls,
        ),
      ),
    );
    expect(active.user?.id, 'bob');
    expect(active.clears, 0);
    expect(secure.values.keys, isNotEmpty);
  });

  test(
    'concurrent login is rejected without issuing a second identity change',
    () async {
      final repo = repository();
      final first = repo.login(alice.email, 'local-fixture-password');
      await expectLater(
        repo.login(bob.email, 'anything'),
        throwsA(isA<StateError>()),
      );
      await first;
      expect(active.user?.id, 'alice');
    },
  );
}
