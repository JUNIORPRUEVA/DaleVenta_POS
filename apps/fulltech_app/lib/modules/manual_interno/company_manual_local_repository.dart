import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/storage/resilient_local_database.dart';
import '../../core/auth/app_role.dart';
import 'company_manual_models.dart';

final companyManualLocalRepositoryProvider =
    Provider<CompanyManualLocalRepository>((ref) {
      return CompanyManualLocalRepository();
    });

class CompanyManualLocalRepository {
  static const _dbName = 'company_manual_local.db';
  static const _dbVersion = 2;
  static const _entriesTable = 'company_manual_entries';
  static const _metaTable = 'company_manual_meta';
  static const _lastSyncedAtKey = 'last_synced_at';

  Database? _database;
  final Map<String, List<CompanyManualEntry>> _memoryEntriesByUser = {};
  final Map<String, DateTime?> _memoryLastSyncedAtByUser = {};

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
        if (oldVersion < 2) {
          await _addColumnIfMissing(
            db,
            tableName: _entriesTable,
            columnName: 'target_roles',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            db,
            tableName: _entriesTable,
            columnName: 'module_key',
            definition: 'TEXT',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_entriesTable (
        viewer_user_id TEXT NOT NULL,
        id TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT,
        content TEXT NOT NULL,
        kind TEXT NOT NULL,
        audience TEXT NOT NULL,
        target_roles TEXT NOT NULL,
        module_key TEXT,
        published INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_by_user_id TEXT NOT NULL,
        updated_by_user_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        PRIMARY KEY (viewer_user_id, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        viewer_user_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (viewer_user_id, key)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_manual_entries_user ON $_entriesTable(viewer_user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_company_manual_entries_updated ON $_entriesTable(viewer_user_id, updated_at)',
    );
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

  Future<List<CompanyManualEntry>> listEntries({
    required String viewerUserId,
  }) async {
    if (kIsWeb) {
      return List<CompanyManualEntry>.from(
        _memoryEntriesByUser[viewerUserId] ?? const <CompanyManualEntry>[],
      );
    }

    final db = await _db;
    final rows = await db.query(
      _entriesTable,
      where: 'viewer_user_id = ?',
      whereArgs: [viewerUserId],
      orderBy: 'sort_order ASC, title COLLATE NOCASE ASC',
    );
    return rows.map(_mapRowToEntry).toList(growable: false);
  }

  Future<CompanyManualEntry?> getEntryById({
    required String viewerUserId,
    required String id,
  }) async {
    if (kIsWeb) {
      final entries =
          _memoryEntriesByUser[viewerUserId] ?? const <CompanyManualEntry>[];
      for (final entry in entries) {
        if (entry.id == id) return entry;
      }
      return null;
    }

    final db = await _db;
    final rows = await db.query(
      _entriesTable,
      where: 'viewer_user_id = ? AND id = ?',
      whereArgs: [viewerUserId, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToEntry(rows.first);
  }

  Future<void> replaceEntries({
    required String viewerUserId,
    required List<CompanyManualEntry> entries,
  }) async {
    if (kIsWeb) {
      _memoryEntriesByUser[viewerUserId] = entries.toList(growable: false);
      _memoryLastSyncedAtByUser[viewerUserId] = DateTime.now().toUtc();
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        _entriesTable,
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );
      for (final entry in entries) {
        await txn.insert(
          _entriesTable,
          _entryToRow(viewerUserId: viewerUserId, entry: entry),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.insert(_metaTable, {
        'viewer_user_id': viewerUserId,
        'key': _lastSyncedAtKey,
        'value': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> upsertEntry({
    required String viewerUserId,
    required CompanyManualEntry entry,
  }) async {
    if (kIsWeb) {
      final current = [
        ...(_memoryEntriesByUser[viewerUserId] ?? const <CompanyManualEntry>[]),
      ];
      final index = current.indexWhere((item) => item.id == entry.id);
      if (index >= 0) {
        current[index] = entry;
      } else {
        current.add(entry);
      }
      _memoryEntriesByUser[viewerUserId] = current;
      return;
    }

    final db = await _db;
    await db.insert(
      _entriesTable,
      _entryToRow(viewerUserId: viewerUserId, entry: entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteEntry({
    required String viewerUserId,
    required String id,
  }) async {
    if (kIsWeb) {
      _memoryEntriesByUser[viewerUserId] =
          (_memoryEntriesByUser[viewerUserId] ?? const <CompanyManualEntry>[])
              .where((item) => item.id != id)
              .toList(growable: false);
      return;
    }

    final db = await _db;
    await db.delete(
      _entriesTable,
      where: 'viewer_user_id = ? AND id = ?',
      whereArgs: [viewerUserId, id],
    );
  }

  Future<DateTime?> readLastSyncedAt({required String viewerUserId}) async {
    if (kIsWeb) {
      return _memoryLastSyncedAtByUser[viewerUserId];
    }

    final db = await _db;
    final rows = await db.query(
      _metaTable,
      where: 'viewer_user_id = ? AND key = ?',
      whereArgs: [viewerUserId, _lastSyncedAtKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse((rows.first['value'] ?? '').toString());
  }

  Future<CompanyManualSummary> buildSummary({
    required String viewerUserId,
    required DateTime? seenAt,
  }) async {
    if (kIsWeb) {
      final entries =
          (_memoryEntriesByUser[viewerUserId] ?? const <CompanyManualEntry>[])
              .where((entry) => entry.published)
              .toList(growable: false);
      final totalCount = entries.length;
      DateTime? latestUpdatedAt;
      for (final entry in entries) {
        final candidate = entry.updatedAt ?? entry.createdAt;
        if (candidate == null) continue;
        if (latestUpdatedAt == null || candidate.isAfter(latestUpdatedAt)) {
          latestUpdatedAt = candidate;
        }
      }
      final unreadCount = seenAt == null
          ? totalCount
          : entries.where((entry) {
              final candidate = entry.updatedAt ?? entry.createdAt;
              return candidate != null && candidate.isAfter(seenAt);
            }).length;
      return CompanyManualSummary(
        totalCount: totalCount,
        unreadCount: unreadCount,
        latestUpdatedAt: latestUpdatedAt,
      );
    }

    final db = await _db;
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS total_count FROM $_entriesTable WHERE viewer_user_id = ? AND published = 1',
      [viewerUserId],
    );
    final totalCount = (totalRows.first['total_count'] as num?)?.toInt() ?? 0;

    final latestRows = await db.rawQuery(
      'SELECT MAX(COALESCE(updated_at, created_at)) AS latest_updated_at FROM $_entriesTable WHERE viewer_user_id = ? AND published = 1',
      [viewerUserId],
    );
    final latestUpdatedAt = DateTime.tryParse(
      (latestRows.first['latest_updated_at'] ?? '').toString(),
    );

    final unreadCount = seenAt == null
        ? totalCount
        : ((await db.rawQuery(
                        'SELECT COUNT(*) AS unread_count FROM $_entriesTable WHERE viewer_user_id = ? AND published = 1 AND COALESCE(updated_at, created_at) > ?',
                        [viewerUserId, seenAt.toUtc().toIso8601String()],
                      )).first['unread_count']
                      as num?)
                  ?.toInt() ??
              0;

    return CompanyManualSummary(
      totalCount: totalCount,
      unreadCount: unreadCount,
      latestUpdatedAt: latestUpdatedAt,
    );
  }

  Map<String, Object?> _entryToRow({
    required String viewerUserId,
    required CompanyManualEntry entry,
  }) {
    return {
      'viewer_user_id': viewerUserId,
      'id': entry.id,
      'owner_id': entry.ownerId,
      'title': entry.title,
      'summary': entry.summary,
      'content': entry.content,
      'kind': entry.kind.apiValue,
      'audience': entry.audience.apiValue,
      'target_roles': entry.targetRoles
          .map((role) => role.name)
          .toList(growable: false)
          .join(','),
      'module_key': entry.moduleKey,
      'published': entry.published ? 1 : 0,
      'sort_order': entry.sortOrder,
      'created_by_user_id': entry.createdByUserId,
      'updated_by_user_id': entry.updatedByUserId,
      'created_at': entry.createdAt?.toUtc().toIso8601String(),
      'updated_at': entry.updatedAt?.toUtc().toIso8601String(),
    };
  }

  CompanyManualEntry _mapRowToEntry(Map<String, Object?> row) {
    final targetRolesRaw = (row['target_roles'] ?? '').toString();
    return CompanyManualEntry(
      id: (row['id'] ?? '').toString(),
      ownerId: (row['owner_id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      summary: (row['summary'] ?? '').toString().trim().isEmpty
          ? null
          : (row['summary'] ?? '').toString(),
      content: (row['content'] ?? '').toString(),
      kind: CompanyManualEntryKindX.fromApi((row['kind'] ?? '').toString()),
      audience: CompanyManualAudienceX.fromApi(
        (row['audience'] ?? '').toString(),
      ),
      targetRoles: targetRolesRaw
          .split(',')
          .map(parseAppRole)
          .where((role) => role != AppRole.unknown)
          .toList(growable: false),
      moduleKey: (row['module_key'] ?? '').toString().trim().isEmpty
          ? null
          : (row['module_key'] ?? '').toString(),
      published: (row['published'] as num?)?.toInt() != 0,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      createdByUserId: (row['created_by_user_id'] ?? '').toString(),
      updatedByUserId:
          (row['updated_by_user_id'] ?? '').toString().trim().isEmpty
          ? null
          : (row['updated_by_user_id'] ?? '').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
    );
  }
}
