import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'local_database_path.dart';

Future<void> backupLocalDatabaseBeforeMigration({
  required String fileName,
  required String label,
  int? targetVersion,
}) async {
  final dbPath = await resolveLocalDatabasePath(fileName);
  final source = File(dbPath);
  if (!await source.exists()) return;

  if (targetVersion != null) {
    final inspection = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      if ((inspection.select('PRAGMA user_version').single.values.first as int) >= targetVersion) return;
    } finally { inspection.close(); }
  }

  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}_'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final backupBase = Directory(p.join(p.dirname(dbPath), 'local_migration_backups', label));
  await backupBase.create(recursive: true);
  final backupDir = await backupBase.createTemp('${stamp}_');

  final partial = File(p.join(backupDir.path, '${p.basename(dbPath)}.partial'));
  if (await partial.exists()) throw StateError('Ya existe una copia de migración en esa ruta.');
  final original = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  Database? destination;
  var version = 0;
  var pending = 0;
  try {
    destination = sqlite3.open(partial.path);
    destination.execute('PRAGMA synchronous = FULL');
    final watch = Stopwatch()..start();
    await for (final _ in original.backup(destination, nPage: 128).timeout(const Duration(seconds: 5))) {
      if (watch.elapsed > const Duration(seconds: 10)) {
        throw StateError('La copia consistente necesita revisión; se conservó la base original.');
      }
    }
    if (destination.select('PRAGMA integrity_check').single.values.first != 'ok') {
      throw StateError('La copia de migración no superó la verificación de integridad.');
    }
    version = destination.select('PRAGMA user_version').single.values.first as int;
    if (destination.select("SELECT name FROM sqlite_master WHERE type='table' AND name='pending_actions'").isNotEmpty) {
      pending = destination.select('SELECT count(*) FROM pending_actions').single.values.first as int;
    }
  } finally {
    destination?.close();
    original.close();
  }
  final digest = sha256.convert(await partial.readAsBytes()).toString();
  final completed = await partial.rename(p.join(backupDir.path, p.basename(dbPath)));
  await File(p.join(backupDir.path, 'manifest.json')).writeAsString(jsonEncode({
    'format': 'fullpos.migration-backup.v1', 'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'fileName': p.basename(completed.path), 'schemaVersion': version,
    'pendingActions': pending, 'sha256': digest, 'integrityCheck': 'ok',
    'method': 'SQLite Backup API',
  }), flush: true);
}
