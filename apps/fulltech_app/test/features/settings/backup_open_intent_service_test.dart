import 'dart:io';

import 'package:daleventa_pos/features/settings/data/backup_open_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cleanup removes only app-owned backup-open cache copies', () async {
    final root = await Directory.systemTemp.createTemp('backup_open_cleanup_');
    addTearDown(() => root.delete(recursive: true));

    final tempDir = Directory('${root.path}/cache/backup-open');
    await tempDir.create(recursive: true);
    final tempCopy = File('${tempDir.path}/import.dvbackup');
    await tempCopy.writeAsBytes([1, 2, 3]);

    final userFile = File('${root.path}/Downloads/Backup.dvbackup');
    await userFile.parent.create(recursive: true);
    await userFile.writeAsBytes([4, 5, 6]);

    expect(
      BackupOpenIntentService.isAppOwnedTemporaryBackupPath(tempCopy.path),
      isTrue,
    );
    expect(
      BackupOpenIntentService.isAppOwnedTemporaryBackupPath(userFile.path),
      isFalse,
    );

    expect(
      await BackupOpenIntentService.cleanupTemporaryBackupCopy(userFile.path),
      isFalse,
    );
    expect(await userFile.exists(), isTrue);

    expect(
      await BackupOpenIntentService.cleanupTemporaryBackupCopy(tempCopy.path),
      isTrue,
    );
    expect(await tempCopy.exists(), isFalse);
  });
}
