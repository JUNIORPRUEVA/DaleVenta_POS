import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:daleventa_pos/core/storage/local_migration_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Backup API includes a live committed WAL and publishes a verified standalone copy', () async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    final oldPath = await ffi.databaseFactory.getDatabasesPath();
    final root = await Directory.systemTemp.createTemp('fullpos-phase16-backup-');
    await ffi.databaseFactory.setDatabasesPath(root.path);
    final source = sqlite3.open(p.join(root.path, 'live.db'));
    try {
      source.execute('PRAGMA journal_mode=WAL');
      source.execute('PRAGMA synchronous=FULL');
      source.execute('PRAGMA wal_autocheckpoint=0');
      source.execute('PRAGMA user_version=1');
      source.execute('CREATE TABLE pending_actions (id TEXT PRIMARY KEY, payload TEXT)');
      source.execute("INSERT INTO pending_actions VALUES ('original', 'economic-payload')");
      expect(File(p.join(root.path, 'live.db-wal')).existsSync(), isTrue);
      await backupLocalDatabaseBeforeMigration(fileName: 'live.db', label: 'test', targetVersion: 2);
      await backupLocalDatabaseBeforeMigration(fileName: 'live.db', label: 'test', targetVersion: 1);
      final manifests = Directory(p.join(root.path, 'local_migration_backups/test'))
        .listSync(recursive: true).whereType<File>().where((f) => p.basename(f.path) == 'manifest.json').toList();
      expect(manifests.length, 1);
      final manifest = jsonDecode(await manifests.single.readAsString()) as Map;
      final copyFile = File(p.join(manifests.single.parent.path, 'live.db'));
      expect(manifest['method'], 'SQLite Backup API');
      expect(manifest['sha256'], sha256.convert(await copyFile.readAsBytes()).toString());
      expect(manifest['pendingActions'], 1);
      final copy = sqlite3.open(copyFile.path, mode: OpenMode.readOnly);
      try {
        expect(copy.select('PRAGMA integrity_check').single.values.first, 'ok');
        expect(copy.select('SELECT id FROM pending_actions').single.values.first, 'original');
      } finally { copy.close(); }
      expect(source.select('SELECT count(*) FROM pending_actions').single.values.first, 1);
    } finally {
      source.close();
      await ffi.databaseFactory.setDatabasesPath(oldPath);
      await root.delete(recursive: true);
    }
  });
}
