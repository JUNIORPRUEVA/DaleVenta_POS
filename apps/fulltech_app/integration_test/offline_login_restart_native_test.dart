import 'dart:convert';

import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/offline_login.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/config/uat_identity.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run as three separate processes: prepare, verify, revoked. The harness may
/// reboot the dedicated Android QA emulator between prepare and verify.
/// Only synthetic identity and UAT-prefixed credentials are used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('OFFLINE_RESTART_PHASE');
  const run = String.fromEnvironment('OFFLINE_RESTART_RUN');
  testWidgets(
    'native restart persistence: $phase',
    (tester) async {
      expect(UatIdentity.isUat, isTrue);
      expect(run.length, greaterThan(10));
      expect(['prepare', 'verify', 'revoked'], contains(phase));
      await tester.runAsync(() async {
        // Port 1 is deliberately unavailable: no remote API or business data.
        const server = 'http://127.0.0.1:1';
        final user = UserModel(
          id: 'restart-$run',
          companyId: 'restart-company-$run',
          email: 'restart-$run@example.test',
          nombreCompleto: 'Prueba de reinicio aislada',
          telefono: '',
          role: 'CAJERO',
        );
        final secret = base64Url.encode(utf8.encode('synthetic-only:$run'));
        final local = OfflineLogin(server: server);
        if (phase == 'prepare') {
          final headers = await ClientTelemetryHeaders.instance.headers();
          final device = headers['x-client-device-id'];
          expect(device, isNotEmpty);
          final now = DateTime.now().toUtc();
          final accepted = await OfflineEmergencyPolicy()
              .recordAuthorizationResponse(
                data: {
                  'authorized': true,
                  'policyVersion': OfflineEmergencyPolicy.policyVersion,
                  'companyId': user.companyId,
                  'userId': user.id,
                  'deviceFingerprint': device,
                  'serverUtc': now.toIso8601String(),
                  'validUntilUtc': now
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                },
                companyId: user.companyId!,
                userId: user.id,
                deviceFingerprint: device!,
              );
          expect(accepted, isTrue);
          final payload = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({'sub': user.id, 'companyId': user.companyId}),
                ),
              )
              .replaceAll('=', '');
          await local.enroll(
            email: user.email,
            password: secret,
            session: OfflineLoginSession(
              user,
              'fixture.$payload.fixture',
              'synthetic-refresh-$run',
            ),
            stillCurrent: () async => true,
          );
          expect((await local.unlock(user.email, secret)).user.id, user.id);
        } else if (phase == 'verify') {
          // This isolate/process has never enrolled a profile. Read the persisted
          // encrypted credential and sealed grant with networking unavailable.
          await expectLater(
            local.unlock(user.email, '$secret-invalid'),
            throwsA(isA<ApiException>()),
          );
          final restored = await local.unlock(user.email, secret);
          expect(restored.user.id, user.id);
          expect(restored.user.companyId, user.companyId);
          await expectLater(
            local.unlock('other-$run@example.test', secret),
            throwsA(isA<ApiException>()),
          );

          // Repository path also fails over from a real loopback connection
          // refusal. Restore any existing UAT active identity afterwards.
          final storage = TokenStorage();
          final access = await storage.getAccessToken();
          final refresh = await storage.getRefreshToken();
          final previous = await storage.getUserSnapshot();
          final dio = Dio(
            BaseOptions(
              baseUrl: server,
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
            ),
          );
          try {
            final repository = AuthRepository(
              dio: dio,
              storage: storage,
              offlineLogin: local,
            );
            expect((await repository.login(user.email, secret)).id, user.id);
            expect(
              (await storage.getUserSnapshot())?.companyId,
              user.companyId,
            );
            await repository.forgetLocalAccess();
            await expectLater(
              local.unlock(user.email, secret),
              throwsA(isA<ApiException>()),
            );
          } finally {
            await storage.clearTokens();
            if ((access ?? '').isNotEmpty || (refresh ?? '').isNotEmpty) {
              await storage.saveTokens(access ?? '', refresh);
            }
            if (previous != null) await storage.saveUserSnapshot(previous);
            dio.close(force: true);
          }
        } else {
          // Revocation must remain effective in a third independent process.
          await expectLater(
            local.unlock(user.email, secret),
            throwsA(isA<ApiException>()),
          );
        }
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Prueba aislada de persistencia')),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
