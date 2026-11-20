import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/auth/auth_interceptor.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/offline_emergency_policy.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/usage/client_telemetry_headers.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/features/offline/sale_attempt_recovery_screen.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/main.dart' as app;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';

/// Opt-in native Windows acceptance. All business data is synthetic. The API
/// must have its local-only UAT guard and its dedicated PostgreSQL database.
/// Evidence and the SQLite outbox are preserved; this test never clears them.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('UAT_API_BASE');
  var evidencePath = const String.fromEnvironment('RECOVERY_EVIDENCE_DIR');
  testWidgets(
    'Windows: socket failures, restart, replay, shift and tenant isolation',
    (tester) async {
      expect(Platform.isWindows || Platform.isAndroid, isTrue);
      final target = Uri.parse(base);
      expect(['127.0.0.1', '::1', '[::1]'], contains(target.host));
      expect([4004, 4005], contains(target.port));
      if (Platform.isAndroid) evidencePath = '${(await getApplicationSupportDirectory()).path}/recovery-evidence';
      expect(evidencePath, isNotEmpty);
      final evidence = <String, dynamic>{
        'platform': Platform.operatingSystem,
        'api': base,
        'scenarios': <Map<String, dynamic>>[],
      };
      final scenarios = evidence['scenarios'] as List<Map<String, dynamic>>;
      late UserModel user;
      late String token;
      late String shift;
      final run = DateTime.now().microsecondsSinceEpoch.toString();
      final store = OfflineStore.instance;
      final http = HttpClient()..autoUncompress = false;
      HttpServer? proxy;
      var disconnected = true;
      var loseSaleResponse = false;
      var expireNextMovement = false;
      late Dio direct;
      late Dio client;
      SyncQueueService? queue;
      final scope = <String, String>{};
      Future<List<PendingSyncAction>> pending() => store.listPendingActions(
        limit: null,
        companyId: user.companyId,
        userId: user.id,
      );
      Future<void> waitForQueue() async {
        for (var i = 0; i < 100 && queue!.state.isProcessing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(queue!.state.isProcessing, isFalse);
      }

      SyncQueueService newQueue() => SyncQueueService(
        store,
        scopeResolver: () async => OfflineSyncScope(
          companyId: scope['companyId'],
          userId: scope['userId'],
        ),
      );
      PendingSyncAction movement(
        String id,
        String session, {
        String status = 'pending',
        bool permanent = false,
      }) {
        final now = DateTime.now().toUtc();
        return PendingSyncAction(
          id: id,
          type: 'cash.movement',
          scope: 'cash',
          companyId: user.companyId,
          userId: user.id,
          idempotencyKey: id,
          payload: {
            'id': id,
            'operationId': id,
            'sessionId': session,
            'type': 'IN',
            'amount': 7,
            'reason': 'Synthetic Windows recovery acceptance',
            'occurredAt': now.toIso8601String(),
          },
          status: status,
          permanent: permanent,
          attempts: 0,
          createdAt: now,
          updatedAt: now,
        );
      }

      await tester.runAsync(() async {
        try {
          if (Platform.isWindows) {
            sqfliteFfiInit();
            databaseFactory = databaseFactoryFfi;
          }
          // Exercise the actual encrypted native store with concurrent callers.
          // Keep these synthetic keys as evidence, without clearing other data.
          const secure = SerializedSecureStorage();
          await Future.wait(List.generate(30, (index) => secure.write(
            key: 'uat.recovery.validation.$run.$index', value: 'synthetic-$index')));
          for (var index = 0; index < 30; index++) {
            expect(await secure.read(key: 'uat.recovery.validation.$run.$index'), 'synthetic-$index');
          }
          scenarios.add({'name': 'encrypted-native-store-concurrent-writes', 'retainedKeys': 30});
          final headers = await ClientTelemetryHeaders.instance.headers();
          direct = Dio(BaseOptions(baseUrl: base, headers: headers));
          final password = 'Synthetic-$run-Aa1!';
          final registered =
              (await direct.post(
                    '/auth/register-business',
                    data: {
                      'firstName': 'Recovery',
                      'lastName': 'Windows',
                      'email': 'recovery-$run@example.test',
                      'phone': '8095550101',
                      'password': password,
                      'confirmPassword': password,
                      'commercialName': 'Recovery Windows $run',
                      'country': 'DO',
                      'currency': 'DOP',
                    },
                  )).data
                  as Map;
          user = UserModel.fromJson(
            Map<String, dynamic>.from(registered['user'] as Map),
          );
          token = registered['accessToken'] as String;
          await TokenStorage().saveTokens(
            token,
            registered['refreshToken']?.toString(),
          );
          await TokenStorage().saveUserSnapshot(user);
          direct.options.headers['authorization'] = 'Bearer $token';
          await direct.post('/onboarding/skip-all');
          scope.addAll({'companyId': user.companyId!, 'userId': user.id});
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
            deviceFingerprint: headers['x-client-device-id']!,
          );
          final opened =
              (await direct.post(
                    '/cash/sessions/open',
                    data: {'openingAmount': 0},
                  )).data
                  as Map;
          shift = opened['shiftId'] as String;
          proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          proxy!.listen((request) async {
            if (disconnected) {
              (await request.response.detachSocket()).destroy();
              return;
            }
            if (expireNextMovement && request.uri.path == '/cash/movements') {
              expireNextMovement = false;
              await request.drain<void>();
              request.response.statusCode = 401;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({'message': 'Synthetic expired access token'}),
              );
              await request.response.close();
              return;
            }
            try {
              final outgoing = await http.openUrl(
                request.method,
                Uri.parse('$base${request.uri}'),
              );
              request.headers.forEach((name, values) {
                if (!['host', 'content-length', 'connection'].contains(name)) {
                  outgoing.headers.set(name, values);
                }
              });
              await outgoing.addStream(request);
              final response = await outgoing.close();
              if (loseSaleResponse &&
                  request.uri.path == '/sales' &&
                  request.method == 'POST') {
                loseSaleResponse = false;
                await response.drain<void>();
                (await request.response.detachSocket()).destroy();
                return;
              }
              request.response.statusCode = response.statusCode;
              response.headers.forEach((name, values) {
                if (![
                  'transfer-encoding',
                  'content-length',
                  'connection',
                ].contains(name)) {
                  request.response.headers.set(name, values);
                }
              });
              await response.pipe(request.response);
            } catch (_) {
              request.response.statusCode = 502;
              await request.response.close();
            }
          });
          client = Dio(
            BaseOptions(
              baseUrl: 'http://127.0.0.1:${proxy!.port}',
              headers: {...headers, 'authorization': 'Bearer $token'},
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );
          queue = newQueue();
          VentasRepository repo() => VentasRepository(
            client,
            queue!,
            WarehouseRepository(client),
            originCashSessionIdResolver: () async => shift,
          );
          Future<SaleModel?> sale(String id) => repo().createSale(
            clientRequestId: id,
            paymentMethod: 'cash',
            paymentCashAmount: 50,
            cashReceived: 50,
            expectedTotalSold: 50,
            items: [
              SaleDraftItem(
                productId: null,
                name: 'Synthetic recovery item',
                imageUrl: null,
                isExternal: false,
                qty: 1,
                priceSoldUnit: 50,
                costUnitSnapshot: 0,
              ),
            ],
          );
          final request = 'windows-offline-$run';
          final local = await sale(request);
          await waitForQueue();
          expect(local!.id, startsWith('local_'));
          final saved = (await pending()).singleWhere(
            (a) => a.idempotencyKey == request,
          );
          final before = await direct.get(
            '/sales/attempts/$request/reconciliation',
            queryParameters: {'expectedTotalSold': 50},
          );
          expect((before.data as Map)['status'], 'NOT_FOUND');
          queue!.dispose();
          await store.closeForTesting();
          queue = newQueue();
          repo().registerSyncHandlers();
          expect(
            (await pending()).singleWhere((a) => a.id == saved.id).payload,
            saved.payload,
          );
          disconnected = false;
          await queue!.processPending();
          final confirmed =
              (await direct.get(
                    '/sales/attempts/$request/reconciliation',
                    queryParameters: {'expectedTotalSold': 50},
                  )).data
                  as Map;
          expect(confirmed['status'], 'CONFIRMED');
          expect(confirmed['matchesExpected'], true);
          final replay =
              (await direct.post('/sales', data: saved.payload)).data as Map;
          expect(replay['id'], (confirmed['sale'] as Map)['id']);
          expect(
            (await pending()).any((a) => a.id == saved.id),
            isFalse,
            reason: jsonEncode({
              'responseKeys': replay.keys.toList(),
              'pending': [
                for (final a in await pending())
                  {'status': a.status, 'error': a.error},
              ],
            }),
          );
          scenarios.add({
            'name': 'offline-sale-restart-replay',
            'requestId': request,
            'serverId': replay['id'],
            'originalOccurredAt': saved.payload['saleOccurredAt'],
            'before': 'NOT_FOUND',
            'after': 'CONFIRMED',
            'localOutboxAfter': 0,
          });

          // Server commits but the socket closes before the client sees its reply.
          queue!.dispose();
          queue = newQueue();
          loseSaleResponse = true;
          final lost = 'windows-lost-response-$run';
          final uncertain = await sale(lost);
          await waitForQueue();
          expect(uncertain!.id, startsWith('local_'));
          final original =
              (await direct.get(
                    '/sales/attempts/$lost/reconciliation',
                    queryParameters: {'expectedTotalSold': 50},
                  )).data
                  as Map;
          expect(original['status'], 'CONFIRMED');
          repo().registerSyncHandlers();
          await queue!.processPending();
          expect(
            (await pending()).any((a) => a.idempotencyKey == lost),
            isFalse,
          );
          scenarios.add({
            'name': 'committed-sale-lost-response',
            'requestId': lost,
            'serverId': (original['sale'] as Map)['id'],
            'remainingOutbox': 0,
          });

          CashRepository(
            client,
            queue!,
            offlineStore: store,
          ).registerSyncHandlers();
          final cash = movement('windows-movement-$run', shift);
          await store.putPendingAction(cash);
          await queue!.processPending();
          final cashBody = Map<String, dynamic>.from(cash.payload)
            ..remove('id');
          final cashReplay =
              (await direct.post('/cash/movements', data: cashBody)).data
                  as Map;
          expect(
            DateTime.parse(
              cashReplay['occurredAt'] as String,
            ).millisecondsSinceEpoch,
            DateTime.parse(
              cash.payload['occurredAt'] as String,
            ).millisecondsSinceEpoch,
          );
          final mismatch = await direct.post(
            '/cash/movements',
            data: {...cashBody, 'amount': 999},
            options: Options(validateStatus: (_) => true),
          );
          expect(mismatch.statusCode, 409);
          scenarios.add({
            'name': 'cash-original-time-idempotency',
            'operationId': cash.id,
            'serverId': cashReplay['id'],
            'occurredAt': cashReplay['occurredAt'],
            'mismatchHttp': 409,
          });

          final authEvents = AuthSessionEvents();
          final authenticated = Dio(
            BaseOptions(baseUrl: client.options.baseUrl, headers: headers),
          );
          authenticated.interceptors.add(
            AuthInterceptor(TokenStorage(), authEvents, authenticated),
          );
          CashRepository(
            authenticated,
            queue!,
            offlineStore: store,
          ).registerSyncHandlers();
          expireNextMovement = true;
          final authMovement = movement('windows-auth-refresh-$run', shift);
          await store.putPendingAction(authMovement);
          await queue!.processPending();
          expect(
            (await pending()).any((a) => a.id == authMovement.id),
            isFalse,
          );
          expect(authEvents.unauthorizedLogoutRequested, isFalse);
          scenarios.add({
            'name': '401-real-refresh-and-original-operation-retry',
            'operationId': authMovement.id,
            'remainingOutbox': 0,
            'logoutRequested': false,
          });
          token = (await TokenStorage().getAccessToken())!;
          direct.options.headers['authorization'] = 'Bearer $token';
          client.options.headers['authorization'] = 'Bearer $token';
          CashRepository(
            client,
            queue!,
            offlineStore: store,
          ).registerSyncHandlers();
          authenticated.close();
          authEvents.dispose();
          await direct.post(
            '/cash/sessions/close',
            data: {'sessionId': shift, 'closingAmount': 114},
          );
          final later =
              (await direct.post(
                    '/cash/sessions/open',
                    data: {'openingAmount': 0},
                  )).data
                  as Map;
          final rejected = movement('windows-old-shift-$run', shift);
          await store.putPendingAction(rejected);
          await queue!.processPending();
          final retained = (await pending()).singleWhere(
            (a) => a.id == rejected.id,
          );
          expect(retained.isAutomaticallyRetryable, isFalse);
          final newState = (await direct.get('/cash/state')).data as Map;
          expect(
            (newState['activeSession'] as Map)['shiftId'],
            later['shiftId'],
          );
          for (var i = 0; i < 45; i++) {
            await store.putPendingAction(
              movement(
                'windows-blocked-$run-$i',
                shift,
                status: 'failed',
                permanent: true,
              ),
            );
          }
          final valid = movement(
            'windows-new-valid-$run',
            later['shiftId'] as String,
          );
          await store.putPendingAction(valid);
          scope['companyId'] = 'different-company';
          scope['userId'] = 'different-user';
          await queue!.processPending();
          expect((await pending()).any((a) => a.id == valid.id), isTrue);
          scope.addAll({'companyId': user.companyId!, 'userId': user.id});
          await queue!.processPending();
          expect((await pending()).any((a) => a.id == valid.id), isFalse);
          expect((await pending()).length, 46);
          scenarios.add({
            'name': 'old-shift-45-blocked-new-valid-tenant-scope',
            'rejectedId': rejected.id,
            'rejectedStatus': retained.status,
            'newOperationId': valid.id,
            'retainedIncidents': 46,
          });
          queue!.dispose();
          await store.closeForTesting();
          expect((await pending()).length, 46);
          evidence.addAll({
            'companyId': user.companyId,
            'userId': user.id,
            'originalShift': shift,
            'laterShift': later['shiftId'],
            'run': run,
            'persistentIncidentsAfterRestart': 46,
          });
          final dir = Directory(evidencePath);
          await dir.create(recursive: true);
          await File(
            '${dir.path}/windows-persistence.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
          http.close(force: true);
          await proxy!.close(force: true);
          client.close();
          direct.close();
        } catch (error, stack) {
          await Directory(evidencePath).create(recursive: true);
          await File(
            '$evidencePath/windows-failure.txt',
          ).writeAsString('$error\n$stack');
          http.close(force: true);
          await proxy?.close(force: true);
          rethrow;
        }
      });
      expect(tester.takeException(), isNull);
      final originalErrorHandler = FlutterError.onError;
      final originalErrorWidgetBuilder = ErrorWidget.builder;
      await app.main();
      // The app installs its production error reporter. Keep test failures
      // observable by restoring the integration binding's handlers immediately.
      FlutterError.onError = originalErrorHandler;
      ErrorWidget.builder = originalErrorWidgetBuilder;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // Render the real recovery screen over the authenticated app, using its
      // production providers and the durable incidents created above.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SaleAttemptRecoveryScreen()),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      for (var i = 0; i < 100 && find.text('Ventas offline y operaciones de caja').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.text('Ventas offline y operaciones de caja'), findsOneWidget);
      final view = binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer! as OffsetLayer;
      final image = await layer.toImage(view.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$evidencePath/windows-recovery-center.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      binding.reportData = {
        ...evidence,
        'centerScreenshotPngBase64': base64Encode(bytes.buffer.asUint8List()),
      };
      FlutterError.onError = originalErrorHandler;
      ErrorWidget.builder = originalErrorWidgetBuilder;
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
