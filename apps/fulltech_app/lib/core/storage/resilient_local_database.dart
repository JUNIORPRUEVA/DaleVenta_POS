import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../debug/app_error_reporter.dart';
import '../debug/trace_log.dart';
import 'local_database_path.dart';

class LocalDatabaseCorruptionException implements Exception {
  const LocalDatabaseCorruptionException(this.fileName, this.details);

  final String fileName;
  final String details;

  @override
  String toString() {
    return 'LocalDatabaseCorruptionException(fileName: $fileName, details: $details)';
  }
}

Future<Database> openResilientLocalDatabase({
  required String fileName,
  required int version,
  required OnDatabaseCreateFn onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
  OnDatabaseVersionChangeFn? onDowngrade,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseOpenFn? onOpen,
  bool allowInMemoryFallback = true,
}) {
  return _ResilientLocalDatabase.instance.open(
    fileName: fileName,
    version: version,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
    onDowngrade: onDowngrade,
    onConfigure: onConfigure,
    onOpen: onOpen,
    allowInMemoryFallback: allowInMemoryFallback,
  );
}

class _ResilientLocalDatabase {
  _ResilientLocalDatabase._();

  static final _ResilientLocalDatabase instance = _ResilientLocalDatabase._();

  final Map<String, Future<Database>> _openingByPath =
      <String, Future<Database>>{};

  Future<Database> open({
    required String fileName,
    required int version,
    required OnDatabaseCreateFn onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    OnDatabaseVersionChangeFn? onDowngrade,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseOpenFn? onOpen,
    required bool allowInMemoryFallback,
  }) async {
    final dbPath = await resolveLocalDatabasePath(fileName);
    final inFlight = _openingByPath[dbPath];
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<Database> future;
    future =
        _openInternal(
          fileName: fileName,
          dbPath: dbPath,
          version: version,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onConfigure: onConfigure,
          onOpen: onOpen,
          allowInMemoryFallback: allowInMemoryFallback,
        ).whenComplete(() {
          final current = _openingByPath[dbPath];
          if (identical(current, future)) {
            _openingByPath.remove(dbPath);
          }
        });

    _openingByPath[dbPath] = future;
    return future;
  }

  Future<Database> _openInternal({
    required String fileName,
    required String dbPath,
    required int version,
    required OnDatabaseCreateFn onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    OnDatabaseVersionChangeFn? onDowngrade,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseOpenFn? onOpen,
    required bool allowInMemoryFallback,
  }) async {
    try {
      return await _openAndValidate(
        fileName: fileName,
        path: dbPath,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onConfigure: onConfigure,
        onOpen: onOpen,
      );
    } catch (error, stackTrace) {
      TraceLog.log(
        'local_db',
        'open failed file=$fileName path=$dbPath',
        error: error,
        stackTrace: stackTrace,
      );

      if (!_looksRecoverable(error)) {
        rethrow;
      }

      final backupSummary = await _backupAndReset(dbPath);
      try {
        final recovered = await _openAndValidate(
          fileName: fileName,
          path: dbPath,
          version: version,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onConfigure: onConfigure,
          onOpen: onOpen,
        );
        _reportAutoRepair(
          fileName: fileName,
          dbPath: dbPath,
          backupSummary: backupSummary,
          originalError: error,
          originalStackTrace: stackTrace,
        );
        return recovered;
      } catch (recoveryError, recoveryStackTrace) {
        TraceLog.log(
          'local_db',
          'auto-repair failed file=$fileName path=$dbPath',
          error: recoveryError,
          stackTrace: recoveryStackTrace,
        );

        if (!allowInMemoryFallback) {
          rethrow;
        }

        final protectedDb = await _openAndValidate(
          fileName: fileName,
          path: inMemoryDatabasePath,
          version: version,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onConfigure: onConfigure,
          onOpen: onOpen,
          skipIntegrityCheck: true,
        );
        _reportProtectedMode(
          fileName: fileName,
          dbPath: dbPath,
          backupSummary: backupSummary,
          originalError: error,
          originalStackTrace: stackTrace,
          recoveryError: recoveryError,
          recoveryStackTrace: recoveryStackTrace,
        );
        return protectedDb;
      }
    }
  }

  Future<Database> _openAndValidate({
    required String fileName,
    required String path,
    required int version,
    required OnDatabaseCreateFn onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    OnDatabaseVersionChangeFn? onDowngrade,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseOpenFn? onOpen,
    bool skipIntegrityCheck = false,
  }) async {
    Database? db;
    try {
      db = await openDatabase(
        path,
        version: version,
        onConfigure: (database) async {
          await _applySafePragmas(database);
          if (onConfigure != null) {
            await onConfigure(database);
          }
        },
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: onDowngrade,
        onOpen: (database) async {
          if (!skipIntegrityCheck && path != inMemoryDatabasePath) {
            await _ensureIntegrity(database, fileName: fileName);
          }
          if (onOpen != null) {
            await onOpen(database);
          }
        },
      );
      return db;
    } catch (_) {
      if (db != null) {
        unawaited(_closeSilently(db));
      }
      rethrow;
    }
  }

