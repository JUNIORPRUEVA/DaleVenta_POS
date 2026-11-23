import 'dart:convert';
import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/offline_login.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/config/uat_identity.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native encrypted credentials survive a local HTTP outage and locking',
    (tester) async {
      expect(
        UatIdentity.isUat,
        isTrue,
        reason: 'Never run this fixture in the production storage namespace',
      );
      await tester.runAsync(() async {
        final stamp = DateTime.now().microsecondsSinceEpoch.toString();
        final user = UserModel(
          id: 'native-$stamp',
          companyId: 'native-company-$stamp',
          email: 'native-$stamp@example.test',
          nombreCompleto: 'Prueba local',
          telefono: '',
          role: 'CAJERO',
        );
        final password = 'native-fixture-$stamp';
        final access =
            'fixture.${base64Url.encode(utf8.encode(jsonEncode({'sub': user.id, 'companyId': user.companyId, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.fixture';
        var offline = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          if (offline) {
            request.response.statusCode = 503;
            request.response.write('{}');
          } else if (request.uri.path == '/auth/login') {
            final input = jsonDecode(body) as Map;
            final valid =
                input['email'] == user.email && input['password'] == password;
            request.response.statusCode = valid ? 200 : 401;
            request.response.write(
              jsonEncode(
                valid
                    ? {
                        'accessToken': access,
                        'refreshToken': 'native-refresh-$stamp',
                        'user': user.toJson(),
                      }
                    : {'message': 'Invalid credentials'},
              ),
            );
          } else if (request.uri.path == '/users/me') {
            request.response.write(jsonEncode(user.toJson()));
          } else if (request.uri.path == '/auth/offline-emergency/authorize') {
            final now = DateTime.now().toUtc();
            request.response.write(
              jsonEncode({
                'authorized': true,
                'policyVersion': OfflineEmergencyPolicy.policyVersion,
                'companyId': user.companyId,
                'userId': user.id,
                'deviceFingerprint': request.headers.value(
                  'x-client-device-id',
                ),
                'serverUtc': now.toIso8601String(),
                'validUntilUtc': now
                    .add(const Duration(hours: 48))
                    .toIso8601String(),
              }),
            );
          } else {
            request.response.statusCode = 404;
            request.response.write('{}');
          }
          await request.response.close();
        });
        final url = 'http://127.0.0.1:${server.port}';
        final storage = TokenStorage();
        // Preserve any pre-existing UAT identity on a desktop test machine.
        // Production keys use a different namespace and are never cleared here.
        final previousAccess = await storage.getAccessToken();
        final previousRefresh = await storage.getRefreshToken();
        final previousUser = await storage.getUserSnapshot();
        final events = AuthSessionEvents();
        final dio = Dio(
          BaseOptions(baseUrl: url, connectTimeout: const Duration(seconds: 2)),
        );
        dio.interceptors.add(AuthInterceptor(storage, events, dio));
        final local = OfflineLogin(server: url);
        final repository = AuthRepository(
          dio: dio,
          storage: storage,
          offlineLogin: local,
        );
        try {
          expect((await repository.login(user.email, password)).id, user.id);
          OfflineLoginSession? prepared;
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (prepared == null && DateTime.now().isBefore(deadline)) {
            try {
              prepared = await local.unlock(user.email, password);
            } on ApiException {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
          expect(
            prepared?.user.id,
            user.id,
            reason: 'Online login must prepare encrypted native access',
          );
          await repository.prepareLocalLock();
          await storage.clearTokens();
          offline = true;
          final freshStorage = TokenStorage();
          final reopened = AuthRepository(
            dio: dio,
            storage: freshStorage,
            offlineLogin: OfflineLogin(server: url),
          );
          final restored = await reopened.login(user.email, password);
          expect(restored.companyId, user.companyId);
          expect((await freshStorage.getUserSnapshot())?.id, user.id);
          await expectLater(
            reopened.login(user.email, 'incorrect-$stamp'),
            throwsA(isA<ApiException>()),
          );
          expect((await freshStorage.getUserSnapshot())?.id, user.id);
          await reopened.forgetLocalAccess();
          await freshStorage.clearTokens();
          await expectLater(
            reopened.login(user.email, password),
            throwsA(isA<ApiException>()),
          );
        } finally {
          await local.forget(user.email);
          await storage.clearTokens();
          if ((previousAccess ?? '').isNotEmpty ||
              (previousRefresh ?? '').isNotEmpty) {
            await storage.saveTokens(previousAccess ?? '', previousRefresh);
          }
          if (previousUser != null) {
            await storage.saveUserSnapshot(previousUser);
          }
          dio.close(force: true);
          events.dispose();
          await server.close(force: true);
        }
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Prueba local de acceso completada. Sin datos productivos.',
              ),
            ),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
