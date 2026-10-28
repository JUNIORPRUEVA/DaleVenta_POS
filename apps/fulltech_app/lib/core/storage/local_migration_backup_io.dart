import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'local_database_path.dart';
import 'local_migration_backup_error.dart';

/// Pasos de copia que buscamos.
///
/// `package:sqlite3` duerme 250 ms después de CADA paso, independientemente del
/// tamaño. Con 128 páginas fijas, una base de 21.683 páginas necesita 170 pasos
/// (42,5 s solo en pausas) y una de 200 MB pasaría de 100 s. Ajustando las
/// páginas por paso al tamaño real, el número de pasos queda acotado y la pausa
/// total se mantiene constante (~3 s) sin importar el tamaño de la base.
const int _targetSteps = 12;

/// Límites de páginas por paso: suficientes para no multiplicar pasos, y no tan
/// altos como para que un solo paso monopolice la copia.
const int _minPagesPerStep = 512;
const int _maxPagesPerStep = 8192;

/// Aborta si el respaldo deja de avanzar. Detecta bloqueos reales
/// (SQLITE_BUSY/LOCKED sostenido, E/S colgada) midiendo progreso, no duración,
/// para no castigar bases grandes.
const Duration _idleTimeout = Duration(seconds: 30);

/// Techo absoluto de seguridad. Medidos ~2 s para 85 MB, 10 minutos cubren
/// bases de decenas de GB; superarlo indica un fallo real y debe fallar seguro.
const Duration _hardCeiling = Duration(minutes: 10);

const String _integrityOk = 'ok';

Future<void> backupLocalDatabaseBeforeMigration({
  required String fileName,
  required String label,
  int? targetVersion,
}) async {
  final dbPath = await resolveLocalDatabasePath(fileName);
  final source = File(dbPath);
  if (!await source.exists()) return;

  Database? original;
  try {
    original = _openSource(dbPath);
    final currentVersion = _pragmaInt(original, 'user_version');
    if (targetVersion != null && currentVersion >= targetVersion) return;

    final pageCount = _pragmaInt(original, 'page_count');
    final pageSize = _pragmaInt(original, 'page_size');
    // Un fichero sin páginas no tiene nada que conservar: la migración lo
    // tratará como base nueva y no hay copia que publicar.
    if (pageCount <= 0 || pageSize <= 0) return;

    final sourceBytes = await source.length();
    final sourcePending = _countRows(original, 'pending_actions');
    final pagesPerStep = _pagesPerStep(pageCount);
    final expectedSteps = (pageCount + pagesPerStep - 1) ~/ pagesPerStep;

    // Restos de intentos anteriores (por ejemplo el fallo real de 147) no deben
    // acumularse en el equipo del cliente.
    await _cleanupStalePartialFiles(dbPath, label);

    try {
      final backupDir = await _createBackupDirectory(dbPath, label);
      final partial = File(
        p.join(backupDir.path, '${p.basename(dbPath)}.partial'),
      );
      if (await partial.exists()) {
        throw LocalMigrationBackupException(
          fileName,
          'Ya existe una copia de migración en esa ruta',
          details: partial.path,
        );
      }

      final watch = Stopwatch()..start();
      Database? destination;
      var steps = 0;
      int copyVersion;
      int? copyPending;
      try {
        destination = sqlite3.open(partial.path);
        destination.execute('PRAGMA synchronous = FULL');

        var lastFraction = -1.0;
        var lastProgressAt = Duration.zero;
        await for (final fraction in original.backup(
          destination,
          nPage: pagesPerStep,
        )) {
          steps++;
          if (fraction > lastFraction) {
            lastFraction = fraction;
            lastProgressAt = watch.elapsed;
          }
          if (watch.elapsed - lastProgressAt > _idleTimeout) {
            throw LocalMigrationBackupException(
              fileName,
              'El respaldo no avanza (posible bloqueo de la base)',
              details:
                  'paso=$steps progreso=${(lastFraction * 100).toStringAsFixed(1)}%',
            );
          }
          if (watch.elapsed > _hardCeiling) {
            throw LocalMigrationBackupException(
              fileName,
              'El respaldo excede el límite absoluto de seguridad',
              details: 'paso=$steps de ~$expectedSteps',
            );
          }
        }

        // Una copia parcial NUNCA se acepta: se verifica sobre la copia.
        final integrity = destination
            .select('PRAGMA integrity_check')
            .first
            .values
            .first;
        if (integrity != _integrityOk) {
          throw LocalMigrationBackupException(
            fileName,
            'La copia de migración no superó la verificación de integridad',
            details: 'integrity_check=$integrity',
          );
        }
        copyVersion = _pragmaInt(destination, 'user_version');
        if (copyVersion != currentVersion) {
          throw LocalMigrationBackupException(
            fileName,
            'La copia de migración no conserva la versión de esquema',
            details: 'origen=$currentVersion copia=$copyVersion',
          );
        }
        copyPending = _countRows(destination, 'pending_actions');
        if (sourcePending != null && copyPending != sourcePending) {
          throw LocalMigrationBackupException(
            fileName,
            'La copia de migración no conserva las operaciones pendientes',
            details: 'origen=$sourcePending copia=$copyPending',
          );
        }
      } finally {
        destination?.close();
      }

      final durationMs = watch.elapsedMilliseconds;
      final digest = await _sha256OfFile(partial);
      final completed = await partial.rename(
        p.join(backupDir.path, p.basename(dbPath)),
      );
      await File(p.join(backupDir.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'format': 'fullpos.migration-backup.v1',
          'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
          'fileName': p.basename(completed.path),
          'schemaVersion': copyVersion,
          'pendingActions': copyPending,
          'sha256': digest,
          'integrityCheck': _integrityOk,
          'method': 'SQLite Backup API',
          'pageCount': pageCount,
          'pageSize': pageSize,
          'pagesPerStep': pagesPerStep,
          'steps': steps,
          'durationMs': durationMs,
          'sourceBytes': sourceBytes,
          'copyBytes': await completed.length(),
          'idleTimeoutMs': _idleTimeout.inMilliseconds,
          'hardCeilingMs': _hardCeiling.inMilliseconds,
        }),
        flush: true,
      );
    } catch (error) {
      await _cleanupPartialFiles(dbPath, label);
      rethrow;
    }
  } on LocalMigrationBackupException {
    rethrow;
  } catch (error) {
    // Cualquier fallo de SQLite (base bloqueada, fichero ilegible, E/S) se
    // reporta como fallo de respaldo: la migración no debe continuar sin copia.
    throw LocalMigrationBackupException(
      fileName,
      'No se pudo respaldar la base antes de migrar',
      details: error.toString(),
    );
  } finally {
    original?.close();
  }
}

