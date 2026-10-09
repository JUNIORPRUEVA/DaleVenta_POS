import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/service_orders/data/service_orders_api.dart';
import 'package:daleventa_pos/modules/service_orders/data/service_orders_local_repository.dart';
import 'package:daleventa_pos/modules/service_orders/service_order_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'reads a bounded service order page with only visible relations',
    () async {
      final dbName =
          'service_orders_page_${DateTime.now().microsecondsSinceEpoch}.db';
      final repo = ServiceOrdersLocalRepository(databaseFileName: dbName);
      final orders = [
        for (var index = 0; index < 250; index++)
          _order(
            index,
            createdAt: DateTime(2026, 1, 1).add(Duration(days: index)),
          ),
      ];
      final clientsById = {
        for (var index = 0; index < 250; index++)
          'client-$index': _client(index),
      };
      final usersById = {
        for (var index = 0; index < 250; index++) 'user-$index': _user(index),
      };

      await repo.saveSnapshot(
        orders: orders,
        clientsById: clientsById,
        usersById: usersById,
      );

      final firstPage = await repo.readSnapshot(limit: 25);

      expect(firstPage.orders, hasLength(25));
      expect(firstPage.orders.first.id, 'order-249');
      expect(firstPage.orders.last.id, 'order-225');
      expect(
        firstPage.clientsById.keys,
        unorderedEquals([
          for (var index = 225; index < 250; index++) 'client-$index',
        ]),
      );
      expect(
        firstPage.usersById.keys,
        unorderedEquals([
          for (var index = 225; index < 250; index++) 'user-$index',
        ]),
      );
      expect(firstPage.clientsById, isNot(contains('client-0')));
      expect(firstPage.usersById, isNot(contains('user-0')));

      final secondPage = await repo.readSnapshot(limit: 25, offset: 25);

      expect(secondPage.orders.first.id, 'order-224');
      expect(secondPage.orders.last.id, 'order-200');
    },
  );

  test(
    'applies a service order delta transactionally and persists cursor',
    () async {
      final dbName =
          'service_orders_delta_${DateTime.now().microsecondsSinceEpoch}.db';
      final repo = ServiceOrdersLocalRepository(databaseFileName: dbName);
      await repo.saveSnapshot(
        orders: [
          _order(1, createdAt: DateTime(2026, 1, 1)),
          _order(2, createdAt: DateTime(2026, 1, 2)),
        ],
        clientsById: {'client-1': _client(1), 'client-2': _client(2)},
        usersById: {'user-1': _user(1), 'user-2': _user(2)},
      );

      await repo.applySyncPage(
        items: [_order(3, createdAt: DateTime(2026, 1, 3), client: _client(3))],
        tombstones: [
          ServiceOrdersSyncTombstone(
            id: 'order-1',
            reason: 'cancelled',
            deletedAt: DateTime(2026, 1, 4),
            version: DateTime(2026, 1, 4),
          ),
        ],
        nextCursor: 'cursor-page-1',
      );

      final snapshot = await repo.readSnapshot(limit: 10);

      expect(
        snapshot.orders.map((item) => item.id),
        containsAll(['order-2', 'order-3']),
      );
      expect(
        snapshot.orders.map((item) => item.id),
        isNot(contains('order-1')),
      );
      expect(snapshot.clientsById, contains('client-3'));
      expect(await repo.readSyncCursor(), 'cursor-page-1');
      expect(snapshot.lastSyncedAt, isNotNull);
    },
  );
}

ServiceOrderModel _order(
  int index, {
  required DateTime createdAt,
  ClienteModel? client,
}) {
  return ServiceOrderModel(
    id: 'order-$index',
    clientId: 'client-$index',
    client: client,
    quotationId: null,
    category: ServiceOrderCategory.camara,
    serviceType: ServiceOrderType.instalacion,
    status: ServiceOrderStatus.pendiente,
    technicalNote: null,
    extraRequirements: null,
    parentOrderId: null,
    createdById: 'user-$index',
    assignedToId: null,
    scheduledFor: null,
    finalizedAt: null,
    technicianConfirmedAt: null,
    technicianConfirmedById: null,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

ClienteModel _client(int index) {
  return ClienteModel(
    id: 'client-$index',
    ownerId: 'company-a',
    nombre: 'Cliente $index',
    telefono: '809000$index',
  );
}

UserModel _user(int index) {
  return UserModel(
    id: 'user-$index',
    email: 'user$index@example.test',
    nombreCompleto: 'Usuario $index',
    telefono: '809100$index',
  );
}
