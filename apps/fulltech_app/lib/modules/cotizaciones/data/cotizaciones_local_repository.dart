import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../cotizacion_models.dart';

final cotizacionesLocalRepositoryProvider =
    Provider<CotizacionesLocalRepository>((ref) {
      return CotizacionesLocalRepository();
    });

class CotizacionesLocalRepository {
  static const _dbName = 'cotizaciones_local.db';
  static const _dbVersion = 4;
  static const _tableCotizaciones = 'cotizaciones';
  static const _tableItems = 'cotizacion_items';

  Database? _database;
  List<CotizacionModel> _memoryQuotes = const [];
  CotizacionModel? _memoryDraft;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableCotizaciones (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            customer_id TEXT,
            customer_name TEXT NOT NULL,
            customer_phone TEXT,
            note TEXT,
            include_itbis INTEGER NOT NULL DEFAULT 0,
            itbis_rate REAL NOT NULL DEFAULT 0.18,
            global_discount_amount REAL NOT NULL DEFAULT 0,
            total_cost REAL,
            total_profit REAL,
            is_draft INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE $_tableItems (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cotizacion_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            nombre TEXT NOT NULL,
            image_url TEXT,
            original_unit_price REAL,
            cost_unit REAL,
            external_cost_unit REAL,
            subtotal_cost_snapshot REAL,
            profit_snapshot REAL,
            unit_price REAL NOT NULL,
            qty REAL NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_cotizacion_items_quote ON $_tableItems(cotizacion_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(
            db,
            tableName: _tableItems,
            columnName: 'original_unit_price',
            definition: 'REAL',
          );
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(
            db,
            tableName: _tableCotizaciones,
            columnName: 'global_discount_amount',
            definition: 'REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(
            db,
            tableName: _tableCotizaciones,
            columnName: 'total_cost',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableCotizaciones,
            columnName: 'total_profit',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableItems,
            columnName: 'cost_unit',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableItems,
            columnName: 'external_cost_unit',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableItems,
            columnName: 'subtotal_cost_snapshot',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            db,
            tableName: _tableItems,
            columnName: 'profit_snapshot',
            definition: 'REAL',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final alreadyExists = columns.any(
      (row) => (row['name'] ?? '').toString().trim() == columnName,
    );
    if (alreadyExists) {
      return;
    }

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  Future<List<CotizacionModel>> listAll() async {
    if (kIsWeb) {
      final items =
          _memoryQuotes.where((item) => !_isDraft(item)).toList(growable: false)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    }

    final db = await _db;
    final rows = await db.query(
      _tableCotizaciones,
      where: 'is_draft = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );

    final itemsByQuote = await _loadItemsGrouped(
      rows.map((row) => (row['id'] ?? '').toString()).toList(),
    );

    return rows
        .map(
          (row) => _toModel(
            row,
            itemsByQuote[(row['id'] ?? '').toString()] ?? const [],
          ),
        )
        .toList();
  }

  Future<void> upsert(CotizacionModel cotizacion) async {
    if (kIsWeb) {
      final next = [
        ..._memoryQuotes.where((item) => item.id != cotizacion.id),
        cotizacion,
      ];
      next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _memoryQuotes = next;
      if (_memoryDraft?.id == cotizacion.id) {
        _memoryDraft = null;
      }
      return;
    }

    await _upsert(cotizacion, isDraft: false);
  }

  Future<void> saveDraft(CotizacionModel cotizacion) async {
    if (kIsWeb) {
      _memoryDraft = cotizacion;
      return;
    }

    final db = await _db;
    await db.delete(_tableCotizaciones, where: 'is_draft = ?', whereArgs: [1]);
    await db.delete(
      _tableItems,
      where: 'cotizacion_id NOT IN (SELECT id FROM $_tableCotizaciones)',
    );
    await _upsert(cotizacion, isDraft: true);
  }

  Future<CotizacionModel?> getDraft() async {
    if (kIsWeb) {
      return _memoryDraft;
    }

    final db = await _db;
    final rows = await db.query(
      _tableCotizaciones,
      where: 'is_draft = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final quoteId = (row['id'] ?? '').toString();
    final itemRows = await db.query(
      _tableItems,
      where: 'cotizacion_id = ?',
      whereArgs: [quoteId],
      orderBy: 'id ASC',
    );

    return _toModel(row, itemRows);
  }

  Future<void> clearDraft() async {
    if (kIsWeb) {
      _memoryDraft = null;
      return;
    }

    final db = await _db;
    final draftRows = await db.query(
      _tableCotizaciones,
      columns: ['id'],
      where: 'is_draft = ?',
      whereArgs: [1],
    );

    for (final row in draftRows) {
      final id = (row['id'] ?? '').toString();
      await db.delete(_tableItems, where: 'cotizacion_id = ?', whereArgs: [id]);
    }

    await db.delete(_tableCotizaciones, where: 'is_draft = ?', whereArgs: [1]);
  }

  Future<void> deleteById(String id) async {
    if (kIsWeb) {
      _memoryQuotes = _memoryQuotes
          .where((item) => item.id != id)
          .toList(growable: false);
      if (_memoryDraft?.id == id) {
        _memoryDraft = null;
      }
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        _tableItems,
        where: 'cotizacion_id = ?',
        whereArgs: [id],
      );
      await txn.delete(_tableCotizaciones, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> clearAll() async {
    _memoryQuotes = const [];
    _memoryDraft = null;

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_tableItems);
      await txn.delete(_tableCotizaciones);
    });
  }

  Future<void> _upsert(
    CotizacionModel cotizacion, {
    required bool isDraft,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert(_tableCotizaciones, {
        'id': cotizacion.id,
        'created_at': cotizacion.createdAt.toIso8601String(),
        'updated_at': now,
        'customer_id': cotizacion.customerId,
        'customer_name': cotizacion.customerName,
        'customer_phone': cotizacion.customerPhone,
        'note': cotizacion.note,
        'include_itbis': cotizacion.includeItbis ? 1 : 0,
        'itbis_rate': cotizacion.itbisRate,
        'global_discount_amount': cotizacion.globalDiscountAmount,
        'total_cost': cotizacion.totalCost,
        'total_profit': cotizacion.totalProfit,
        'is_draft': isDraft ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        _tableItems,
        where: 'cotizacion_id = ?',
        whereArgs: [cotizacion.id],
      );

      for (final item in cotizacion.items) {
        await txn.insert(_tableItems, {
          'cotizacion_id': cotizacion.id,
          'product_id': item.productId,
          'nombre': item.nombre,
          'image_url': item.imageUrl,
          'original_unit_price': item.originalUnitPrice,
          'cost_unit': item.costUnit,
          'external_cost_unit': item.externalCostUnit,
          'subtotal_cost_snapshot': item.subtotalCostSnapshot,
          'profit_snapshot': item.profitSnapshot,
          'unit_price': item.unitPrice,
          'qty': item.qty,
        });
      }
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> _loadItemsGrouped(
    List<String> quoteIds,
  ) async {
    if (quoteIds.isEmpty) return {};

    final db = await _db;
    final placeholders = List.filled(quoteIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM $_tableItems WHERE cotizacion_id IN ($placeholders) ORDER BY id ASC',
      quoteIds,
    );

    final result = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final id = (row['cotizacion_id'] ?? '').toString();
      result.putIfAbsent(id, () => <Map<String, Object?>>[]).add(row);
    }
    return result;
  }

  CotizacionModel _toModel(
    Map<String, Object?> row,
    List<Map<String, Object?>> itemRows,
  ) {
    return CotizacionModel(
      id: (row['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      customerId: row['customer_id']?.toString(),
      customerName: (row['customer_name'] ?? '').toString(),
      customerPhone: row['customer_phone']?.toString(),
      note: (row['note'] ?? '').toString(),
      includeItbis: (row['include_itbis'] as num?)?.toInt() == 1,
      itbisRate: (row['itbis_rate'] as num?)?.toDouble() ?? 0.18,
      globalDiscountAmount:
          (row['global_discount_amount'] as num?)?.toDouble() ?? 0,
      totalCost: (row['total_cost'] as num?)?.toDouble(),
      totalProfit: (row['total_profit'] as num?)?.toDouble(),
      items: itemRows
          .map(
            (itemRow) => CotizacionItem(
              productId: (itemRow['product_id'] ?? '').toString(),
              nombre: (itemRow['nombre'] ?? '').toString(),
              imageUrl: itemRow['image_url']?.toString(),
              originalUnitPrice: (itemRow['original_unit_price'] as num?)
                  ?.toDouble(),
              costUnit: (itemRow['cost_unit'] as num?)?.toDouble(),
              externalCostUnit: (itemRow['external_cost_unit'] as num?)
                  ?.toDouble(),
              subtotalCostSnapshot: (itemRow['subtotal_cost_snapshot'] as num?)
                  ?.toDouble(),
              profitSnapshot: (itemRow['profit_snapshot'] as num?)?.toDouble(),
              unitPrice: (itemRow['unit_price'] as num?)?.toDouble() ?? 0,
              qty: (itemRow['qty'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(),
    );
  }

  bool _isDraft(CotizacionModel cotizacion) {
    return _memoryDraft?.id == cotizacion.id;
  }
}