  Future<void> _applySafePragmas(Database db) async {
    await db.rawQuery('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA synchronous = FULL');
    await db.rawQuery('PRAGMA busy_timeout = 5000');
  }

  Future<void> _ensureIntegrity(Database db, {required String fileName}) async {
    final rows = await db.rawQuery('PRAGMA quick_check(1)');
    final value = rows.isEmpty
        ? null
        : rows.first.values.firstOrNull?.toString().trim();
    if ((value ?? '').toLowerCase() == 'ok') {
      return;
    }

    throw LocalDatabaseCorruptionException(
      fileName,
      value == null || value.isEmpty
          ? 'PRAGMA quick_check returned an empty result.'
          : value,
    );
  }

  bool _looksRecoverable(Object error) {
    if (error is LocalDatabaseCorruptionException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    const hints = <String>[
      'database disk image is malformed',
      'file is not a database',
      'not a database',
      'sqlite_corrupt',
      'sqlite_notadb',
      'malformed',
      'corrupt',
      'disk i/o error',
      'unable to open database file',
      'database is locked',
      'database or disk is full',
      'readonly database',
      'no such column',
      'no such table',
      'has no column named',
      'duplicate column name',
      'table already exists',
    ];
    for (final hint in hints) {
      if (message.contains(hint)) {
        return true;
      }
    }
    return false;
  }

  Future<String> _backupAndReset(String dbPath) async {
    final databaseFile = File(dbPath);
    final databaseDirectory = databaseFile.parent;
    final recoveryDirectory = Directory(
      p.join(databaseDirectory.path, 'db_recovery'),
    );
    if (!await recoveryDirectory.exists()) {
      await recoveryDirectory.create(recursive: true);
    }

    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

    final archivedFiles = <String>[];
    for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
      final source = File('$dbPath$suffix');
      if (!await source.exists()) {
        continue;
      }

      final targetPath = p.join(
        recoveryDirectory.path,
        '${p.basename(dbPath)}_$stamp${suffix.replaceAll('-', '_')}.bak',
      );
      try {
        await source.copy(targetPath);
        archivedFiles.add(targetPath);
      } catch (error, stackTrace) {
        TraceLog.log(
          'local_db',
          'backup copy failed path=${source.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        await source.delete();
      } catch (error, stackTrace) {
        TraceLog.log(
          'local_db',
          'backup delete failed path=${source.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return archivedFiles.isEmpty
        ? recoveryDirectory.path
        : archivedFiles.join(', ');
  }

  void _reportAutoRepair({
    required String fileName,
    required String dbPath,
    required String backupSummary,
    required Object originalError,
    required StackTrace originalStackTrace,
  }) {
    AppErrorReporter.instance.record(
      originalError,
      originalStackTrace,
      context: 'LocalDatabase.AutoRepair',
      title: 'Recuperamos el almacenamiento local',
      userMessage:
          'Detectamos un daño en la base local del dispositivo y la reparamos automaticamente. La app seguira funcionando y volvera a descargar la informacion necesaria desde la nube.',
      technicalDetails: 'db=$fileName path=$dbPath backups=$backupSummary',
      severity: AppErrorSeverity.warning,
      dedupeKey: 'local-db-auto-repair',
    );
  }

  void _reportProtectedMode({
    required String fileName,
    required String dbPath,
    required String backupSummary,
    required Object originalError,
    required StackTrace originalStackTrace,
    required Object recoveryError,
    required StackTrace recoveryStackTrace,
  }) {
    AppErrorReporter.instance.record(
      originalError,
      originalStackTrace,
      context: 'LocalDatabase.ProtectedMode',
      title: 'Seguimos operando en modo protegido',
      userMessage:
          'No pudimos restaurar la base local persistente del dispositivo, pero la app seguira abierta en modo protegido para que no se detenga tu operacion. Algunos datos locales solo se conservaran durante esta sesion hasta que el almacenamiento vuelva a estar disponible.',
      technicalDetails:
          'db=$fileName path=$dbPath backups=$backupSummary recoveryError=$recoveryError recoveryStack=$recoveryStackTrace',
      severity: AppErrorSeverity.warning,
      dedupeKey: 'local-db-protected-mode',
    );
  }

  Future<void> _closeSilently(Database db) async {
    try {
      await db.close();
    } catch (_) {
      // Ignore close failures after a broken open attempt.
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
