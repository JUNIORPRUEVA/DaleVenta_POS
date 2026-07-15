import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../debug/app_error_reporter.dart';
import '../debug/trace_log.dart';
import '../storage/resilient_local_database.dart';
import 'pending_sync_action.dart';

class OfflineStore {
  OfflineStore._();

  static final OfflineStore instance = OfflineStore._();

  static const String _webCachePrefix = 'ft_db_cache:';
  static const String _webPendingKey = 'ft_db_pending_actions';

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
    TraceLog.log('offline_store', 'opening sqlite db path=fulltech_offline.db');
    return openResilientLocalDatabase(
      fileName: 'fulltech_offline.db',
      version: 1,
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
            payload TEXT NOT NULL,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            error TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
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
      'payload': jsonEncode(action.payload),
      'status': action.status,
      'attempts': action.attempts,
      'error': action.error,
      'created_at': action.createdAt.millisecondsSinceEpoch,
      'updated_at': action.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingSyncAction>> listPendingActions({int limit = 50}) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webPendingKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => PendingSyncAction.fromMap(row.cast<String, dynamic>()))
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
          .toList(growable: false)
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }

    final rows = await db.query(
      'pending_actions',
      orderBy: 'updated_at ASC',
      limit: limit,
    );
    return rows
        .map(
          (row) => PendingSyncAction.fromMap({
            'id': row['id'],
            'type': row['type'],
            'scope': row['scope'],
            'payload': jsonDecode((row['payload'] ?? '{}').toString()),
            'status': row['status'],
            'attempts': row['attempts'],
            'error': row['error'],
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

  Future<Map<String, int>> pendingActionStats() async {
    final actions = await listPendingActions(limit: 500);
    var pending = 0;
    var syncing = 0;
    var error = 0;

    for (final action in actions) {
      switch (action.status) {
        case 'syncing':
          syncing++;
          break;
        case 'error':
          error++;
          break;
        default:
          pending++;
          break;
      }
    }

    TraceLog.log(
      'offline_store',
      'pending stats pending=$pending syncing=$syncing error=$error',
    );
    return {'pending': pending, 'syncing': syncing, 'error': error};
  }
}
