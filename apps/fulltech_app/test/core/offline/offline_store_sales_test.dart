import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
  });

  group('OfflineStore offline sale transaction', () {
    test(
      'saves sale, items, payment, inventory intents and outbox by tenant',
      () async {
        final action = _pendingSaleAction(
          companyId: 'company-a',
          userId: 'user-a',
          localSaleId: 'local_sale_req_a',
          clientRequestId: 'sale_req_a',
        );

        await OfflineStore.instance.saveOfflineSaleAtomically(
          localSaleId: 'local_sale_req_a',
          companyId: 'company-a',
          userId: 'user-a',
          clientRequestId: 'sale_req_a',
          salePayload: _salePayload('sale_req_a'),
          itemPayloads: [_item('product-a', 2), _item('product-b', 1)],
          paymentPayload: {
            'paymentMethod': 'cash',
            'paymentCashAmount': 300,
            'paymentTransferAmount': 0,
            'creditAmount': 0,
          },
          pendingAction: action,
          totalSold: 300,
          saleOccurredAt: DateTime.utc(2026, 8, 19, 12),
        );

        final companyASales = await OfflineStore.instance.listOfflineSales(
          companyId: 'company-a',
          userId: 'user-a',
        );
        final companyBSales = await OfflineStore.instance.listOfflineSales(
          companyId: 'company-b',
          userId: 'user-b',
        );
        final actions = await OfflineStore.instance.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        );

        expect(companyASales, hasLength(1));
        expect(companyASales.single['clientRequestId'], 'sale_req_a');
        expect(companyASales.single['status'], 'pending');
        expect(companyBSales, isEmpty);
        expect(actions, hasLength(1));
        expect(actions.single.idempotencyKey, 'sale_req_a');
      },
    );

    test(
      'deduplicates equivalent outbox records by company and idempotency key',
      () async {
        Future<void> save(String localSaleId) {
          return OfflineStore.instance.saveOfflineSaleAtomically(
            localSaleId: localSaleId,
            companyId: 'company-a',
            userId: 'user-a',
            clientRequestId: 'sale_req_duplicate',
            salePayload: _salePayload('sale_req_duplicate'),
            itemPayloads: [_item('product-a', 1)],
            paymentPayload: {
              'paymentMethod': 'cash',
              'paymentCashAmount': 100,
              'paymentTransferAmount': 0,
              'creditAmount': 0,
            },
            pendingAction: _pendingSaleAction(
              companyId: 'company-a',
              userId: 'user-a',
              localSaleId: localSaleId,
              clientRequestId: 'sale_req_duplicate',
            ),
            totalSold: 100,
          );
        }

        await save('local_sale_req_duplicate_1');
        await save('local_sale_req_duplicate_2');

        final sales = await OfflineStore.instance.listOfflineSales(
          companyId: 'company-a',
        );
        final actions = await OfflineStore.instance.listPendingActions(
          companyId: 'company-a',
          userId: 'user-a',
        );

        expect(sales, hasLength(1));
        expect(actions, hasLength(1));
        expect(actions.single.idempotencyKey, 'sale_req_duplicate');
      },
    );

    test(
      'marks local sale and inventory intents as synced after backend ack',
      () async {
        await OfflineStore.instance.saveOfflineSaleAtomically(
          localSaleId: 'local_sale_req_sync',
          companyId: 'company-a',
          userId: 'user-a',
          clientRequestId: 'sale_req_sync',
          salePayload: _salePayload('sale_req_sync'),
          itemPayloads: [_item('product-a', 1)],
          paymentPayload: {
            'paymentMethod': 'cash',
            'paymentCashAmount': 100,
            'paymentTransferAmount': 0,
            'creditAmount': 0,
          },
          pendingAction: _pendingSaleAction(
            companyId: 'company-a',
            userId: 'user-a',
            localSaleId: 'local_sale_req_sync',
            clientRequestId: 'sale_req_sync',
          ),
          totalSold: 100,
        );

        await OfflineStore.instance.markOfflineSaleSynced(
          companyId: 'company-a',
          clientRequestId: 'sale_req_sync',
          serverSaleId: 'server-sale-1',
        );

        final sales = await OfflineStore.instance.listOfflineSales(
          companyId: 'company-a',
          status: 'synced',
        );

        expect(sales, hasLength(1));
        expect(sales.single['serverId'], 'server-sale-1');
        expect(sales.single['syncedAt'], isNotNull);
      },
    );

    test('marks local sale and inventory intents as conflict', () async {
      await OfflineStore.instance.saveOfflineSaleAtomically(
        localSaleId: 'local_sale_req_conflict',
        companyId: 'company-a',
        userId: 'user-a',
        clientRequestId: 'sale_req_conflict',
        salePayload: _salePayload('sale_req_conflict'),
        itemPayloads: [_item('product-a', 7.625)],
        paymentPayload: {
          'paymentMethod': 'cash',
          'paymentCashAmount': 100,
          'paymentTransferAmount': 0,
          'creditAmount': 0,
        },
        pendingAction: _pendingSaleAction(
          companyId: 'company-a',
          userId: 'user-a',
          localSaleId: 'local_sale_req_conflict',
          clientRequestId: 'sale_req_conflict',
        ),
        totalSold: 100,
      );

      await OfflineStore.instance.markOfflineSaleConflict(
        companyId: 'company-a',
        clientRequestId: 'sale_req_conflict',
        conflict: {
          'errorCode': 'INSUFFICIENT_WAREHOUSE_STOCK',
          'details': {
            'productId': 'product-a',
            'requestedQuantity': '7.625000',
            'availableQuantity': '0.125000',
          },
        },
      );

      final sales = await OfflineStore.instance.listOfflineSales(
        companyId: 'company-a',
        status: 'conflict',
      );
      final aggregate = await OfflineStore.instance.getOfflineSaleAggregate(
        companyId: 'company-a',
        localSaleId: 'local_sale_req_conflict',
      );

      expect(sales, hasLength(1));
      expect(sales.single['error'], contains('INSUFFICIENT_WAREHOUSE_STOCK'));
      expect(aggregate!['inventoryIntents'].single['quantityDelta'], -7.625);
    });

    test('survives store restart with aggregate and pending action', () async {
      await OfflineStore.instance.saveOfflineSaleAtomically(
        localSaleId: 'local_sale_req_restart',
        companyId: 'company-restart',
        userId: 'user-restart',
        clientRequestId: 'sale_req_restart',
        salePayload: _salePayload('sale_req_restart'),
        itemPayloads: [_item('product-a', 1), _item('product-b', 2)],
        paymentPayload: {
          'paymentMethod': 'cash',
          'paymentCashAmount': 300,
          'paymentTransferAmount': 0,
          'creditAmount': 0,
        },
        pendingAction: _pendingSaleAction(
          companyId: 'company-restart',
          userId: 'user-restart',
          localSaleId: 'local_sale_req_restart',
          clientRequestId: 'sale_req_restart',
        ),
        totalSold: 300,
      );

      await OfflineStore.instance.closeForTesting();

      final aggregate = await OfflineStore.instance.getOfflineSaleAggregate(
        companyId: 'company-restart',
        localSaleId: 'local_sale_req_restart',
      );
      final actions = await OfflineStore.instance.listPendingActions(
        companyId: 'company-restart',
        userId: 'user-restart',
      );

      expect(aggregate, isNotNull);
      expect(aggregate!['items'], hasLength(2));
      expect(aggregate['payments'], hasLength(1));
      expect(aggregate['inventoryIntents'], hasLength(2));
      expect(actions, hasLength(1));
      expect(actions.single.idempotencyKey, 'sale_req_restart');
    });

    test(
      'recovers stale syncing action without changing idempotency',
      () async {
        final stale =
            _pendingSaleAction(
              companyId: 'company-stale',
              userId: 'user-stale',
              localSaleId: 'local_sale_req_stale',
              clientRequestId: 'sale_req_stale',
            ).copyWith(
              status: 'syncing',
              attempts: 1,
              lastAttemptAt: DateTime.now().toUtc().subtract(
                const Duration(minutes: 10),
              ),
            );
        await OfflineStore.instance.putPendingAction(stale);

        await OfflineStore.instance.recoverStaleSyncingActions(
          olderThan: const Duration(minutes: 2),
          companyId: 'company-stale',
          userId: 'user-stale',
        );

        final actions = await OfflineStore.instance.listPendingActions(
          companyId: 'company-stale',
          userId: 'user-stale',
        );

        expect(actions, hasLength(1));
        expect(actions.single.status, 'pending');
        expect(actions.single.idempotencyKey, 'sale_req_stale');
      },
    );
  });
}

PendingSyncAction _pendingSaleAction({
  required String companyId,
  required String userId,
  required String localSaleId,
  required String clientRequestId,
}) {
  final now = DateTime.utc(2026, 8, 19, 12);
  return PendingSyncAction(
    id: 'sales.create:$localSaleId',
    type: 'sales.create',
    scope: 'sales',
    companyId: companyId,
    userId: userId,
    entityType: 'sale',
    entityId: localSaleId,
    idempotencyKey: clientRequestId,
    payload: _salePayload(clientRequestId),
    status: 'pending',
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _salePayload(String clientRequestId) {
  return {
    'clientRequestId': clientRequestId,
    'paymentMethod': 'cash',
    'paymentCashAmount': 100,
    'items': [_item('product-a', 1)],
  };
}

Map<String, dynamic> _item(String productId, double qty) {
  return {
    'productId': productId,
    'productName': 'Producto $productId',
    'qty': qty,
    'priceSoldUnit': 100,
    'costUnitSnapshot': 50,
  };
}