/// Abre la base en modo de solo lectura.
///
/// Si el modo estricto falla (por ejemplo un `-shm` de WAL que no puede
/// inicializarse), se reintenta en modo normal con `PRAGMA query_only = ON`,
/// que impide cualquier escritura desde esta conexión.
Database _openSource(String dbPath) {
  try {
    return sqlite3.open(dbPath, mode: OpenMode.readOnly);
  } on SqliteException {
    final fallback = sqlite3.open(dbPath);
    try {
      fallback.execute('PRAGMA query_only = ON');
    } catch (_) {
      fallback.close();
      rethrow;
    }
    return fallback;
  }
}

int _pragmaInt(Database db, String pragma) {
  final value = db.select('PRAGMA $pragma').first.values.first;
  return value is int ? value : int.tryParse('$value') ?? 0;
}

int? _countRows(Database db, String table) {
  final exists = db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
    [table],
  ).isNotEmpty;
  if (!exists) return null;
  final value = db.select('SELECT COUNT(*) FROM "$table"').first.values.first;
  return value is int ? value : int.tryParse('$value') ?? 0;
}

int _pagesPerStep(int pageCount) {
  final desired = (pageCount / _targetSteps).ceil();
  if (desired < _minPagesPerStep) return _minPagesPerStep;
  if (desired > _maxPagesPerStep) return _maxPagesPerStep;
  return desired;
}

Future<Directory> _createBackupDirectory(String dbPath, String label) async {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}_'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final base = Directory(
    p.join(p.dirname(dbPath), 'local_migration_backups', label),
  );
  await base.create(recursive: true);
  return base.createTemp('${stamp}_');
}

Future<String> _sha256OfFile(File file) async {
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    hasher.add(chunk);
  }
  hasher.close();
  final digest = sink.value;
  if (digest == null) {
    throw LocalMigrationBackupException(
      p.basename(file.path),
      'No se pudo calcular la huella de la copia de migración',
    );
  }
  return digest.toString();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Elimina copias parciales y sidecars temporales de respaldos anteriores.
///
/// Nunca toca la base original ni sus `-wal`/`-shm`: solo ficheros cuyo nombre
/// empieza por `<base>.partial`, que este respaldo crea y nunca publica sin
/// verificarlos.
Future<void> _cleanupPartialFiles(String dbPath, String label) async {
  await _deletePartialFiles(dbPath, label, minAge: Duration.zero);
}

/// Limpia restos antiguos antes de empezar. Solo borra copias `.partial` con
/// más de una hora: así nunca interfiere con otro respaldo en curso.
Future<void> _cleanupStalePartialFiles(String dbPath, String label) async {
  await _deletePartialFiles(dbPath, label, minAge: const Duration(hours: 1));
}

Future<void> _deletePartialFiles(
  String dbPath,
  String label, {
  required Duration minAge,
}) async {
  final base = Directory(
    p.join(p.dirname(dbPath), 'local_migration_backups', label),
  );
  if (!await base.exists()) return;

  final cutoff = DateTime.now().subtract(minAge);
  try {
    for (final entity in base.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final leftovers = entity
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => p
                .basename(file.path)
                .startsWith('${p.basename(dbPath)}.partial'),
          )
          .where((file) {
            if (minAge == Duration.zero) return true;
            try {
              return file.lastModifiedSync().isBefore(cutoff);
            } catch (_) {
              return false;
            }
          })
          .toList();
      if (leftovers.isEmpty) continue;
      for (final file in leftovers) {
        try {
          await file.delete();
        } catch (_) {
          // Un fichero bloqueado no debe ocultar el error original.
        }
      }
      try {
        if (entity.listSync().isEmpty) await entity.delete();
      } catch (_) {
        // La limpieza es best-effort; el error real ya se está propagando.
      }
    }
  } catch (_) {
    // Ídem: no sustituir el error original por un fallo de limpieza.
  }
}
