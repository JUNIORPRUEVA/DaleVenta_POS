import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../cliente_profile_model.dart';
import '../cliente_timeline_model.dart';

final clienteDetailLocalRepositoryProvider =
    Provider<ClienteDetailLocalRepository>((ref) {
      return ClienteDetailLocalRepository();
    });

class ClienteDetailLocalSnapshot {
  const ClienteDetailLocalSnapshot({
    this.profile,
    this.timeline = const [],
    this.updatedAt,
  });

  final ClienteProfileResponse? profile;
  final List<ClienteTimelineEvent> timeline;
  final DateTime? updatedAt;

  bool get hasData => profile != null || timeline.isNotEmpty;
}

class ClienteDetailLocalRepository {
  static const _dbName = 'clientes_detail_local.db';
  static const _dbVersion = 1;
  static const _table = 'cliente_details';

  Database? _database;
  final Map<String, ClienteDetailLocalSnapshot> _memory =
      <String, ClienteDetailLocalSnapshot>{};

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async => _createSchema(db),
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        client_id TEXT PRIMARY KEY,
        profile_payload TEXT,
        timeline_payload TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<ClienteDetailLocalSnapshot> read(String clientId) async {
    final trimmedId = clientId.trim();
    if (trimmedId.isEmpty) return const ClienteDetailLocalSnapshot();

    final memoryValue = _memory[trimmedId];
    if (memoryValue != null) {
      return memoryValue;
    }

    if (kIsWeb) {
      return const ClienteDetailLocalSnapshot();
    }

    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'client_id = ?',
      whereArgs: [trimmedId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const ClienteDetailLocalSnapshot();
    }

    final row = rows.first;
    final snapshot = ClienteDetailLocalSnapshot(
      profile: _decodeProfile(row['profile_payload']),
      timeline: _decodeTimeline(row['timeline_payload']),
      updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
    );
    _memory[trimmedId] = snapshot;
    return snapshot;
  }

  Future<void> write({
    required String clientId,
    ClienteProfileResponse? profile,
    List<ClienteTimelineEvent>? timeline,
  }) async {
    final trimmedId = clientId.trim();
    if (trimmedId.isEmpty) return;

    final existing = await read(trimmedId);
    final snapshot = ClienteDetailLocalSnapshot(
      profile: profile ?? existing.profile,
      timeline: timeline ?? existing.timeline,
      updatedAt: DateTime.now(),
    );
    _memory[trimmedId] = snapshot;

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    await db.insert(_table, {
      'client_id': trimmedId,
      'profile_payload': snapshot.profile == null
          ? null
          : jsonEncode(snapshot.profile!.toJson()),
      'timeline_payload': jsonEncode(
        snapshot.timeline.map((item) => item.toJson()).toList(growable: false),
      ),
      'updated_at': (snapshot.updatedAt ?? DateTime.now()).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  ClienteProfileResponse? _decodeProfile(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return ClienteProfileResponse.fromJson(decoded.cast<String, dynamic>());
  }

  List<ClienteTimelineEvent> _decodeTimeline(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return const [];
    final decoded = jsonDecode(text);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map(
          (item) => ClienteTimelineEvent.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }
}
