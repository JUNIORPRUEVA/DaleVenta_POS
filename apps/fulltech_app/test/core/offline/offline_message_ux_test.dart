import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/operation_error_message.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/sync_status_menu_button.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FixtureQueue extends SyncQueueService {
  _FixtureQueue(SyncQueueState initial) : super(OfflineStore.instance) {
    state = initial;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String previousPath;
  final store = OfflineStore.instance;
  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'));
    await font.load();
  });
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await store.closeForTesting();
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-message-ux-');
    await databaseFactory.setDatabasesPath(root.path);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await TokenStorage().saveUserSnapshot(
      UserModel.fromJson({
        'id': 'ux-user',
        'companyId': 'ux-company',
        'email': 'ux@fullpos.test',
      }),
    );
    final now = DateTime.now().toUtc();
    await store.putPendingAction(
      PendingSyncAction(
        id: 'ux-action',
        type: 'sales.create',
        scope: 'sales',
        companyId: 'ux-company',
        userId: 'ux-user',
        payload: const {},
        status: 'conflict',
        attempts: 1,
        createdAt: now,
        updatedAt: now,
        error: jsonEncode({
          'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
          'details': {
            'productName': 'Tela de prueba con nombre largo para revisión',
            'requestedQuantity': '5.000000',
            'availableQuantity': '2.000000',
          },
        }),
      ),
    );
  });
  tearDown(() async {
    await store.closeForTesting();
    await databaseFactory.setDatabasesPath(previousPath);
    final tempRoot = Directory.systemTemp.absolute.path;
    expect(root.absolute.path.startsWith(tempRoot), isTrue);
    await root.delete(recursive: true);
  });

  for (final size in [const Size(1366, 768), const Size(360, 640)]) {
    testWidgets('checkout shows the complete actionable message at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final message = customerOperationErrorMessage({
        'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
        'details': {
          'productName': 'TELA_UTP de prueba con nombre largo',
          'requestedQuantity': 5,
          'availableQuantity': 2,
        },
      })!;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Manrope'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SalesNoticeToast(
                  title: 'No se pudo completar',
                  message: message,
                  icon: Icons.error_outline_rounded,
                  accent: Colors.red,
                  repeatCount: 1,
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.text(message);
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).maxLines, isNull);
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('OFFLINE_UX_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final renderView = binding.renderViews.first;
          // ignore: invalid_use_of_protected_member
          final layer = renderView.layer! as OffsetLayer;
          final picture = await layer.toImage(renderView.paintBounds);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory('../../.uat/evidence/offline-message-ux');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/checkout-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.tap(find.byTooltip('Cerrar'));
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('conflicts remain readable and never say all synced at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncQueueServiceProvider.overrideWith(
              (ref) => _FixtureQueue(
                const SyncQueueState(
                  conflictCount: 1,
                  lastError:
                      'DioException status code of 409 RequestOptions cash.close',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Manrope'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SyncStatusMenuButton(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SyncStatusMenuButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
              .textContaining('Cantidad solicitada: 5. Disponible: 2.')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Todo sincronizado'), findsNothing);
      expect(find.text('Revisión pendiente'), findsOneWidget);
      expect(
        find.textContaining('Cantidad solicitada: 5. Disponible: 2.'),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('cash.close'), findsNothing);
      final message = tester.widget<Text>(
        find.textContaining('Cantidad solicitada: 5. Disponible: 2.'),
      );
      expect(message.maxLines, isNull);
      await tester.ensureVisible(find.text('Revisión pendiente'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final actions = await tester.runAsync(
        () => store.listPendingActions(
          companyId: 'ux-company',
          userId: 'ux-user',
        ),
      );
      expect(actions!.single.status, 'conflict');
      expect(actions.single.id, 'ux-action');

      if (const bool.fromEnvironment('OFFLINE_UX_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final renderView = binding.renderViews.first;
          // ignore: invalid_use_of_protected_member
          final layer = renderView.layer! as OffsetLayer;
          final picture = await layer.toImage(renderView.paintBounds);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory('../../.uat/evidence/offline-message-ux');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/sync-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
