import 'dart:io';

import 'package:path/path.dart' as p;

const _sqliteSidecarSuffixes = <String>['-wal', '-shm', '-journal'];

Future<void> copyLegacyDatabaseIfNeeded({
  required String fileName,
  required String targetPath,
  required Iterable<Directory> legacyDirectories,
}) async {
  final target = File(targetPath);
  if (await target.exists()) return;

  final targetDirectory = target.parent;
  await targetDirectory.create(recursive: true);

  for (final legacyDirectory in _uniqueExistingDirectories(legacyDirectories)) {
    final legacyPath = p.join(legacyDirectory.path, fileName);
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) continue;

    await _copyVerified(legacyFile, target);

    for (final suffix in _sqliteSidecarSuffixes) {
      final sidecar = File('$legacyPath$suffix');
      if (!await sidecar.exists()) continue;
      await _copyVerified(sidecar, File('$targetPath$suffix'));
    }
    return;
  }
}

Iterable<Directory> _uniqueExistingDirectories(Iterable<Directory> dirs) sync* {
  final seen = <String>{};
  for (final dir in dirs) {
    final normalized = p.normalize(dir.path);
    final key = normalized.toLowerCase();
    if (!seen.add(key)) continue;
    if (Directory(normalized).existsSync()) {
      yield Directory(normalized);
    }
  }
}

Future<void> _copyVerified(File source, File target) async {
  if (await target.exists()) return;

  await target.parent.create(recursive: true);
  final copied = await source.copy(target.path);
  final sourceLength = await source.length();
  final copiedLength = await copied.length();
  if (sourceLength != copiedLength) {
    try {
      await copied.delete();
    } catch (_) {
      // Keep the original legacy file untouched even if cleanup fails.
    }
    throw FileSystemException(
      'Legacy database copy verification failed',
      target.path,
    );
  }
}
