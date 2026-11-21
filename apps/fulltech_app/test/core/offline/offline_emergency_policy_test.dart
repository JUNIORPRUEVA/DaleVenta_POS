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

  test(
    'offline opening receipt is scoped to the authorized owner and device',
    () async {
      final policy = OfflineEmergencyPolicy(sealStore: _MemorySealStore());
      final at = DateTime.utc(2026, 11, 20, 12);
      await policy.recordServerValidation(
        companyId: 'company-1',
        userId: 'user-1',
        deviceFingerprint: 'device-1',
        serverUtc: at,
        observedAtUtc: at,
        allowedOperations: ['sales.create', 'cash.open'],
        cashOpenPermit: 'signed-receipt',
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          openedAt: at.add(const Duration(minutes: 10)),
        ),
        'signed-receipt',
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-2',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          openedAt: at,
        ),
        isNull,
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-1',
          userId: 'user-2',
          deviceFingerprint: 'device-1',
          openedAt: at,
        ),
        isNull,
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-2',
          openedAt: at,
        ),
        isNull,
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          openedAt: at.add(const Duration(hours: 49)),
        ),
        isNull,
      );
    },
  );

  test(
    'a sales-only authorization cannot grant an offline cash opening',
    () async {
      final policy = OfflineEmergencyPolicy(sealStore: _MemorySealStore());
      final at = DateTime.utc(2026, 11, 20, 12);
      await policy.recordServerValidation(
        companyId: 'company-1',
        userId: 'user-1',
        deviceFingerprint: 'device-1',
        serverUtc: at,
        observedAtUtc: at,
        cashOpenPermit: 'signed-receipt',
      );
      expect(
        await policy.cashOpeningPermit(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          openedAt: at,
        ),
        isNull,
      );
    },
  );

  for (final offset in [-400, 400]) {
    test(
      'cash opening uses sealed server time with device offset ${offset}ms',
      () async {
        final policy = OfflineEmergencyPolicy(sealStore: _MemorySealStore());
        final server = DateTime.utc(2026, 11, 20, 12);
        final observed = server.add(Duration(milliseconds: offset));
        await policy.recordServerValidation(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          serverUtc: server,
          observedAtUtc: observed,
          allowedOperations: ['sales.create', 'cash.open'],
          cashOpenPermit: 'signed-receipt',
        );
        final opening = await policy.cashOpeningAuthorization(
          companyId: 'company-1',
          userId: 'user-1',
          deviceFingerprint: 'device-1',
          deviceOpenedAt: observed.add(const Duration(milliseconds: 50)),
        );
        expect(opening?.permit, 'signed-receipt');
        expect(opening?.openedAt, server.add(const Duration(milliseconds: 50)));
        expect(
          await policy.cashOpeningAuthorization(
            companyId: 'company-1',
            userId: 'user-1',
            deviceFingerprint: 'device-1',
            deviceOpenedAt: observed.subtract(const Duration(minutes: 6)),
          ),
          isNull,
        );
      },
    );
  }

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
