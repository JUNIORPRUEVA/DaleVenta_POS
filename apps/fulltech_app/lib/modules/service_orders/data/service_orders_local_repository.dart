import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import 'service_orders_api.dart';
import '../service_order_models.dart';

final serviceOrdersLocalRepositoryProvider =
    Provider<ServiceOrdersLocalRepository>((ref) {
      return ServiceOrdersLocalRepository();
    });

class ServiceOrdersLocalSnapshot {
  const ServiceOrdersLocalSnapshot({
    required this.orders,
    required this.clientsById,
    required this.usersById,
    this.lastSyncedAt,
  });

  final List<ServiceOrderModel> orders;
  final Map<String, ClienteModel> clientsById;
  final Map<String, UserModel> usersById;
  final DateTime? lastSyncedAt;
}

class ServiceOrdersLocalRepository {
  static const _dbName = 'operations_local.db';
  static const _dbVersion = 2;
  static const _defaultSnapshotLimit = 200;
  static const _maxSnapshotLimit = 200;
  static const _ordersTable = 'operations_orders';
  static const _clientsTable = 'operations_clients';
  static const _usersTable = 'operations_users';
  static const _metaTable = 'operations_meta';
  static const _lastSyncedAtKey = 'last_synced_at';
  static const _syncCursorKey = 'sync_cursor';
  static const _viewerUserIdKey = 'viewer_user_id';

  Database? _database;
  ServiceOrdersLocalSnapshot? _memorySnapshot;
  String _activeViewerUserId = '';
  final String _databaseFileName;

