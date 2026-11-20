import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic API/PostgreSQL acceptance for the public foreground cash methods.
/// A real loopback proxy drops committed responses. The original authenticated
/// owner is restored afterwards; neither incidents nor credentials are deleted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native cash journal survives committed response loss without duplicate money',
    (tester) async {
      const base = String.fromEnvironment('UAT_API_BASE');
      expect(['127.0.0.1', '::1', '[::1]'], contains(Uri.parse(base).host));
      expect(Uri.parse(base).port, 4004);
      final run = DateTime.now().microsecondsSinceEpoch.toString();
      final result = <String, dynamic>{
        'platform': Platform.operatingSystem,
        'run': 'journal-$run',
        'api': base,
      };
      await tester.runAsync(() async {
        if (Platform.isWindows) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }
        final identity = TokenStorage();
        final priorUser = await identity.getUserSnapshot();
        final priorAccess = await identity.getAccessToken();
        final priorRefresh = await identity.getRefreshToken();
        expect(priorUser, isNotNull);
        expect(priorAccess, isNotEmpty);
        expect(priorRefresh, isNotEmpty);
        final store = OfflineStore.instance;
        final telemetry = await ClientTelemetryHeaders.instance.headers();
        final direct = Dio(BaseOptions(baseUrl: base, headers: telemetry));
        final transport = HttpClient()..autoUncompress = false;
        HttpServer? proxy;
        SyncQueueService? queue;
        Dio? client;
        try {
          final password = 'Synthetic-$run-Aa1!';
          final registered =
              (await direct.post(
                    '/auth/register-business',
                    data: {
                      'firstName': 'Synthetic',
                      'lastName': 'Cash Journal',
                      'email': 'cash-journal-$run@example.test',
                      'phone': '8095550303',
                      'password': password,
                      'confirmPassword': password,
                      'commercialName': 'Native Cash Journal $run',
                      'country': 'DO',
                      'currency': 'DOP',
                    },
                  )).data
                  as Map;
          final user = UserModel.fromJson(
            Map<String, dynamic>.from(registered['user'] as Map),
          );
          final token = registered['accessToken'] as String;
          await identity.saveTokens(
            token,
            registered['refreshToken'] as String,
          );
          await identity.saveUserSnapshot(user);
          direct.options.headers['authorization'] = 'Bearer $token';
          await direct.post('/onboarding/skip-all');
          final grant =
              (await direct.post(
                    '/auth/offline-emergency/authorize',
                    data: {},
                  )).data
                  as Map;
          await OfflineEmergencyPolicy().recordAuthorizationResponse(
            data: Map<String, dynamic>.from(grant),
            companyId: user.companyId!,
            userId: user.id,
            deviceFingerprint: telemetry['x-client-device-id']!,
          );
          Future<List<PendingSyncAction>> pending() => store.listPendingActions(
            companyId: user.companyId,
            userId: user.id,
            limit: null,
          );
          var lostPath = '/cash/sessions/open';
          var networkBlocked = false;
          final seen = <String>{};
          final proxyErrors = <Object>[];
          final dispatched = <Map<String, dynamic>>[];
          proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          proxy.listen((request) async {
            try {
              if (networkBlocked) {
                final socket = await request.response.detachSocket(
                  writeHeaders: false,
                );
                socket.destroy();
                return;
              }
              final bytes = await request.fold<List<int>>(
                [],
                (all, part) => all..addAll(part),
              );
              final body = jsonDecode(utf8.decode(bytes)) as Map;
              final operation =
                  (body['operationId'] ??
                          body['clientSessionId'] ??
                          body['sessionId'])
                      .toString();
              if (seen.add('${request.uri.path}:$operation')) {
                final before = await pending();
                final record = before.singleWhere(
                  (item) =>
                      item.payload['operationId'] == operation ||
                      item.payload['clientSessionId'] == operation ||
                      item.payload['sessionId'] == operation,
                );
                expect(record.status, 'requires_action');
                expect(record.permanent, isTrue);
                dispatched.add({
                  'path': request.uri.path,
                  'operationId': operation,
                  'journalBeforePost': true,
                  'occurredAt': body['occurredAt'],
                });
              }
              final outgoing = await transport.openUrl(
                request.method,
                Uri.parse(
                  base,
                ).replace(path: request.uri.path, query: request.uri.query),
              );
              request.headers.forEach((name, values) {
                if (name.toLowerCase() != 'host') {
                  outgoing.headers.set(name, values);
                }
              });
              outgoing.add(bytes);
              final response = await outgoing.close();
              if (request.uri.path == lostPath) {
                expect(response.statusCode, 201);
                lostPath = '';
                if (request.uri.path == '/cash/sessions/open') {
                  networkBlocked = true;
                }
                await response.drain<void>();
                final socket = await request.response.detachSocket(
                  writeHeaders: false,
                );
                socket.destroy();
                return;
              }
              request.response.statusCode = response.statusCode;
              response.headers.forEach((name, values) {
                if (name.toLowerCase() != 'transfer-encoding') {
                  request.response.headers.set(name, values);
                }
              });
              await request.response.addStream(response);
              await request.response.close();
            } catch (error) {
              proxyErrors.add(error);
              request.response.statusCode = 500;
              await request.response.close();
            }
          });
          queue = SyncQueueService(
            store,
            scopeResolver: () async =>
                OfflineSyncScope(companyId: user.companyId, userId: user.id),
          );
          client = Dio(
            BaseOptions(
              baseUrl: 'http://127.0.0.1:${proxy.port}',
              headers: {...telemetry, 'authorization': 'Bearer $token'},
            ),
          );
          final cash = CashRepository(
            client,
            queue,
            offlineStore: store,
            tokenStorage: identity,
          )..registerSyncHandlers();
          Future<void> settle({bool allowRetry = true}) async {
            for (var index = 0; index < 300; index++) {
              expect(proxyErrors, isEmpty);
              if (allowRetry && !queue!.state.isProcessing) {
                await queue.processPending();
              }
              final rows = await pending();
              if (!queue!.state.isProcessing &&
                  (!allowRetry ||
                      !rows.any((item) => item.isAutomaticallyRetryable))) {
                return;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            fail(
              'The native cash journal did not settle within its bounded retry window.',
            );
          }

          final opened = await cash.openSession(openingAmount: 0);
          expect(
            cash.lastStateFromCache,
            isTrue,
            reason: 'A local opening is not a confirmed server snapshot.',
          );
          await settle(allowRetry: false);
          expect(
            (await pending()).single.payload['clientSessionId'],
            opened.shiftId,
          );
          networkBlocked = false;
          await settle();
          expect(await pending(), isEmpty);
          expect(cash.lastStateFromCache, isFalse);
          lostPath = '/cash/movements';
          await cash.addMovement(
            sessionId: opened.shiftId,
            type: 'IN',
            amount: 7,
            reason: 'Synthetic committed response loss',
          );
          await settle();
          expect(await pending(), isEmpty);
          lostPath = '/cash/sessions/close';
          await expectLater(
            cash.closeSession(sessionId: opened.shiftId, closingAmount: 7),
            throwsA(isA<CashClosePendingSyncException>()),
          );
          await settle();
          final close = (await pending()).single;
          expect(close.type, 'cash.close');
          expect(close.permanent, isTrue);
          final reviews = RecoveryReviewRepository(
            direct,
            store,
            onChanged: queue.refreshStats,
            onResolved: (action, confirmed) => cash.applyReviewedOperation(
              action,
              financiallyConfirmed: confirmed,
            ),
          );
          await reviews.submit(close);
          final submitted = (await pending()).single;
          await reviews.verify(submitted.payload['recoveryReviewId'] as String);
          final retained = (await pending()).single;
          expect(retained.status, 'review_resolved');
          expect(
            retained.payload['recoveryReviewStatus'],
            'RESOLVED_REGISTERED',
          );
          expect((await cash.cachedActiveSession()), isNull);
          expect(
            (await direct.get('/cash/state')).data['userOpenShift'],
            isNull,
          );
          result.addAll({
            'companyId': user.companyId,
            'userId': user.id,
            'sessionId': opened.shiftId,
            'expectedClosingAmount': 7,
            'dispatched': dispatched,
            'retainedCloseReview': retained.id,
            'reviewId': retained.payload['recoveryReviewId'],
            'reviewStatus': retained.payload['recoveryReviewStatus'],
          });
        } finally {
          queue?.dispose();
          client?.close(force: true);
          direct.close(force: true);
          transport.close(force: true);
          await proxy?.close(force: true);
          if (priorUser != null && priorAccess != null) {
            await identity.saveTokens(priorAccess, priorRefresh);
            await identity.saveUserSnapshot(priorUser);
          }
        }
      });
      expect(tester.takeException(), isNull);
      binding.reportData = result;
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
