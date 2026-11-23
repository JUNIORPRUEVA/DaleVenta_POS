import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:daleventa_pos/core/auth/offline_login.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySecure extends SerializedSecureStorage {
  final values = <String, String>{};
  bool fail = false;
  bool failDelete = false;
  @override
  Future<String?> read({required String key}) async {
    if (fail) throw StateError('Storage unavailable');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (fail) throw StateError('Storage unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    if (failDelete) throw StateError('Native deletion unavailable');
    values.remove(key);
  }
}

class MemorySeal implements OfflineEmergencySealStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

String token(String user, String company) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'companyId': company}))).replaceAll('=', '')}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late MemorySecure secure;
  late OfflineEmergencyPolicy policy;
  late String device;

  OfflineLogin create({
    String server = 'https://local.example/api',
    bool enabled = true,
  }) => OfflineLogin(
    server: server,
    storage: secure,
    policy: policy,
    deviceId: () async => device,
    now: () => now,
    enabled: enabled,
    // Scope/race tests use a fast double; the separate test below uses real PBKDF2.
    derive: (password, salt) async =>
        sha256.convert([...salt, ...utf8.encode(password)]).bytes,
  );

  Future<void> enroll(String id, String company, {bool current = true}) async {
    final user = UserModel(
      id: id,
      companyId: company,
      email: '$id@example.test',
      nombreCompleto: id,
      telefono: '',
      role: 'CAJERO',
    );
    await policy.recordServerValidation(
      companyId: company,
      userId: id,
      deviceFingerprint: device,
      serverUtc: now,
      observedAtUtc: now,
    );
    await create().enroll(
      email: user.email,
      password: 'local-fixture-password',
      session: OfflineLoginSession(
        user,
        token(id, company),
        'local-fixture-refresh',
      ),
      stillCurrent: () async => current,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 22, 12);
    device = 'device-a';
    secure = MemorySecure();
    policy = OfflineEmergencyPolicy(sealStore: MemorySeal());
  });

  test('real PBKDF2 produces a stable salted 256-bit verifier', () async {
    final salt = List<int>.generate(32, (i) => i);
    final first = await OfflineLogin.deriveVerifier(
      'local-fixture-password',
      salt,
    );
    final second = await OfflineLogin.deriveVerifier(
      'local-fixture-password',
      salt,
    );
    expect(first, second);
    expect(first.length, 32);
    expect(
      first,
      isNot(sha256.convert(utf8.encode('local-fixture-password')).bytes),
    );
  });

  test(
    'two companies and two users retain independent encrypted profiles',
    () async {
      await enroll('alice', 'company-a');
      await enroll('bob', 'company-b');
      final a = await create().unlock(
        ' ALICE@example.test ',
        'local-fixture-password',
      );
      final b = await create().unlock(
        'bob@example.test',
        'local-fixture-password',
      );
      expect(a.user.companyId, 'company-a');
      expect(b.user.companyId, 'company-b');
      expect(a.accessToken, isNot(b.accessToken));
      expect(secure.values.length, 2);
      expect(
        secure.values.values.join(),
        isNot(contains('local-fixture-password')),
      );
    },
  );

  test('unknown user and first access cannot authenticate locally', () async {
    await expectLater(
      create().unlock('new@example.test', 'anything'),
      throwsA(isA<ApiException>()),
    );
  });

  test('wrong password blocks and throttles repeated attempts', () async {
    await enroll('alice', 'company-a');
    for (var i = 0; i < 5; i++) {
      await expectLater(
        create().unlock('alice@example.test', 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.displayCode,
            'code',
            'LOCAL_LOGIN_INVALID',
          ),
        ),
      );
    }
    await expectLater(
      create().unlock('alice@example.test', 'local-fixture-password'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.displayCode,
          'code',
          'LOCAL_LOGIN_THROTTLED',
        ),
      ),
    );
    now = now.add(const Duration(minutes: 6));
    expect(
      (await create().unlock(
        'alice@example.test',
        'local-fixture-password',
      )).user.id,
      'alice',
    );
  });

  test('another device or backend cannot reuse a profile', () async {
    await enroll('alice', 'company-a');
    device = 'device-b';
    await expectLater(
      create().unlock('alice@example.test', 'local-fixture-password'),
      throwsA(isA<ApiException>()),
    );
    device = 'device-a';
    await expectLater(
      create(
        server: 'https://other.example/api',
      ).unlock('alice@example.test', 'local-fixture-password'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'expiry is not extended by unlocking or renewing the sales permit',
    () async {
      await enroll('alice', 'company-a');
      now = now.add(const Duration(hours: 47));
      await create().unlock('alice@example.test', 'local-fixture-password');
      await policy.recordServerValidation(
        companyId: 'company-a',
        userId: 'alice',
        deviceFingerprint: device,
        serverUtc: now,
        observedAtUtc: now,
      );
      now = now.add(const Duration(hours: 2));
      await expectLater(
        create().unlock('alice@example.test', 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'an existing server/device clock offset does not invalidate a fresh grant',
    () async {
      final user = UserModel(
        id: 'alice',
        companyId: 'company-a',
        email: 'alice@example.test',
        nombreCompleto: 'Alice',
        telefono: '',
        role: 'CAJERO',
      );
      await policy.recordServerValidation(
        companyId: 'company-a',
        userId: 'alice',
        deviceFingerprint: device,
        serverUtc: now.subtract(const Duration(days: 3)),
        observedAtUtc: now,
      );
      await create().enroll(
        email: user.email,
        password: 'local-fixture-password',
        session: OfflineLoginSession(
          user,
          token('alice', 'company-a'),
          'local-fixture-refresh',
        ),
        stillCurrent: () async => true,
      );
      expect(
        (await create().unlock(user.email, 'local-fixture-password')).user.id,
        'alice',
      );
      now = now.add(const Duration(hours: 49));
      await expectLater(
        create().unlock(user.email, 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('clock rollback blocks access', () async {
    await enroll('alice', 'company-a');
    now = now.subtract(const Duration(hours: 1));
    await expectLater(
      create().unlock('alice@example.test', 'local-fixture-password'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'a late enrollment after logout does not recreate the profile',
    () async {
      await enroll('alice', 'company-a', current: false);
      expect(secure.values, isEmpty);
    },
  );

  test(
    'forget only removes the selected account, not the other company',
    () async {
      await enroll('alice', 'company-a');
      await enroll('bob', 'company-b');
      await create().forget('alice@example.test');
      await expectLater(
        create().unlock('alice@example.test', 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
      expect(
        (await create().unlock(
          'bob@example.test',
          'local-fixture-password',
        )).user.id,
        'bob',
      );
    },
  );

  test('corrupt token cannot impersonate another company', () async {
    await enroll('alice', 'company-a');
    final key = secure.values.keys.single;
    final data = jsonDecode(secure.values[key]!) as Map<String, dynamic>;
    data['access'] = token('alice', 'company-b');
    secure.values[key] = jsonEncode(data);
    await expectLater(
      create().unlock('alice@example.test', 'local-fixture-password'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'web/unsupported platform does not store or accept credentials',
    () async {
      await enroll('alice', 'company-a');
      await expectLater(
        create(
          enabled: false,
        ).unlock('alice@example.test', 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('observed permission downgrade retires the profile', () async {
    await enroll('alice', 'company-a');
    final user = UserModel(
      id: 'alice',
      companyId: 'company-a',
      email: 'alice@example.test',
      nombreCompleto: 'Alice',
      telefono: '',
      role: 'VENDEDOR',
    );
    await create().observeSession(
      OfflineLoginSession(
        user,
        token('alice', 'company-a'),
        'new-fixture-refresh',
      ),
    );
    expect(secure.values.keys, isEmpty);
  });

  test(
    'refresh updates tokens without extending the offline deadline',
    () async {
      await enroll('alice', 'company-a');
      final previous = jsonDecode(secure.values.values.single) as Map;
      final current = UserModel.fromJson(
        (previous['user'] as Map).cast<String, dynamic>(),
      );
      now = now.add(const Duration(hours: 1));
      await create().observeSession(
        OfflineLoginSession(
          current,
          token('alice', 'company-a'),
          'renewed-fixture-refresh',
        ),
      );
      final updated = jsonDecode(secure.values.values.single) as Map;
      expect(updated['validatedAt'], previous['validatedAt']);
      expect(
        (await create().unlock(
          current.email,
          'local-fixture-password',
        )).refreshToken,
        'renewed-fixture-refresh',
      );
    },
  );

  test('unavailable secure storage never falls back to preferences', () async {
    await enroll('alice', 'company-a');
    secure.fail = true;
    await expectLater(
      create().unlock('alice@example.test', 'local-fixture-password'),
      throwsA(anything),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => k.startsWith('offline_login.')), isFalse);
  });

  test(
    'revocation remains effective when native credential deletion fails',
    () async {
      await enroll('alice', 'company-a');
      secure.failDelete = true;
      await expectLater(
        create().forget('alice@example.test'),
        throwsA(isA<StateError>()),
      );
      expect(secure.values.keys, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().any(
          (key) =>
              key.startsWith('offline_login_revoked.') &&
              prefs.getBool(key) == true,
        ),
        isTrue,
      );
      await expectLater(
        create().unlock('alice@example.test', 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'a snapshot already marked blocked cannot authenticate locally',
    () async {
      await enroll('alice', 'company-a');
      final key = secure.values.keys.single;
      final data = jsonDecode(secure.values[key]!) as Map<String, dynamic>;
      (data['user'] as Map)['blocked'] = true;
      secure.values[key] = jsonEncode(data);
      await expectLater(
        create().unlock('alice@example.test', 'local-fixture-password'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
