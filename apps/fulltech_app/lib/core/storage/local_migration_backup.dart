import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_database_path.dart';

Future<void> backupLocalDatabaseBeforeMigration({
  required String fileName,
  required String label,
}) async {
  final dbPath = await resolveLocalDatabasePath(fileName);
  final source = File(dbPath);
  if (!await source.exists()) return;

  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}_'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final backupDir = Directory(
    p.join(p.dirname(dbPath), 'local_migration_backups', label, stamp),
  );
  await backupDir.create(recursive: true);

  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final candidate = File('$dbPath$suffix');
    if (!await candidate.exists()) continue;
    await candidate.copy(p.join(backupDir.path, p.basename(candidate.path)));
  }
}
