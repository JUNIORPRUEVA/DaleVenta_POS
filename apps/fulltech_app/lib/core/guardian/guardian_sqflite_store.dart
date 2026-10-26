import 'package:sqflite/sqflite.dart';

import 'guardian_event.dart';
import 'guardian_store.dart';

/// Cola local persistente **independiente** de la cola de ventas offline.
///
/// Usa su propio archivo SQLite (`guardian_outbox.db`) para no tocar el esquema
/// de negocio ni la base de ventas/caja.
class SqfliteGuardianStore implements GuardianStore {
  SqfliteGuardianStore({this.databasePath});

  final String? databasePath;
  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    await init();
    return _db!;
  }

  @override
  Future<void> init() async {
    if (_db != null) return;
    final path = databasePath ?? '${await getDatabasesPath()}/guardian_outbox.db';
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE guardian_events (
            event_id TEXT PRIMARY KEY,
            severity TEXT NOT NULL,
            occurred_at_ms INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_guardian_events_due ON guardian_events(next_attempt_at_ms, severity, occurred_at_ms)',
        );
        await db.execute('''
          CREATE TABLE guardian_discards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL,
            reason TEXT NOT NULL,
            at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE guardian_fingerprints (
            fingerprint TEXT PRIMARY KEY,
            at_ms INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<void> upsert(GuardianEvent event) async {
    final db = await _database;
    await db.insert(
      'guardian_events',
      <String, Object?>{
        'event_id': event.eventId,
        'severity': event.severity,
        'occurred_at_ms': event.occurredAt.millisecondsSinceEpoch,
        'attempts': event.attempts,
        'next_attempt_at_ms': event.nextAttemptAtMs,
        'payload': event.toDbJson(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<GuardianEvent>> dueEvents({required int limit, DateTime? now}) async {
    final db = await _database;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = await db.query(
      'guardian_events',
      where: 'next_attempt_at_ms <= ?',
      whereArgs: <Object?>[at],
      orderBy: 'severity ASC, occurred_at_ms ASC',
      limit: limit,
    );
    return rows.map(GuardianEvent.fromDbRow).toList();
  }

  @override
  Future<void> markFailure(
    String eventId, {
    required int attempts,
    required int nextAttemptAtMs,
  }) async {
    final db = await _database;
    await db.update(
      'guardian_events',
      <String, Object?>{'attempts': attempts, 'next_attempt_at_ms': nextAttemptAtMs},
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
    );
  }

  @override
  Future<void> removeAll(Iterable<String> eventIds) async {
    final ids = eventIds.toList();
    if (ids.isEmpty) return;
    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('guardian_events', where: 'event_id IN ($placeholders)', whereArgs: ids);
  }

  @override
  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM guardian_events');
    return (result.first['c'] as int?) ?? 0;
  }

  @override
  Future<int> totalBytes() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COALESCE(SUM(LENGTH(payload)), 0) AS b FROM guardian_events');
    return (result.first['b'] as int?) ?? 0;
  }

  @override
  Future<List<GuardianEvent>> selectForEviction({
    required int eventsToDrop,
    required int bytesToDrop,
  }) async {
    if (eventsToDrop <= 0 && bytesToDrop <= 0) return const [];
    final db = await _database;
    final rows = await db.query(
      'guardian_events',
      where: "severity NOT IN ('SEV1','SEV2')",
      orderBy: 'severity DESC, occurred_at_ms ASC',
    );
    final selected = <GuardianEvent>[];
    var bytes = 0;
    for (final row in rows) {
      if (selected.length >= eventsToDrop && bytes >= bytesToDrop) break;
      final event = GuardianEvent.fromDbRow(row);
      selected.add(event);
      bytes += (row['payload'] as String).length;
    }
    return selected;
  }

  @override
  Future<void> recordDiscard(GuardianDiscardRecord record) async {
    final db = await _database;
    await db.insert('guardian_discards', <String, Object?>{
      'event_id': record.eventId,
      'reason': record.reason,
      'at_ms': record.at.millisecondsSinceEpoch,
    });
  }

  @override
  Future<List<GuardianDiscardRecord>> discards() async {
    final db = await _database;
    final rows = await db.query('guardian_discards', orderBy: 'at_ms ASC', limit: 100);
    return rows
        .map(
          (row) => GuardianDiscardRecord(
            eventId: row['event_id'] as String,
            reason: row['reason'] as String,
            at: DateTime.fromMillisecondsSinceEpoch(row['at_ms'] as int),
          ),
        )
        .toList();
  }

  @override
  Future<bool> wasRecentlyRecorded(String fingerprint, {required Duration window}) async {
    final db = await _database;
    final rows = await db.query(
      'guardian_fingerprints',
      where: 'fingerprint = ? AND at_ms >= ?',
      whereArgs: <Object?>[fingerprint, DateTime.now().subtract(window).millisecondsSinceEpoch],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markRecorded(String fingerprint) async {
    final db = await _database;
    await db.insert(
      'guardian_fingerprints',
      <String, Object?>{'fingerprint': fingerprint, 'at_ms': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
