import 'dart:convert';

import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/sync_status_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _companyId = String.fromEnvironment(
  'W13_VIS_COMPANY_ID',
  defaultValue: '727562dd-fbba-4197-9ed4-de3b5945c0a4',
);
const _userId = String.fromEnvironment(
  'W13_VIS_USER_ID',
  defaultValue: 'f5bccc03-ac2d-4bb6-b122-62329c3dd901',
);
const _email = String.fromEnvironment(
  'W13_VIS_EMAIL',
  defaultValue: 'w132_visual_final_1788186412@example.invalid',
);
const _productId = String.fromEnvironment(
  'W13_VIS_PRODUCT_ID',
  defaultValue: '1da0cc32-2e40-46ea-ad7d-249a631172c0',
);
const _warehouseId = String.fromEnvironment(
  'W13_VIS_WAREHOUSE_ID',
  defaultValue: 'f0691018-d260-4c93-8aa0-2bec79c2f4cc',
);
const _productName = String.fromEnvironment(
  'W13_VIS_PRODUCT_NAME',
  defaultValue: 'W13 Conflict Visual Product',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedVisualConflict();
  runApp(const ProviderScope(child: W13VisualEvidenceApp()));
}

Future<void> _seedVisualConflict() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('accessToken', 'w13-visual-access-token');
  await prefs.setString('refreshToken', 'w13-visual-refresh-token');
  final existingSales = prefs.getString('ft_db_offline_sales') ?? '';
  final existingActions = prefs.getString('ft_db_pending_actions') ?? '';
  if (existingSales.contains('local_w13_visual_web_conflict') &&
      existingActions.contains('sales.create:local_w13_visual_web_conflict')) {
    return;
  }
  final now = DateTime.now().toUtc().toIso8601String();
  const clientRequestId = 'w13_visual_web_conflict';
  final payload = {
    'clientRequestId': clientRequestId,
    'warehouseId': _warehouseId,
    'items': [
      {
        'productId': _productId,
        'productName': _productName,
        'qty': 4,
        'priceSoldUnit': 10,
      },
    ],
  };
  final conflict = {
    'statusCode': 409,
    'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
    'errorCode': 'INSUFFICIENT_WAREHOUSE_STOCK',
    'message':
        'Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.',
    'details': {
      'productId': _productId,
      'warehouseId': _warehouseId,
      'requestedQuantity': '4.000000',
      'availableQuantity': '1.000000',
      'productName': _productName,
      'warehouseName': 'Main Warehouse',
      'warehouseCode': 'w132_visual_final_1788186412-main',
    },
  };
  await prefs.setString(
    'authUserSnapshot',
    jsonEncode({
      'id': _userId,
      'email': _email,
      'nombreCompleto': 'W13 Visual Cashier',
      'telefono': '0000000000',
      'role': 'CAJERO',
      'companyId': _companyId,
      'companyName': 'W13 Visual',
      'companySlug': 'w132_visual_final_1788186412',
    }),
  );
  await prefs.setString(
    'ft_db_pending_actions',
    jsonEncode([
      {
        'id': 'sales.create:local_w13_visual_web_conflict',
        'type': 'sales.create',
        'scope': 'sales',
        'companyId': _companyId,
        'userId': _userId,
        'terminalId': '',
        'entityType': 'sale',
        'entityId': 'local_w13_visual_web_conflict',
        'idempotencyKey': clientRequestId,
        'payload': payload,
        'status': 'conflict',
        'attempts': 1,
        'error': jsonEncode(conflict),
        'permanent': true,
        'createdAt': now,
        'updatedAt': now,
      },
    ]),
  );
  await prefs.setString(
    'ft_db_offline_sales',
    jsonEncode([
      {
        'localId': 'local_w13_visual_web_conflict',
        'companyId': _companyId,
        'userId': _userId,
        'serverId': null,
        'clientRequestId': clientRequestId,
        'status': 'conflict',
        'payload': payload,
        'items': const [],
        'payment': const {'paymentMethod': 'cash', 'paymentCashAmount': 40},
        'inventoryIntents': const [],
        'totalSold': 40,
        'saleOccurredAt': now,
        'createdAt': now,
        'updatedAt': now,
        'error': jsonEncode(conflict),
      },
    ]),
  );
}

class W13VisualEvidenceApp extends ConsumerStatefulWidget {
  const W13VisualEvidenceApp({super.key});

  @override
  ConsumerState<W13VisualEvidenceApp> createState() =>
      _W13VisualEvidenceAppState();
}

class _W13VisualEvidenceAppState extends ConsumerState<W13VisualEvidenceApp> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      ref.read(syncQueueServiceProvider.notifier).refreshStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
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
    );
  }
}
