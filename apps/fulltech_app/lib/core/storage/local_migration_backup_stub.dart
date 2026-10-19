Future<void> backupLocalDatabaseBeforeMigration({
  required String fileName,
  required String label,
  int? targetVersion,
}) async {
  throw UnsupportedError('SQLite migration backups require native storage.');
}
