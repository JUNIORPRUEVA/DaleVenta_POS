import 'dart:io';

import 'package:daleventa_pos/core/storage/local_database_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'copies legacy database and sqlite sidecars when target is missing',
    () async {
      final root = await Directory.systemTemp.createTemp('local-db-migration-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final legacy = Directory(p.join(root.path, 'legacy'))..createSync();
      final target = Directory(p.join(root.path, 'target'))..createSync();
      final targetPath = p.join(target.path, 'fulltech_offline.db');

      await File(
        p.join(legacy.path, 'fulltech_offline.db'),
      ).writeAsString('db');
      await File(
        p.join(legacy.path, 'fulltech_offline.db-wal'),
      ).writeAsString('wal');
      await File(
        p.join(legacy.path, 'fulltech_offline.db-shm'),
      ).writeAsString('shm');
      await File(
        p.join(legacy.path, 'fulltech_offline.db-journal'),
      ).writeAsString('journal');

      await copyLegacyDatabaseIfNeeded(
        fileName: 'fulltech_offline.db',
        targetPath: targetPath,
        legacyDirectories: [legacy],
      );

      expect(await File(targetPath).readAsString(), 'db');
      expect(await File('$targetPath-wal').readAsString(), 'wal');
      expect(await File('$targetPath-shm').readAsString(), 'shm');
      expect(await File('$targetPath-journal').readAsString(), 'journal');
      expect(
        await File(p.join(legacy.path, 'fulltech_offline.db')).exists(),
        true,
      );
    },
  );

  test('does not overwrite an existing target database', () async {
    final root = await Directory.systemTemp.createTemp('local-db-migration-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final legacy = Directory(p.join(root.path, 'legacy'))..createSync();
    final target = Directory(p.join(root.path, 'target'))..createSync();
    final targetPath = p.join(target.path, 'fulltech_printing.db');

    await File(
      p.join(legacy.path, 'fulltech_printing.db'),
    ).writeAsString('legacy');
    await File(targetPath).writeAsString('current');

    await copyLegacyDatabaseIfNeeded(
      fileName: 'fulltech_printing.db',
      targetPath: targetPath,
      legacyDirectories: [legacy],
    );

    expect(await File(targetPath).readAsString(), 'current');
  });
}
