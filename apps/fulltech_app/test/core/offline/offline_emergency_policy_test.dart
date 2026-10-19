import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('blocks when there is no trusted server validation', () async {
    final policy = OfflineEmergencyPolicy();

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: DateTime.utc(2026, 10, 13, 12),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, OfflineEmergencyBlockReason.missingValidation);
  });

  test('allows within 48 hours after a server Date validation', () async {
    final policy = OfflineEmergencyPolicy();
    final observedAt = DateTime.utc(2026, 10, 13, 12);
    final headers = Headers.fromMap({
      OfflineEmergencyPolicy.serverDateHeader: [formatHttpDate(observedAt)],
    });

    await policy.recordServerValidationFromHeaders(
      headers: headers,
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      observedAtUtc: observedAt,
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: observedAt.add(const Duration(hours: 47, minutes: 59)),
    );

    expect(decision.allowed, isTrue);
    expect(decision.lastServerValidationUtc, observedAt);
  });

  test('blocks new offline sales after 48 hours', () async {
    final policy = OfflineEmergencyPolicy();
    final observedAt = DateTime.utc(2026, 10, 13, 12);

    await policy.recordServerValidation(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      serverUtc: observedAt,
      observedAtUtc: observedAt,
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: observedAt.add(const Duration(hours: 48, minutes: 1)),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, OfflineEmergencyBlockReason.expired);
  });

  test(
    'blocks when the device clock rolls back before validation time',
    () async {
      final policy = OfflineEmergencyPolicy();
      final observedAt = DateTime.utc(2026, 10, 13, 12);

      await policy.recordServerValidation(
        companyId: 'company-1',
        userId: 'user-1',
        deviceFingerprint: 'device-1',
        serverUtc: observedAt,
        observedAtUtc: observedAt,
      );

      final decision = await policy.canStartOfflineSale(
        companyId: 'company-1',
        userId: 'user-1',
        deviceFingerprint: 'device-1',
        nowUtc: observedAt.subtract(const Duration(minutes: 6)),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, OfflineEmergencyBlockReason.clockRollback);
    },
  );

  test('blocks when stored authorization belongs to another device', () async {
    final policy = OfflineEmergencyPolicy();
    final observedAt = DateTime.utc(2026, 10, 13, 12);

    await policy.recordServerValidation(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      serverUtc: observedAt,
      observedAtUtc: observedAt,
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-2',
      nowUtc: observedAt.add(const Duration(hours: 1)),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, OfflineEmergencyBlockReason.missingValidation);
  });

  test('records only matching dedicated authorization responses', () async {
    final policy = OfflineEmergencyPolicy();
    final observedAt = DateTime.utc(2026, 10, 13, 12);

    await policy.recordAuthorizationResponse(
      data: {
        'authorized': true,
        'policyVersion': OfflineEmergencyPolicy.policyVersion,
        'companyId': 'company-1',
        'userId': 'user-1',
        'deviceFingerprint': 'device-1',
        'serverUtc': observedAt.toIso8601String(),
        'validUntilUtc': observedAt
            .add(const Duration(hours: 48))
            .toIso8601String(),
      },
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      observedAtUtc: observedAt,
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: observedAt.add(const Duration(hours: 1)),
    );

    expect(decision.allowed, isTrue);
  });

  test('blocks tampered local authorization when a secure seal exists', () async {
    final prefs = await SharedPreferences.getInstance();
    final sealStore = _MemorySealStore();
    final policy = OfflineEmergencyPolicy(sealStore: sealStore);
    final observedAt = DateTime.utc(2026, 10, 13, 12);

    await policy.recordServerValidation(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      serverUtc: observedAt,
      observedAtUtc: observedAt,
    );
    await prefs.setString(
      'offline_emergency.v1.company:company-1.user:user-1',
      '{"policyVersion":"offline-safe-48h.v1","companyId":"company-1","userId":"user-1","deviceFingerprint":"device-1","serverUtc":"2026-10-13T12:00:00.000Z","validUntilUtc":"2026-10-20T12:00:00.000Z","observedDeviceUtc":"2026-10-13T12:00:00.000Z"}',
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: observedAt.add(const Duration(hours: 1)),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, OfflineEmergencyBlockReason.corruptedValidation);
  });

  test('ignores authorization responses longer than 48 hours', () async {
    final policy = OfflineEmergencyPolicy();
    final observedAt = DateTime.utc(2026, 10, 13, 12);

    await policy.recordAuthorizationResponse(
      data: {
        'authorized': true,
        'policyVersion': OfflineEmergencyPolicy.policyVersion,
        'companyId': 'company-1',
        'userId': 'user-1',
        'deviceFingerprint': 'device-1',
        'serverUtc': observedAt.toIso8601String(),
        'validUntilUtc': observedAt
            .add(const Duration(hours: 48, seconds: 1))
            .toIso8601String(),
      },
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      observedAtUtc: observedAt,
    );

    final decision = await policy.canStartOfflineSale(
      companyId: 'company-1',
      userId: 'user-1',
      deviceFingerprint: 'device-1',
      nowUtc: observedAt.add(const Duration(hours: 1)),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, OfflineEmergencyBlockReason.missingValidation);
  });
}

class _MemorySealStore implements OfflineEmergencySealStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
