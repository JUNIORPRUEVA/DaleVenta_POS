import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../media_gallery_models.dart';

class MediaGalleryLocalSnapshot {
  const MediaGalleryLocalSnapshot({
    required this.items,
    this.lastSyncedAt,
    this.nextCursor,
  });

  final List<MediaGalleryItem> items;
  final DateTime? lastSyncedAt;
  final String? nextCursor;
}

final mediaGalleryLocalRepositoryProvider =
    Provider<MediaGalleryLocalRepository>((ref) {
      return MediaGalleryLocalRepository();
    });

class MediaGalleryLocalRepository {
  static const _dbName = 'fulltech_media_gallery_local.db';
  static const _dbVersion = 2;
  static const _itemsTable = 'media_gallery_items';
  static const _metaTable = 'media_gallery_meta';
  static const _metaLastSyncedAt = 'last_synced_at';
  static const _metaNextCursor = 'next_cursor';

  Database? _database;
  final Map<String, MediaGalleryLocalSnapshot> _memoryByViewer = {};

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
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
      CREATE TABLE IF NOT EXISTS $_itemsTable (
        viewer_user_id TEXT NOT NULL,
        id TEXT NOT NULL,
        position INTEGER NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
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
  }

  Future<MediaGalleryLocalSnapshot> readSnapshot({
    required String viewerUserId,
  }) async {
    final memory = _memoryByViewer[viewerUserId];
    if (memory != null) {
      return memory;
    }

    if (viewerUserId.trim().isEmpty || kIsWeb) {
      return _memoryByViewer[viewerUserId] ??
          const MediaGalleryLocalSnapshot(items: []);
    }

    final db = await _db;
    final itemRows = await db.query(
      _itemsTable,
      where: 'viewer_user_id = ?',
      whereArgs: [viewerUserId],
      orderBy: 'position ASC',
    );
    final metaRows = await db.query(
      _metaTable,
      where: 'viewer_user_id = ?',
      whereArgs: [viewerUserId],
    );
    final meta = {
      for (final row in metaRows)
        (row['key'] ?? '').toString(): row['value']?.toString(),
    };

    final snapshot = MediaGalleryLocalSnapshot(
      items: itemRows
          .map((row) => (row['payload'] ?? '').toString())
          .where((payload) => payload.trim().isNotEmpty)
          .map(jsonDecode)
          .whereType<Map>()
          .map(
            (payload) =>
                MediaGalleryItem.fromJson(payload.cast<String, dynamic>()),
          )
          .toList(growable: false),
      lastSyncedAt: DateTime.tryParse(meta[_metaLastSyncedAt] ?? ''),
      nextCursor: (meta[_metaNextCursor] ?? '').trim().isEmpty
          ? null
          : meta[_metaNextCursor],
    );
    _memoryByViewer[viewerUserId] = snapshot;
    return snapshot;
  }

  Future<void> saveSnapshot({
    required String viewerUserId,
    required List<MediaGalleryItem> items,
    required DateTime syncedAt,
    required String? nextCursor,
  }) async {
    final normalizedItems = items.toList(growable: false);
    final snapshot = MediaGalleryLocalSnapshot(
      items: normalizedItems,
      lastSyncedAt: syncedAt,
      nextCursor: nextCursor,
    );
    _memoryByViewer[viewerUserId] = snapshot;

    if (viewerUserId.trim().isEmpty || kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        _itemsTable,
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );
      for (var index = 0; index < normalizedItems.length; index++) {
        final item = normalizedItems[index];
        await txn.insert(_itemsTable, {
          'viewer_user_id': viewerUserId,
          'id': item.id,
          'position': index,
          'payload': jsonEncode(item.toJson()),
          'created_at': item.createdAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await _writeMeta(
        txn,
        viewerUserId: viewerUserId,
        key: _metaLastSyncedAt,
        value: syncedAt.toIso8601String(),
      );
      await _writeMeta(
        txn,
        viewerUserId: viewerUserId,
        key: _metaNextCursor,
        value: nextCursor,
      );
    });
  }

  Future<void> clearSnapshot({required String viewerUserId}) async {
    _memoryByViewer[viewerUserId] = const MediaGalleryLocalSnapshot(items: []);
    if (viewerUserId.trim().isEmpty || kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        _itemsTable,
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );
      await txn.delete(
        _metaTable,
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );
    });
  }

  Future<void> _writeMeta(
    Transaction txn, {
    required String viewerUserId,
    required String key,
    required String? value,
  }) async {
    await txn.insert(_metaTable, {
      'viewer_user_id': viewerUserId,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
