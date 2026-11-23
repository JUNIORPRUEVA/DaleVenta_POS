import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/offline_login.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_login_http_test.dart' show ActiveSession;
import 'offline_login_test.dart' show MemorySecure, MemorySeal, token;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final invalidGrants = <String, Map<String, dynamic>>{
    'explicit denial': {'authorized': false},
    'other company': {'companyId': 'company-b'},
    'other user': {'userId': 'bob'},
    'other device': {'deviceFingerprint': 'device-b'},
    'unknown policy': {'policyVersion': 'unsupported'},
    'missing date': {'serverUtc': null},
    'invalid date': {'validUntilUtc': 'invalid'},
    'inverted dates': {'validUntilUtc': '2000-01-01T00:00:00Z'},
    'excessive validity': {'validUntilUtc': '2099-01-01T00:00:00Z'},
  };

  for (final entry in invalidGrants.entries) {
    test('new ${entry.key} cannot enroll from an older valid grant', () async {
      SharedPreferences.setMockInitialValues({
        'daleventas.usage.device_id.v1': 'device-a',
      });
      final now = DateTime.now().toUtc();
      final user = UserModel(
        id: 'alice',
        companyId: 'company-a',
        email: 'alice@example.test',
        nombreCompleto: 'Alice',
        telefono: '',
        role: 'CAJERO',
      );
      final policy = OfflineEmergencyPolicy(sealStore: MemorySeal());
      await policy.recordServerValidation(
        companyId: 'company-a',
        userId: 'alice',
        deviceFingerprint: 'device-a',
        serverUtc: now,
        observedAtUtc: now,
      );
      final secure = MemorySecure();
      var derivations = 0;
      final local = OfflineLogin(
        server: 'http://127.0.0.1',
        storage: secure,
        policy: policy,
        deviceId: () async => 'device-a',
        enabled: true,
        derive: (password, salt) async {
          derivations++;
          return List<int>.filled(32, 1);
        },
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1'));
      final responseSent = Completer<void>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final isGrant = options.path.endsWith('/authorize');
            final data = options.path.endsWith('/auth/login')
                ? {
                    'accessToken': token('alice', 'company-a'),
                    'refreshToken': 'fixture-refresh',
                    'user': user.toJson(),
                  }
                : options.path.endsWith('/users/me')
                ? user.toJson()
                : {
                    'authorized': true,
                    'policyVersion': OfflineEmergencyPolicy.policyVersion,
                    'companyId': user.companyId,
                    'userId': user.id,
                    'deviceFingerprint': 'device-a',
                    'serverUtc': now.toIso8601String(),
                    'validUntilUtc': now
                        .add(const Duration(hours: 2))
                        .toIso8601String(),
                    ...entry.value,
                  };
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
            if (isGrant && !responseSent.isCompleted) responseSent.complete();
          },
        ),
      );
      final storage = ActiveSession();
      final repository = AuthRepository(
        dio: dio,
        storage: storage,
        offlineLogin: local,
      );
      try {
        expect(
          (await repository.login(user.email, 'fixture-only')).id,
          user.id,
        );
        await responseSent.future.timeout(const Duration(seconds: 5));
        // Drain the background grant continuation; no real KDF is scheduled.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(derivations, 0);
        expect(secure.values.length, 0);
        expect(storage.user?.id, user.id); // Online access remains usable.
      } finally {
        dio.close(force: true);
      }
    });
  }
}
