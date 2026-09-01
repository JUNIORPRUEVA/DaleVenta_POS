import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../debug/app_error_reporter.dart';
import '../debug/trace_log.dart';
import '../storage/resilient_local_database.dart';
import 'pending_sync_action.dart';

class OfflineStore {
  OfflineStore._({String databaseFileName = 'fulltech_offline.db'})
    : _databaseFileName = databaseFileName;

  static final OfflineStore instance = OfflineStore._();

  @visibleForTesting
  factory OfflineStore.forTesting(String databaseFileName) {
    return OfflineStore._(databaseFileName: databaseFileName);
  }

  static const String _webCachePrefix = 'ft_db_cache:';
  static const String _webPendingKey = 'ft_db_pending_actions';
  static const String _webOfflineSalesKey = 'ft_db_offline_sales';

  final String _databaseFileName;
  Database? _database;
  Future<Database>? _opening;
  bool _preferencesFallbackEnabled = false;

  Future<Database?> _dbOrNull() async {
    if (kIsWeb || _preferencesFallbackEnabled) return null;
    if (_database != null) return _database;
    if (_opening != null) {
      try {
        return await _opening!;
      } catch (_) {
        return null;
      }
    }

    _opening = _openDatabase();
    try {
      final db = await _opening!;
      _database = db;
      return db;
    } catch (error, stackTrace) {
      _enablePreferencesFallback(error, stackTrace);
      return null;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _openDatabase() async {
    TraceLog.log('offline_store', 'opening sqlite db path=$_databaseFileName');
    return openResilientLocalDatabase(
      fileName: _databaseFileName,
      version: 3,
      allowInMemoryFallback: false,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache_entries (
            cache_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_actions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            scope TEXT NOT NULL,
            company_id TEXT,
            user_id TEXT,
            terminal_id TEXT,
            entity_type TEXT,
            entity_id TEXT,
            idempotency_key TEXT,
            payload TEXT NOT NULL,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            error TEXT,
            next_attempt_at INTEGER,
            last_attempt_at INTEGER,
            permanent INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createOfflineSalesTables(db);
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, 'pending_actions', 'company_id TEXT');
          await _addColumnIfMissing(db, 'pending_actions', 'user_id TEXT');
          await _addColumnIfMissing(db, 'pending_actions', 'terminal_id TEXT');
          await _addColumnIfMissing(db, 'pending_actions', 'entity_type TEXT');
          await _addColumnIfMissing(db, 'pending_actions', 'entity_id TEXT');
          await _addColumnIfMissing(
            db,
            'pending_actions',
            'idempotency_key TEXT',
          );
          await _addColumnIfMissing(
            db,
            'pending_actions',
            'next_attempt_at INTEGER',
          );
          await _addColumnIfMissing(
            db,
            'pending_actions',
            'last_attempt_at INTEGER',
          );
          await _addColumnIfMissing(
            db,
            'pending_actions',
            'permanent INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await _createOfflineSalesTables(db);
          await _createIndexes(db);
        }
      },
    );
  }

  Future<void> _createOfflineSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sales (
        local_id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        server_id TEXT,
        client_request_id TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        total_sold REAL NOT NULL DEFAULT 0,
        sale_occurred_at INTEGER NOT NULL,
        synced_at INTEGER,
        error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sale_items (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        product_id TEXT,
        product_name_snapshot TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (sale_local_id) REFERENCES offline_sales(local_id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sale_payments (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        method TEXT NOT NULL,
        cash_amount REAL NOT NULL DEFAULT 0,
        transfer_amount REAL NOT NULL DEFAULT 0,
        credit_amount REAL NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (sale_local_id) REFERENCES offline_sales(local_id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_inventory_intents (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        product_id TEXT,
        quantity_delta REAL NOT NULL,
        idempotency_key TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (sale_local_id) REFERENCES offline_sales(local_id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_actions_scope_status_next
      ON pending_actions(company_id, user_id, status, next_attempt_at, created_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_actions_type_entity
      ON pending_actions(type, entity_type, entity_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_actions_scope_idempotency
      ON pending_actions(company_id, idempotency_key)
      WHERE idempotency_key IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cache_entries_updated
      ON cache_entries(updated_at)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_sales_scope_request
      ON offline_sales(company_id, client_request_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_sales_scope_status
      ON offline_sales(company_id, user_id, status, sale_occurred_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_sale_items_sale
      ON offline_sale_items(sale_local_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_sale_payments_sale
      ON offline_sale_payments(sale_local_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_inventory_intents_once
      ON offline_inventory_intents(company_id, idempotency_key)
    ''');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String columnDefinition,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (!message.contains('duplicate column') &&
          !message.contains('already exists')) {
        rethrow;
      }
    }
  }

  void _enablePreferencesFallback(Object error, StackTrace stackTrace) {
    if (_preferencesFallbackEnabled) return;
    _preferencesFallbackEnabled = true;
    TraceLog.log(
      'offline_store',
      'sqlite unavailable, switching to shared preferences fallback',
      error: error,
      stackTrace: stackTrace,
    );
    AppErrorReporter.instance.record(
      error,
      stackTrace,
      context: 'OfflineStore.SQLite',
      title: 'Modo offline limitado',
      userMessage:
          'No pudimos iniciar la base local del dispositivo. La app seguira funcionando con almacenamiento alternativo y sincronizacion protegida.',
      technicalDetails:
          'SQLite no pudo abrir el archivo local; se activo el fallback de SharedPreferences para evitar bloqueo del sistema.',
      severity: AppErrorSeverity.warning,
      dedupeKey: 'offline-store-sqlite-open-failed',
    );
  }

  Future<Map<String, dynamic>?> readCacheEntry(
    String key, {
    Duration? maxAge,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_webCachePrefix$key');
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final updatedAtMs = (decoded['updatedAtMs'] as num?)?.toInt();
      if (maxAge != null && updatedAtMs != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
        );
        if (age > maxAge) return null;
      }
      final payload = decoded['payload'];
      if (payload is Map) return payload.cast<String, dynamic>();
      return null;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_webCachePrefix$key');
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final updatedAtMs = (decoded['updatedAtMs'] as num?)?.toInt();
      if (maxAge != null && updatedAtMs != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
        );
        if (age > maxAge) return null;
      }
      final payload = decoded['payload'];
      if (payload is Map) return payload.cast<String, dynamic>();
      return null;
    }

    final rows = await db.query(
      'cache_entries',
      columns: ['payload', 'updated_at'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final updatedAtMs = (row['updated_at'] as num?)?.toInt();
    if (maxAge != null && updatedAtMs != null) {
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      );
      if (age > maxAge) return null;
    }

    final payload = jsonDecode((row['payload'] ?? '{}').toString());
    if (payload is Map) return payload.cast<String, dynamic>();
    return null;
  }

  Future<void> writeCacheEntry(String key, Map<String, dynamic> payload) async {
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_webCachePrefix$key',
        jsonEncode({'payload': payload, 'updatedAtMs': updatedAtMs}),
      );
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_webCachePrefix$key',
        jsonEncode({'payload': payload, 'updatedAtMs': updatedAtMs}),
      );
      return;
    }

    await db.insert('cache_entries', {
      'cache_key': key,
      'payload': jsonEncode(payload),
      'updated_at': updatedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeCacheEntry(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_webCachePrefix$key');
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_webCachePrefix$key');
      return;
    }

    await db.delete('cache_entries', where: 'cache_key = ?', whereArgs: [key]);
  }

  Future<void> clearCacheEntries() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(_webCachePrefix))
          .toList(growable: false);
      for (final key in keys) {
        await prefs.remove(key);
      }
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(_webCachePrefix))
          .toList(growable: false);
      for (final key in keys) {
        await prefs.remove(key);
      }
      return;
    }

    await db.delete('cache_entries');
  }

  Future<void> clearAll({bool includePendingActions = true}) async {
    await clearCacheEntries();
    if (!includePendingActions) return;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_webPendingKey);
      await prefs.remove(_webOfflineSalesKey);
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_webPendingKey);
      await prefs.remove(_webOfflineSalesKey);
      return;
    }

    await db.delete('pending_actions');
    await db.delete('offline_inventory_intents');
    await db.delete('offline_sale_payments');
    await db.delete('offline_sale_items');
    await db.delete('offline_sales');
  }

  Future<void> saveOfflineSaleAtomically({
    required String localSaleId,
    required String companyId,
    required String userId,
    required String clientRequestId,
    required Map<String, dynamic> salePayload,
    required List<Map<String, dynamic>> itemPayloads,
    required Map<String, dynamic> paymentPayload,
    required PendingSyncAction pendingAction,
    required double totalSold,
    DateTime? saleOccurredAt,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanUserId = userId.trim();
    final cleanLocalSaleId = localSaleId.trim();
    final cleanRequestId = clientRequestId.trim();
    if (cleanCompanyId.isEmpty ||
        cleanUserId.isEmpty ||
        cleanLocalSaleId.isEmpty ||
        cleanRequestId.isEmpty ||
        itemPayloads.isEmpty) {
      throw StateError('Offline sale requires company, user, id and items');
    }

    final occurredAt = (saleOccurredAt ?? DateTime.now()).toUtc();
    final now = DateTime.now().toUtc();

    if (kIsWeb) {
      await _saveOfflineSaleInPreferences(
        localSaleId: cleanLocalSaleId,
        companyId: cleanCompanyId,
        userId: cleanUserId,
        clientRequestId: cleanRequestId,
        salePayload: salePayload,
        itemPayloads: itemPayloads,
        paymentPayload: paymentPayload,
        pendingAction: pendingAction,
        totalSold: totalSold,
        saleOccurredAt: occurredAt,
        now: now,
      );
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      await _saveOfflineSaleInPreferences(
        localSaleId: cleanLocalSaleId,
        companyId: cleanCompanyId,
        userId: cleanUserId,
        clientRequestId: cleanRequestId,
        salePayload: salePayload,
        itemPayloads: itemPayloads,
        paymentPayload: paymentPayload,
        pendingAction: pendingAction,
        totalSold: totalSold,
        saleOccurredAt: occurredAt,
        now: now,
      );
      return;
    }

    await db.transaction((txn) async {
      await txn.insert('offline_sales', {
        'local_id': cleanLocalSaleId,
        'company_id': cleanCompanyId,
        'user_id': cleanUserId,
        'server_id': null,
        'client_request_id': cleanRequestId,
        'status': 'pending',
        'payload': jsonEncode(salePayload),
        'total_sold': totalSold,
        'sale_occurred_at': occurredAt.millisecondsSinceEpoch,
        'synced_at': null,
        'error': null,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'offline_sale_items',
        where: 'sale_local_id = ?',
        whereArgs: [cleanLocalSaleId],
      );
      for (var index = 0; index < itemPayloads.length; index += 1) {
        final item = itemPayloads[index];
        await txn.insert('offline_sale_items', {
          'id': '${cleanLocalSaleId}_item_$index',
          'sale_local_id': cleanLocalSaleId,
          'company_id': cleanCompanyId,
          'product_id': item['productId']?.toString(),
          'product_name_snapshot':
              (item['productName'] ?? item['productNameSnapshot'] ?? 'Producto')
                  .toString(),
          'qty': _asDouble(item['qty']),
          'unit_price': _asDouble(item['priceSoldUnit']),
          'payload': jsonEncode(item),
          'created_at': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete(
        'offline_sale_payments',
        where: 'sale_local_id = ?',
        whereArgs: [cleanLocalSaleId],
      );
      await txn.insert('offline_sale_payments', {
        'id': '${cleanLocalSaleId}_payment',
        'sale_local_id': cleanLocalSaleId,
        'company_id': cleanCompanyId,
        'method': (paymentPayload['paymentMethod'] ?? 'cash').toString(),
        'cash_amount': _asDouble(paymentPayload['paymentCashAmount']),
        'transfer_amount': _asDouble(paymentPayload['paymentTransferAmount']),
        'credit_amount': _asDouble(paymentPayload['creditAmount']),
        'payload': jsonEncode(paymentPayload),
        'created_at': now.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'offline_inventory_intents',
        where: 'sale_local_id = ?',
        whereArgs: [cleanLocalSaleId],
      );
      for (var index = 0; index < itemPayloads.length; index += 1) {
        final item = itemPayloads[index];
        final productId = item['productId']?.toString().trim();
        if (productId == null || productId.isEmpty) continue;
        await txn.insert(
          'offline_inventory_intents',
          {
            'id': '${cleanLocalSaleId}_inventory_$index',
            'sale_local_id': cleanLocalSaleId,
            'company_id': cleanCompanyId,
            'product_id': productId,
            'quantity_delta': -_asDouble(item['qty']),
            'idempotency_key': '$cleanRequestId:inventory:$index',
            'status': 'pending',
            'payload': jsonEncode({
              'saleLocalId': cleanLocalSaleId,
              'productId': productId,
              'quantityDelta': -_asDouble(item['qty']),
            }),
            'created_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert('pending_actions', {
        'id': pendingAction.id,
        'type': pendingAction.type,
        'scope': pendingAction.scope,
        'company_id': pendingAction.companyId,
        'user_id': pendingAction.userId,
        'terminal_id': pendingAction.terminalId,
        'entity_type': pendingAction.entityType,
        'entity_id': pendingAction.entityId,
        'idempotency_key': pendingAction.idempotencyKey,
        'payload': jsonEncode(pendingAction.payload),
        'status': pendingAction.status,
        'attempts': pendingAction.attempts,
        'error': pendingAction.error,
        'next_attempt_at': pendingAction.nextAttemptAt?.millisecondsSinceEpoch,
        'last_attempt_at': pendingAction.lastAttemptAt?.millisecondsSinceEpoch,
        'permanent': pendingAction.permanent ? 1 : 0,
        'created_at': pendingAction.createdAt.millisecondsSinceEpoch,
        'updated_at': pendingAction.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _saveOfflineSaleInPreferences({
    required String localSaleId,
    required String companyId,
    required String userId,
    required String clientRequestId,
    required Map<String, dynamic> salePayload,
    required List<Map<String, dynamic>> itemPayloads,
    required Map<String, dynamic> paymentPayload,
    required PendingSyncAction pendingAction,
    required double totalSold,
    required DateTime saleOccurredAt,
    required DateTime now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_webOfflineSalesKey);
    final decoded = raw == null || raw.trim().isEmpty
        ? const <dynamic>[]
        : jsonDecode(raw);
    final rows = decoded is List ? decoded : const <dynamic>[];
    final nextRows = [
      for (final row in rows)
        if (row is! Map ||
            row['localId']?.toString() != localSaleId ||
            row['companyId']?.toString() != companyId)
          row,
      {
        'localId': localSaleId,
        'companyId': companyId,
        'userId': userId,
        'serverId': null,
        'clientRequestId': clientRequestId,
        'status': 'pending',
        'payload': salePayload,
        'items': itemPayloads,
        'payment': paymentPayload,
        'inventoryIntents': [
          for (var index = 0; index < itemPayloads.length; index += 1)
            if ((itemPayloads[index]['productId']?.toString().trim() ?? '')
                .isNotEmpty)
              {
                'id': '${localSaleId}_inventory_$index',
                'productId': itemPayloads[index]['productId']?.toString(),
                'quantityDelta': -_asDouble(itemPayloads[index]['qty']),
                'idempotencyKey': '$clientRequestId:inventory:$index',
                'status': 'pending',
              },
        ],
        'totalSold': totalSold,
        'saleOccurredAt': saleOccurredAt.toIso8601String(),
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
    ];
    await prefs.setString(_webOfflineSalesKey, jsonEncode(nextRows));
    await putPendingAction(pendingAction);
  }

  Future<void> markOfflineSaleSynced({
    required String companyId,
    required String clientRequestId,
    required String serverSaleId,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanRequestId = clientRequestId.trim();
    final cleanServerId = serverSaleId.trim();
    if (cleanCompanyId.isEmpty ||
        cleanRequestId.isEmpty ||
        cleanServerId.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webOfflineSalesKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final nextRows = decoded
          .map((row) {
            if (row is! Map) return row;
            if (row['companyId']?.toString() != cleanCompanyId ||
                row['clientRequestId']?.toString() != cleanRequestId) {
              return row;
            }
            return {
              ...row.cast<String, dynamic>(),
              'serverId': cleanServerId,
              'status': 'synced',
              'syncedAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
            };
          })
          .toList(growable: false);
      await prefs.setString(_webOfflineSalesKey, jsonEncode(nextRows));
      return;
    }

    final db = await _dbOrNull();
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.update(
        'offline_sales',
        {
          'server_id': cleanServerId,
          'status': 'synced',
          'synced_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'company_id = ? AND client_request_id = ?',
        whereArgs: [cleanCompanyId, cleanRequestId],
      );
      await txn.update(
        'offline_inventory_intents',
        {'status': 'synced', 'updated_at': now.millisecondsSinceEpoch},
        where: 'company_id = ? AND idempotency_key LIKE ? AND status != ?',
        whereArgs: [cleanCompanyId, '$cleanRequestId:inventory:%', 'synced'],
      );
    });
  }

  Future<void> markOfflineSaleConflict({
    required String companyId,
    required String clientRequestId,
    required Map<String, dynamic> conflict,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanRequestId = clientRequestId.trim();
    if (cleanCompanyId.isEmpty || cleanRequestId.isEmpty) return;
    final now = DateTime.now().toUtc();
    final encoded = jsonEncode(conflict);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webOfflineSalesKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final nextRows = decoded
          .map((row) {
            if (row is! Map) return row;
            if (row['companyId']?.toString() != cleanCompanyId ||
                row['clientRequestId']?.toString() != cleanRequestId) {
              return row;
            }
            return {
              ...row.cast<String, dynamic>(),
              'status': 'conflict',
              'error': encoded,
              'updatedAt': now.toIso8601String(),
            };
          })
          .toList(growable: false);
      await prefs.setString(_webOfflineSalesKey, jsonEncode(nextRows));
      return;
    }

    final db = await _dbOrNull();
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.update(
        'offline_sales',
        {
          'status': 'conflict',
          'error': encoded,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'company_id = ? AND client_request_id = ?',
        whereArgs: [cleanCompanyId, cleanRequestId],
      );
      await txn.update(
        'offline_inventory_intents',
        {'status': 'conflict', 'updated_at': now.millisecondsSinceEpoch},
        where: 'company_id = ? AND idempotency_key LIKE ? AND status != ?',
        whereArgs: [cleanCompanyId, '$cleanRequestId:inventory:%', 'synced'],
      );
    });
  }

  Future<void> recoverStaleSyncingActions({
    required Duration olderThan,
    String? companyId,
    String? userId,
  }) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(olderThan)
        .millisecondsSinceEpoch;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webPendingKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final next = decoded
          .whereType<Map>()
          .map((row) => PendingSyncAction.fromMap(row.cast<String, dynamic>()))
          .map((action) {
            final lastAttemptMs = action.lastAttemptAt?.millisecondsSinceEpoch;
            final matchesCompany =
                companyId == null || action.companyId == companyId;
            final matchesUser = userId == null || action.userId == userId;
            final stale =
                action.status == 'syncing' &&
                matchesCompany &&
                matchesUser &&
                (lastAttemptMs == null || lastAttemptMs <= cutoff);
            return stale
                ? action.copyWith(
                    status: 'pending',
                    clearError: true,
                    clearNextAttemptAt: true,
                    updatedAt: DateTime.now().toUtc(),
                  )
                : action;
          })
          .map((action) => action.toMap())
          .toList(growable: false);
      await prefs.setString(_webPendingKey, jsonEncode(next));
      return;
    }

    final db = await _dbOrNull();
    if (db == null) return;
    final where = <String>[
      'status = ?',
      '(last_attempt_at IS NULL OR last_attempt_at <= ?)',
    ];
    final whereArgs = <Object?>['syncing', cutoff];
    if (companyId != null) {
      where.add('company_id = ?');
      whereArgs.add(companyId);
    }
    if (userId != null) {
      where.add('user_id = ?');
      whereArgs.add(userId);
    }
    await db.update(
      'pending_actions',
      {
        'status': 'pending',
        'error': null,
        'next_attempt_at': null,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: where.join(' AND '),
      whereArgs: whereArgs,
    );
  }

  Future<List<Map<String, dynamic>>> listOfflineSales({
    required String companyId,
    String? userId,
    String? status,
    int limit = 100,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanUserId = userId?.trim();
    final cleanStatus = status?.trim();
    if (cleanCompanyId.isEmpty) return const [];

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webOfflineSalesKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .where(
            (row) =>
                row['companyId']?.toString() == cleanCompanyId &&
                ((cleanUserId ?? '').isEmpty ||
                    row['userId']?.toString() == cleanUserId) &&
                ((cleanStatus ?? '').isEmpty ||
                    row['status']?.toString() == cleanStatus),
          )
          .take(limit)
          .toList(growable: false);
    }

    final db = await _dbOrNull();
    if (db == null) return const [];
    final where = <String>['company_id = ?'];
    final whereArgs = <Object?>[cleanCompanyId];
    if ((cleanUserId ?? '').isNotEmpty) {
      where.add('user_id = ?');
      whereArgs.add(cleanUserId);
    }
    if ((cleanStatus ?? '').isNotEmpty) {
      where.add('status = ?');
      whereArgs.add(cleanStatus);
    }
    final rows = await db.query(
      'offline_sales',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'sale_occurred_at DESC',
      limit: limit,
    );
    return rows.map(_offlineSaleRowToMap).toList(growable: false);
  }

  Future<Map<String, dynamic>?> getOfflineSaleAggregate({
    required String companyId,
    required String localSaleId,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanLocalSaleId = localSaleId.trim();
    if (cleanCompanyId.isEmpty || cleanLocalSaleId.isEmpty) return null;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webOfflineSalesKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      for (final row in decoded.whereType<Map>()) {
        if (row['companyId']?.toString() == cleanCompanyId &&
            row['localId']?.toString() == cleanLocalSaleId) {
          return row.cast<String, dynamic>();
        }
      }
      return null;
    }

    final db = await _dbOrNull();
    if (db == null) return null;
    final saleRows = await db.query(
      'offline_sales',
      where: 'company_id = ? AND local_id = ?',
      whereArgs: [cleanCompanyId, cleanLocalSaleId],
      limit: 1,
    );
    if (saleRows.isEmpty) return null;
    final items = await db.query(
      'offline_sale_items',
      where: 'company_id = ? AND sale_local_id = ?',
      whereArgs: [cleanCompanyId, cleanLocalSaleId],
      orderBy: 'created_at ASC',
    );
    final payments = await db.query(
      'offline_sale_payments',
      where: 'company_id = ? AND sale_local_id = ?',
      whereArgs: [cleanCompanyId, cleanLocalSaleId],
      orderBy: 'created_at ASC',
    );
    final inventoryIntents = await db.query(
      'offline_inventory_intents',
      where: 'company_id = ? AND sale_local_id = ?',
      whereArgs: [cleanCompanyId, cleanLocalSaleId],
      orderBy: 'created_at ASC',
    );
    return {
      ..._offlineSaleRowToMap(saleRows.single),
      'items': items
          .map((row) => jsonDecode((row['payload'] ?? '{}').toString()))
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(growable: false),
      'payments': payments
          .map((row) => jsonDecode((row['payload'] ?? '{}').toString()))
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(growable: false),
      'inventoryIntents': inventoryIntents
          .map((row) => jsonDecode((row['payload'] ?? '{}').toString()))
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(growable: false),
    };
  }

  Future<void> closeForTesting() async {
    await _database?.close();
    _database = null;
    _opening = null;
    _preferencesFallbackEnabled = false;
  }

  Future<void> putPendingAction(PendingSyncAction action) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final items = await listPendingActions();
      final next = [
        for (final item in items)
          if (item.id != action.id) item,
        action,
      ];
      await prefs.setString(
        _webPendingKey,
        jsonEncode(next.map((item) => item.toMap()).toList()),
      );
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final items = await listPendingActions();
      final next = [
        for (final item in items)
          if (item.id != action.id) item,
        action,
      ];
      await prefs.setString(
        _webPendingKey,
        jsonEncode(next.map((item) => item.toMap()).toList()),
      );
      return;
    }

    await db.insert('pending_actions', {
      'id': action.id,
      'type': action.type,
      'scope': action.scope,
      'company_id': action.companyId,
      'user_id': action.userId,
      'terminal_id': action.terminalId,
      'entity_type': action.entityType,
      'entity_id': action.entityId,
      'idempotency_key': action.idempotencyKey,
      'payload': jsonEncode(action.payload),
      'status': action.status,
      'attempts': action.attempts,
      'error': action.error,
      'next_attempt_at': action.nextAttemptAt?.millisecondsSinceEpoch,
      'last_attempt_at': action.lastAttemptAt?.millisecondsSinceEpoch,
      'permanent': action.permanent ? 1 : 0,
      'created_at': action.createdAt.millisecondsSinceEpoch,
      'updated_at': action.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingSyncAction>> listPendingActions({
    int limit = 50,
    String? companyId,
    String? userId,
    bool includeUnscoped = false,
    bool dueOnly = false,
  }) async {
    bool matchesScope(PendingSyncAction action) {
      final actionCompany = action.companyId?.trim();
      final actionUser = action.userId?.trim();
      final companyMatches = companyId == null
          ? true
          : actionCompany == companyId ||
                (includeUnscoped && actionCompany == null);
      final userMatches = userId == null
          ? true
          : actionUser == userId || (includeUnscoped && actionUser == null);
      if (!companyMatches || !userMatches) return false;
      if (!dueOnly) return true;
      final next = action.nextAttemptAt;
      return next == null || !next.isAfter(DateTime.now().toUtc());
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webPendingKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => PendingSyncAction.fromMap(row.cast<String, dynamic>()))
          .where(matchesScope)
          .take(limit)
          .toList(growable: false)
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webPendingKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => PendingSyncAction.fromMap(row.cast<String, dynamic>()))
          .where(matchesScope)
          .take(limit)
          .toList(growable: false)
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }

    final where = <String>[];
    final whereArgs = <Object?>[];
    if (companyId != null) {
      where.add(
        includeUnscoped
            ? '(company_id = ? OR company_id IS NULL)'
            : 'company_id = ?',
      );
      whereArgs.add(companyId);
    }
    if (userId != null) {
      where.add(
        includeUnscoped ? '(user_id = ? OR user_id IS NULL)' : 'user_id = ?',
      );
      whereArgs.add(userId);
    }
    if (dueOnly) {
      where.add('(next_attempt_at IS NULL OR next_attempt_at <= ?)');
      whereArgs.add(DateTime.now().toUtc().millisecondsSinceEpoch);
    }

    final rows = await db.query(
      'pending_actions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows
        .map(
          (row) => PendingSyncAction.fromMap({
            'id': row['id'],
            'type': row['type'],
            'scope': row['scope'],
            'companyId': row['company_id'],
            'userId': row['user_id'],
            'terminalId': row['terminal_id'],
            'entityType': row['entity_type'],
            'entityId': row['entity_id'],
            'idempotencyKey': row['idempotency_key'],
            'payload': jsonDecode((row['payload'] ?? '{}').toString()),
            'status': row['status'],
            'attempts': row['attempts'],
            'error': row['error'],
            'nextAttemptAt': row['next_attempt_at'],
            'lastAttemptAt': row['last_attempt_at'],
            'permanent': row['permanent'],
            'createdAt': DateTime.fromMillisecondsSinceEpoch(
              (row['created_at'] as num?)?.toInt() ?? 0,
            ).toUtc().toIso8601String(),
            'updatedAt': DateTime.fromMillisecondsSinceEpoch(
              (row['updated_at'] as num?)?.toInt() ?? 0,
            ).toUtc().toIso8601String(),
          }),
        )
        .toList(growable: false);
  }

  Future<void> removePendingAction(String id) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final next = (await listPendingActions())
          .where((item) => item.id != id)
          .map((item) => item.toMap())
          .toList(growable: false);
      await prefs.setString(_webPendingKey, jsonEncode(next));
      return;
    }

    final db = await _dbOrNull();
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final next = (await listPendingActions())
          .where((item) => item.id != id)
          .map((item) => item.toMap())
          .toList(growable: false);
      await prefs.setString(_webPendingKey, jsonEncode(next));
      return;
    }

    await db.delete('pending_actions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePendingAction(PendingSyncAction action) async {
    await putPendingAction(action);
  }

  Future<Map<String, int>> pendingActionStats({
    String? companyId,
    String? userId,
    bool includeUnscoped = false,
  }) async {
    final actions = await listPendingActions(
      limit: 500,
      companyId: companyId,
      userId: userId,
      includeUnscoped: includeUnscoped,
    );
    var pending = 0;
    var syncing = 0;
    var error = 0;
    var conflict = 0;

    for (final action in actions) {
      switch (action.status) {
        case 'syncing':
          syncing++;
          break;
        case 'conflict':
        case 'requires_action':
          conflict++;
          break;
        case 'error':
        case 'failed':
        case 'auth_blocked':
        case 'tenant_mismatch':
          error++;
          break;
        default:
          pending++;
          break;
      }
    }

    TraceLog.log(
      'offline_store',
      'pending stats pending=$pending syncing=$syncing error=$error conflict=$conflict',
    );
    return {
      'pending': pending,
      'syncing': syncing,
      'error': error,
      'conflict': conflict,
    };
  }

  Map<String, dynamic> _offlineSaleRowToMap(Map<String, Object?> row) {
    return {
      'localId': row['local_id']?.toString(),
      'companyId': row['company_id']?.toString(),
      'userId': row['user_id']?.toString(),
      'serverId': row['server_id']?.toString(),
      'clientRequestId': row['client_request_id']?.toString(),
      'status': row['status']?.toString(),
      'payload': jsonDecode((row['payload'] ?? '{}').toString()),
      'totalSold': _asDouble(row['total_sold']),
      'saleOccurredAt': DateTime.fromMillisecondsSinceEpoch(
        (row['sale_occurred_at'] as num?)?.toInt() ?? 0,
      ).toUtc().toIso8601String(),
      'syncedAt': (row['synced_at'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (row['synced_at'] as num).toInt(),
            ).toUtc().toIso8601String(),
      'error': row['error']?.toString(),
      'createdAt': DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num?)?.toInt() ?? 0,
      ).toUtc().toIso8601String(),
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as num?)?.toInt() ?? 0,
      ).toUtc().toIso8601String(),
    };
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
