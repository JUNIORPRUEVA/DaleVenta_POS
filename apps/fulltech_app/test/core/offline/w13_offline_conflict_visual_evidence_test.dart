// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/sync_status_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues(const {});
    SharedPreferences.setMockInitialValues(const {});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final email = const String.fromEnvironment('W13_VIS_EMAIL').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_EMAIL')
      : (Platform.environment['W13_VIS_EMAIL'] ?? '');
  final password = const String.fromEnvironment('W13_VIS_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_PASSWORD')
      : (Platform.environment['W13_VIS_PASSWORD'] ?? '');
  final productId =
      const String.fromEnvironment('W13_VIS_PRODUCT_ID').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_PRODUCT_ID')
      : (Platform.environment['W13_VIS_PRODUCT_ID'] ?? '');
  final companyId =
      const String.fromEnvironment('W13_VIS_COMPANY_ID').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_COMPANY_ID')
      : (Platform.environment['W13_VIS_COMPANY_ID'] ??
            '727562dd-fbba-4197-9ed4-de3b5945c0a4');
  final userId = const String.fromEnvironment('W13_VIS_USER_ID').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_USER_ID')
      : (Platform.environment['W13_VIS_USER_ID'] ??
            'f5bccc03-ac2d-4bb6-b122-62329c3dd901');
  final warehouseId =
      const String.fromEnvironment('W13_VIS_WAREHOUSE_ID').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_WAREHOUSE_ID')
      : (Platform.environment['W13_VIS_WAREHOUSE_ID'] ?? '');
  final terminalId =
      const String.fromEnvironment('W13_VIS_TERMINAL_ID').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_TERMINAL_ID')
      : (Platform.environment['W13_VIS_TERMINAL_ID'] ?? '');
  final deviceFingerprint =
      const String.fromEnvironment('W13_VIS_DEVICE_FINGERPRINT').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_DEVICE_FINGERPRINT')
      : (Platform.environment['W13_VIS_DEVICE_FINGERPRINT'] ?? '');
  final productName =
      const String.fromEnvironment('W13_VIS_PRODUCT_NAME').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_PRODUCT_NAME')
      : (Platform.environment['W13_VIS_PRODUCT_NAME'] ??
            'W13 Conflict Visual Product');
  final apiBaseUrl = const String.fromEnvironment('API_BASE_URL').isNotEmpty
      ? const String.fromEnvironment('API_BASE_URL')
      : (Platform.environment['API_BASE_URL'] ?? '');
  final outDir =
      const String.fromEnvironment('W13_VIS_SCREENSHOT_DIR').isNotEmpty
      ? const String.fromEnvironment('W13_VIS_SCREENSHOT_DIR')
      : (Platform.environment['W13_VIS_SCREENSHOT_DIR'] ??
            '../../docs/uom-visual-evidence');

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 300));
    final renderView = binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  }

  Future<UserModel> restoreSyntheticSession() async {
    await TokenStorage().saveTokens(
      'w13-visual-access-token',
      'w13-visual-refresh-token',
    );
    final user = UserModel(
      id: userId,
      email: email,
      nombreCompleto: 'W13 Visual Cashier',
      telefono: '0000000000',
      role: 'CAJERO',
      companyId: companyId,
      companyName: 'W13 Visual',
      companySlug: 'w132_visual_final_1788186412',
    );
    await TokenStorage().saveUserSnapshot(user);
    return user;
  }

  Future<void> mountSyncStatus(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SyncStatusMenuButton(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final context = tester.element(find.byType(SyncStatusMenuButton));
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(syncQueueServiceProvider.notifier).refreshStats();
    await settle(tester);
  }

  Future<void> refreshMountedSyncStatus(WidgetTester tester) async {
    final context = tester.element(find.byType(SyncStatusMenuButton));
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(syncQueueServiceProvider.notifier).refreshStats();
    await settle(tester);
  }

  Future<void> createRealConflict(UserModel user) async {
    expect(user.companyId, isNotEmpty);
    expect(user.id, isNotEmpty);

    final clientRequestId =
        'w13_visual_offline_${DateTime.now().microsecondsSinceEpoch}';
    final localId = 'local_$clientRequestId';
    final occurredAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 2),
    );
    final item = {
      'productId': productId,
      'productName': productName,
      'qty': 4,
      'priceSoldUnit': 10,
      'costUnitSnapshot': 4,
    };
    final payload = {
      'clientRequestId': clientRequestId,
      'warehouseId': warehouseId,
      'terminalId': terminalId,
      'deviceFingerprint': deviceFingerprint,
      'saleOccurredAt': occurredAt.toIso8601String(),
      'paymentMethod': 'cash',
      'paymentCashAmount': 40,
      'expectedTotalSold': 40,
      'items': [item],
    };
    final action = PendingSyncAction(
      id: 'sales.create:$localId',
      type: 'sales.create',
      scope: 'sales',
      companyId: user.companyId,
      userId: user.id,
      terminalId: terminalId,
      entityType: 'sale',
      entityId: localId,
      idempotencyKey: clientRequestId,
      payload: payload,
      status: 'pending',
      attempts: 0,
      createdAt: occurredAt,
      updatedAt: occurredAt,
    );

    await OfflineStore.instance.saveOfflineSaleAtomically(
      localSaleId: localId,
      companyId: user.companyId!,
      userId: user.id,
      clientRequestId: clientRequestId,
      salePayload: payload,
      itemPayloads: [item],
      paymentPayload: const {
        'paymentMethod': 'cash',
        'paymentCashAmount': 40,
        'paymentTransferAmount': 0,
        'creditAmount': 0,
      },
      pendingAction: action,
      totalSold: 40,
      saleOccurredAt: occurredAt,
    );

    await OfflineStore.instance.markOfflineSaleConflict(
      companyId: user.companyId!,
      clientRequestId: clientRequestId,
      conflict: {
        'statusCode': 409,
        'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
        'errorCode': 'INSUFFICIENT_WAREHOUSE_STOCK',
        'message':
            'Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.',
        'details': {
          'productId': productId,
          'warehouseId': warehouseId,
          'requestedQuantity': '4.000000',
          'availableQuantity': '1.000000',
          'productName': productName,
          'warehouseName': 'Main Warehouse',
          'warehouseCode': 'w132_visual_final_1788186412-main',
        },
      },
    );

    final conflicts = await OfflineStore.instance.listOfflineSales(
      companyId: user.companyId!,
      userId: user.id,
      status: 'conflict',
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.single['error'], contains('INSUFFICIENT_WAREHOUSE_STOCK'));
    expect(conflicts.single['error'], contains(productName));
  }

  Future<void> openSyncMenu(WidgetTester tester) async {
    final revisar = find.text('Revisar');
    expect(revisar, findsOneWidget);
    await tester.tap(revisar);
    await settle(tester);
    expect(find.text('Venta offline sin sincronizar'), findsOneWidget);
    expect(find.textContaining(productName), findsOneWidget);
    expect(find.textContaining('solicitado 4'), findsOneWidget);
    expect(find.textContaining('disponible 1'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('StackTrace'), findsNothing);
  }

  testWidgets(
    'captures real W13 offline conflict visual evidence',
    (tester) async {
      final isConfigured =
          apiBaseUrl == 'http://127.0.0.1:4013' &&
          email.isNotEmpty &&
          password.isNotEmpty &&
          productId.isNotEmpty &&
          companyId.isNotEmpty &&
          userId.isNotEmpty &&
          warehouseId.isNotEmpty &&
          terminalId.isNotEmpty &&
          deviceFingerprint.isNotEmpty;

      if (!isConfigured) {
        debugPrint(
          'W13_VIS: skipped because API_BASE_URL/W13_VIS_* values are not configured.',
        );
        return;
      }

      expect(apiBaseUrl, 'http://127.0.0.1:4013');
      expect(email, isNotEmpty);
      expect(password, isNotEmpty);
      expect(productId, isNotEmpty);
      expect(companyId, isNotEmpty);
      expect(userId, isNotEmpty);
      expect(warehouseId, isNotEmpty);
      expect(terminalId, isNotEmpty);
      expect(deviceFingerprint, isNotEmpty);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await setViewport(tester, const Size(1366, 768));
      debugPrint('W13_VIS: clearing local state');
      await tester.runAsync(() async {
        await TokenStorage().clearTokens();
        await OfflineStore.instance.clearAll();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      });

      debugPrint('W13_VIS: restoring session');
      final user = await tester.runAsync(restoreSyntheticSession);
      expect(user, isNotNull);
      debugPrint('W13_VIS: mounting desktop sync status');
      await mountSyncStatus(tester);
      debugPrint('W13_VIS: creating persisted conflict');
      await tester.runAsync(() => createRealConflict(user!));
      debugPrint('W13_VIS: refreshing conflict UI');
      await refreshMountedSyncStatus(tester);
      debugPrint('W13_VIS: opening desktop menu');
      await openSyncMenu(tester);
      debugPrint('W13_VIS: shooting desktop');
      await shot(tester, 'w13-conflict-desktop');

      await tester.tapAt(const Offset(16, 16));
      await settle(tester);
      debugPrint('W13_VIS: mounting mobile viewport');
      await setViewport(tester, const Size(390, 844));
      debugPrint('W13_VIS: opening mobile menu');
      await openSyncMenu(tester);
      debugPrint('W13_VIS: shooting mobile');
      await shot(tester, 'w13-conflict-mobile-390x844');

      await tester.tapAt(const Offset(16, 16));
      await settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      debugPrint('W13_VIS: remounting for persistence');
      await mountSyncStatus(tester);
      debugPrint('W13_VIS: opening persisted mobile menu');
      await openSyncMenu(tester);
      debugPrint('W13_VIS: shooting persistence');
      await shot(tester, 'w13-conflict-persistence-mobile-390x844');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
