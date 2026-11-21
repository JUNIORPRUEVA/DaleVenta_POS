import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/plans/data/plans_repository.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/payment_screen.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/orders_history_screen.dart';
import 'package:daleventa_pos/features/plans/presentation/widgets/plan_ui.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../test/support/plans_file_picker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'existing three-month order uploads a real PDF once despite quote outage',
    (tester) async {
      expect(Platform.isWindows, true);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = Directory(
        const String.fromEnvironment('PLANS_PAYMENT_LAB_DIR'),
      );
      final fixture =
          jsonDecode(
                await File(
                  '${directory.path}/native-fixture.json',
                ).readAsString(),
              )
              as Map;
      expect(fixture['api'], 'http://127.0.0.1:4018');
      final dio = Dio(BaseOptions(baseUrl: fixture['api'] as String));
      final login = await dio.post(
        '/auth/login',
        data: {'email': fixture['email'], 'password': fixture['password']},
      );
      expect(login.data['user']['companyId'], fixture['user']['companyId']);
      dio.options.headers['Authorization'] =
          'Bearer ${login.data['accessToken']}';
      final licenseBefore = await LicenseRepository(dio).getLicense();
      expect(licenseBefore.companyId, fixture['user']['companyId']);
      var postCount = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/orders/quote')) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 503,
                    data: {'message': 'Cotización de prueba no disponible'},
                  ),
                ),
              );
            }
            if (options.method == 'POST' &&
                options.path.endsWith('/evidence')) {
              postCount++;
            }
            handler.next(options);
          },
        ),
      );
      final before = (await OfflineStore.instance.listPendingActions(
        limit: null,
      )).map((a) => a.toMap()).toList();
      final proof = File('${directory.path}/native-proof.pdf');
      expect(await proof.exists(), true);
      final picker = PlansTestFilePicker(
        () async => FilePickerResult([
          PlatformFile(
            name: 'comprobante-prueba.pdf',
            path: proof.path,
            size: await proof.length(),
          ),
        ]),
      );
      FilePicker.platform = picker;
      addTearDown(AppFeedback.clearToasts);
      final repaint = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plansRepositoryProvider.overrideWithValue(PlansRepository(dio)),
            licenseStatusProvider.overrideWith(
              (ref) => LicenseRepository(dio).getLicense(),
            ),
          ],
          child: RepaintBoundary(
            key: repaint,
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: GoRouter(
                initialLocation: '/payment',
                routes: [
                  GoRoute(
                    path: '/payment',
                    builder: (_, __) => PaymentScreen(
                      planCode: '${fixture['planCode']}',
                      startPayment: true,
                    ),
                  ),
                  GoRoute(
                    path: '/planes/historial',
                    builder: (_, __) => const OrdersHistoryScreen(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 35; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        final image =
            await (repaint.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await settle();
      final upload = find.byWidgetPredicate(
        (w) =>
            w is SquareButton &&
            w.label == 'Subir comprobante de la transferencia',
      );
      expect(upload, findsOneWidget);
      expect(tester.widget<SquareButton>(upload).onPressed, isNotNull);
      await capture('windows-payment-ready');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await settle();
      expect(find.text('Comprobante recibido'), findsOneWidget);
      expect(find.text('Confirmar pago'), findsNothing);
      expect(find.text('Ver estado del pago'), findsOneWidget);
      expect(postCount, 1);
      expect(picker.calls, 1);
      final orders = await PlansRepository(dio).fetchOrders();
      final order = orders.singleWhere((o) => o.id == fixture['orderId']);
      expect(order.months, 3);
      expect(order.status, 'EVIDENCE_RECEIVED');
      expect(order.evidences.length, 1);
      final licenseAfter = await LicenseRepository(dio).getLicense();
      expect(licenseAfter.status, licenseBefore.status);
      expect(licenseAfter.planCode, licenseBefore.planCode);
      expect(
        (await OfflineStore.instance.listPendingActions(
          limit: null,
        )).map((a) => a.toMap()).toList(),
        before,
      );
      await capture('windows-payment-received');
      await tester.tap(find.text('Ver estado del pago'));
      await settle();
      expect(find.text('Tus ordenes'), findsOneWidget);
      expect(find.text('Comprobante en revisión'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      await capture('windows-payment-history');
      await File('${directory.path}/native-result.json').writeAsString(
        jsonEncode({
          'result': 'PASS',
          'runId': const Uuid().v4(),
          'companyId': fixture['user']['companyId'],
          'orderId': order.id,
          'evidenceId': order.evidences.single.id,
          'months': order.months,
          'status': order.status,
          'actualHttpMultipart': true,
          'quoteOutageDidNotBlockUpload': true,
          'uploadPosts': postCount,
          'offlineQueueUnchanged': true,
          'historyShowsPersistedReceipt': true,
          'osPicker':
              'synthetic file selected by test, actual file bytes sent to private API',
        }),
      );
      AppFeedback.clearToasts();
      await tester.pumpWidget(const SizedBox.shrink());
      dio.close();
    },
  );
}