  ServiceOrdersLocalRepository({String databaseFileName = _dbName})
    : _databaseFileName = databaseFileName;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _databaseFileName,
      version: _dbVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
      },
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_ordersTable (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_clientsTable (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_usersTable (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_operations_orders_created_at
      ON $_ordersTable(created_at DESC, id DESC)
    ''');
  }

  Future<ServiceOrdersLocalSnapshot> readSnapshot({
    int limit = _defaultSnapshotLimit,
    int offset = 0,
  }) async {
    final effectiveLimit = limit.clamp(1, _maxSnapshotLimit).toInt();
    final effectiveOffset = offset < 0 ? 0 : offset;
    final memorySnapshot = _memorySnapshot;
    if (kIsWeb && memorySnapshot != null) {
      return ServiceOrdersLocalSnapshot(
        orders: memorySnapshot.orders
            .skip(effectiveOffset)
            .take(effectiveLimit)
            .toList(growable: false),
        clientsById: memorySnapshot.clientsById,
        usersById: memorySnapshot.usersById,
        lastSyncedAt: memorySnapshot.lastSyncedAt,
      );
    }

    if (kIsWeb) {
      return const ServiceOrdersLocalSnapshot(
        orders: [],
        clientsById: {},
        usersById: {},
      );
    }

    final db = await _db;
    final orderRows = await db.query(
      _ordersTable,
      orderBy: 'created_at DESC, id DESC',
      limit: effectiveLimit,
      offset: effectiveOffset,
    );
    final metaRows = await db.query(
      _metaTable,
      where: 'key = ?',
      whereArgs: [_lastSyncedAtKey],
      limit: 1,
    );

    final orders = orderRows
        .map((row) => _decodeMap(row['payload']))
        .whereType<Map<String, dynamic>>()
        .map(ServiceOrderModel.fromJson)
        .toList(growable: false);
    final clientIds = {
      for (final order in orders)
        if (order.clientId.trim().isNotEmpty) order.clientId,
      for (final order in orders)
        if (order.client != null) order.client!.id,
    };
    final userIds = _collectUserIds(orders);
    final clientRows = await _queryRowsByIds(db, _clientsTable, clientIds);
    final userRows = await _queryRowsByIds(db, _usersTable, userIds);

    final snapshot = ServiceOrdersLocalSnapshot(
      orders: orders,
      clientsById: {
        for (final row in clientRows)
          if (((row['id'] ?? '').toString()).isNotEmpty)
            (row['id'] ?? '').toString(): ClienteModel.fromJson(
              _decodeMap(row['payload']) ?? const <String, dynamic>{},
            ),
      },
      usersById: {
        for (final row in userRows)
          if (((row['id'] ?? '').toString()).isNotEmpty)
            (row['id'] ?? '').toString(): UserModel.fromJson(
              _decodeMap(row['payload']) ?? const <String, dynamic>{},
            ),
      },
      lastSyncedAt: metaRows.isEmpty
          ? null
          : DateTime.tryParse((metaRows.first['value'] ?? '').toString()),
    );
    return snapshot;
  }

  Future<String?> readSyncCursor() async {
    if (kIsWeb) return null;
    final db = await _db;
    final rows = await db.query(
      _metaTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_syncCursorKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = (rows.first['value'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<void> applySyncPage({
    required List<ServiceOrderModel> items,
    required List<ServiceOrdersSyncTombstone> tombstones,
    required String? nextCursor,
  }) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      final nextOrders = [
        ...snapshot.orders.where(
          (order) => !tombstones.any((item) => item.id == order.id),
        ),
      ];
      for (final item in items) {
        final index = nextOrders.indexWhere((order) => order.id == item.id);
        if (index >= 0) {
          nextOrders[index] = item;
        } else {
          nextOrders.add(item);
        }
      }
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: nextOrders,
        clientsById: {
          ...snapshot.clientsById,
          for (final item in items)
            if (item.client != null) item.client!.id: item.client!,
        },
        usersById: snapshot.usersById,
        lastSyncedAt: DateTime.now(),
      );
      return;
    }

    final db = await _db;
    _memorySnapshot = null;
    await db.transaction((txn) async {
      for (final tombstone in tombstones) {
        await txn.delete(
          _ordersTable,
          where: 'id = ?',
          whereArgs: [tombstone.id],
        );
      }

      for (final order in items) {
        await txn.insert(_ordersTable, {
          'id': order.id,
          'created_at': order.createdAt.toIso8601String(),
          'updated_at': order.updatedAt.toIso8601String(),
          'payload': jsonEncode(order.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final client = order.client;
        if (client != null) {
          await txn.insert(_clientsTable, {
            'id': client.id,
            'payload': jsonEncode(client.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      if ((nextCursor ?? '').trim().isNotEmpty) {
        await txn.insert(_metaTable, {
          'key': _syncCursorKey,
          'value': nextCursor!.trim(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert(_metaTable, {
        'key': _lastSyncedAtKey,
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(_metaTable, {
        'key': _viewerUserIdKey,
        'value': _activeViewerUserId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> prepareForViewer(String viewerUserId) async {
    final normalizedViewerUserId = viewerUserId.trim();
    if (_activeViewerUserId == normalizedViewerUserId) {
      return;
    }

    _activeViewerUserId = normalizedViewerUserId;
    _memorySnapshot = null;

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    final rows = await db.query(
      _metaTable,
      where: 'key = ?',
      whereArgs: [_viewerUserIdKey],
      limit: 1,
    );
    final storedViewerUserId = rows.isEmpty
        ? ''
        : (rows.first['value'] ?? '').toString().trim();

    if (storedViewerUserId.isEmpty ||
        storedViewerUserId == normalizedViewerUserId) {
      return;
    }

    await clearSnapshot();
  }

  Future<ServiceOrderModel?> readOrder(String id) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      for (final order in snapshot.orders) {
        if (order.id == id) return order;
      }
      return null;
    }

    final db = await _db;
    final rows = await db.query(
      _ordersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = _decodeMap(rows.first['payload']);
    if (payload == null) return null;
    return ServiceOrderModel.fromJson(payload);
  }

  Future<void> saveSnapshot({
    required List<ServiceOrderModel> orders,
    required Map<String, ClienteModel> clientsById,
    required Map<String, UserModel> usersById,
  }) async {
    if (kIsWeb) {
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: orders.toList(growable: false),
        clientsById: Map<String, ClienteModel>.from(clientsById),
        usersById: Map<String, UserModel>.from(usersById),
        lastSyncedAt: DateTime.now(),
      );
      return;
    }

    _memorySnapshot = null;
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_ordersTable);
      for (final order in orders) {
        await txn.insert(_ordersTable, {
          'id': order.id,
          'created_at': order.createdAt.toIso8601String(),
          'updated_at': order.updatedAt.toIso8601String(),
          'payload': jsonEncode(order.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete(_clientsTable);
      for (final entry in clientsById.entries) {
        await txn.insert(_clientsTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete(_usersTable);
      for (final entry in usersById.entries) {
        await txn.insert(_usersTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.insert(_metaTable, {
        'key': _lastSyncedAtKey,
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(_metaTable, {
        'key': _viewerUserIdKey,
        'value': _activeViewerUserId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> saveOrder({
    required ServiceOrderModel order,
    ClienteModel? client,
    Map<String, UserModel> usersById = const {},
  }) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      final nextOrders = [...snapshot.orders];
      final index = nextOrders.indexWhere((item) => item.id == order.id);
      if (index >= 0) {
        nextOrders[index] = order;
      } else {
        nextOrders.add(order);
      }
      final nextClients = Map<String, ClienteModel>.from(snapshot.clientsById);
      final effectiveClient = client ?? order.client;
      if (effectiveClient != null) {
        nextClients[effectiveClient.id] = effectiveClient;
      }
      final nextUsers = Map<String, UserModel>.from(snapshot.usersById)
        ..addAll(usersById);
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: nextOrders,
        clientsById: nextClients,
        usersById: nextUsers,
        lastSyncedAt: DateTime.now(),
      );
      return;
    }

    final db = await _db;
    _memorySnapshot = null;
    await db.transaction((txn) async {
      await txn.insert(_ordersTable, {
        'id': order.id,
        'created_at': order.createdAt.toIso8601String(),
        'updated_at': order.updatedAt.toIso8601String(),
        'payload': jsonEncode(order.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final effectiveClient = client ?? order.client;
      if (effectiveClient != null) {
        await txn.insert(_clientsTable, {
          'id': effectiveClient.id,
          'payload': jsonEncode(effectiveClient.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final entry in usersById.entries) {
        await txn.insert(_usersTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.insert(_metaTable, {
        'key': _viewerUserIdKey,
        'value': _activeViewerUserId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteOrder(String id) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: snapshot.orders
            .where((item) => item.id != id)
            .toList(growable: false),
        clientsById: snapshot.clientsById,
        usersById: snapshot.usersById,
        lastSyncedAt: snapshot.lastSyncedAt,
      );
      return;
    }

    final db = await _db;
    _memorySnapshot = null;
    await db.delete(_ordersTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSnapshot() async {
    _memorySnapshot = const ServiceOrdersLocalSnapshot(
      orders: [],
      clientsById: {},
      usersById: {},
    );

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_ordersTable);
      await txn.delete(_clientsTable);
      await txn.delete(_usersTable);
      await txn.delete(
        _metaTable,
        where: 'key = ?',
        whereArgs: [_lastSyncedAtKey],
      );
      await txn.delete(
        _metaTable,
        where: 'key = ?',
        whereArgs: [_viewerUserIdKey],
      );
      await txn.delete(
        _metaTable,
        where: 'key = ?',
        whereArgs: [_syncCursorKey],
      );
    });
  }

  Future<Map<String, UserModel>> readUsersById() async {
    if (kIsWeb) {
      return Map<String, UserModel>.from((await readSnapshot()).usersById);
    }

    final db = await _db;
    final rows = await db.query(_usersTable);
    return {
      for (final row in rows)
        if (((row['id'] ?? '').toString()).isNotEmpty)
          (row['id'] ?? '').toString(): UserModel.fromJson(
            _decodeMap(row['payload']) ?? const <String, dynamic>{},
          ),
    };
  }

  Set<String> _collectUserIds(List<ServiceOrderModel> orders) {
    final ids = <String>{};
    void add(String? id) {
      final normalized = (id ?? '').trim();
      if (normalized.isNotEmpty) ids.add(normalized);
    }

    for (final order in orders) {
      add(order.createdById);
      add(order.assignedToId);
      add(order.technicianConfirmedById);
      add(order.lastStatusChangedByUserId);
      for (final entry in order.statusHistory) {
        add(entry.changedByUserId);
      }
      for (final evidence in order.evidences) {
        add(evidence.createdById);
      }
      for (final report in order.reports) {
        add(report.createdById);
      }
    }
    return ids;
  }

  Future<List<Map<String, Object?>>> _queryRowsByIds(
    Database db,
    String table,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const <Map<String, Object?>>[];
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.query(
      table,
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(growable: false),
    );
  }

  Future<ClienteModel?> readClientById(String id) async {
    if (kIsWeb) {
      return (await readSnapshot()).clientsById[id];
    }

    final db = await _db;
    final rows = await db.query(
      _clientsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = _decodeMap(rows.first['payload']);
    if (payload == null) return null;
    return ClienteModel.fromJson(payload);
  }

  Map<String, dynamic>? _decodeMap(Object? raw) {
    final value = (raw ?? '').toString();
    if (value.trim().isEmpty) return null;
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }
}
