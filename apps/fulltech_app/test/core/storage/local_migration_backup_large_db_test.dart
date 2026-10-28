import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:daleventa_pos/core/storage/local_migration_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Regresión del fallo real de la actualización Windows 146→147.
///
/// El respaldo previo a la migración abortaba con bases grandes porque mezclaba
/// una guarda fija de 10 s con pasos de 128 páginas (250 ms de pausa por paso
/// dentro de `package:sqlite3`). Una base de 85 MB necesita ~42 s así, de modo
/// que la migración v3→v5 nunca podía completarse en un equipo real.
///
/// Estas pruebas usan SQLite de verdad y bases del tamaño real del problema.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String previousPath;

  setUpAll(() {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() async {
    previousPath = await ffi.databaseFactory.getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-backup-large-');
    await ffi.databaseFactory.setDatabasesPath(root.path);
  });

  tearDown(() async {
    await ffi.databaseFactory.setDatabasesPath(previousPath);
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // En Windows un fichero aún abierto puede impedir el borrado.
    }
  });

  /// Crea una base con el esquema real de outbox v3 y la llena hasta [megabytes].
  ///
  /// Usa WAL (igual que producción) para que el respaldo tenga que incluir el
  /// contenido todavía no checkpointado del `-wal`.
  void createLargeOutbox(String name, int megabytes, {int pendingRows = 3}) {
    final db = sqlite3.open(p.join(root.path, name));
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=OFF');
      db.execute('PRAGMA user_version=3');
      db.execute('''
        CREATE TABLE cache_entries (
          cache_key TEXT PRIMARY KEY,
          payload TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE pending_actions (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          scope TEXT NOT NULL,
          company_id TEXT,
          user_id TEXT,
          terminal_id TEXT,
          entity_type TEXT,
          entity_id TEXT,
          idempotency_key TEXT,
          payload TEXT NOT NULL,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          error TEXT,
          next_attempt_at INTEGER,
          last_attempt_at INTEGER,
          permanent INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE bulk_payload (
          id INTEGER PRIMARY KEY,
          blob BLOB NOT NULL
        )
      ''');

      final chunk = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 0x41);
      db.execute('BEGIN');
      for (var i = 0; i < megabytes; i++) {
        db.execute('INSERT INTO bulk_payload (blob) VALUES (?)', [chunk]);
      }
      for (var i = 0; i < pendingRows; i++) {
        db.execute(
          'INSERT INTO pending_actions '
          '(id, type, scope, company_id, user_id, idempotency_key, payload, '
          'status, attempts, created_at, updated_at) '
          "VALUES (?, 'sales.attempt', 'sales', 'company-a', 'user-a', ?, ?, "
          "'requires_action', 0, ?, ?)",
          [
            'sales.attempt:req-$i',
            'req-$i',
            '{"expectedTotalSold":${100 + i}.0}',
            1791242551423 + i,
            1791242551423 + i,
          ],
        );
      }
      db.execute('COMMIT');
    } finally {
      db.close();
    }
  }

  int countRows(String path, String table) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return db.select('SELECT COUNT(*) FROM "$table"').first.values.first
          as int;
    } finally {
      db.close();
    }
  }

  List<File> manifestsFor(String label) {
    final base = Directory(p.join(root.path, 'local_migration_backups', label));
    if (!base.existsSync()) return const [];
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path) == 'manifest.json')
        .toList();
  }

  /// Copias parciales presentes en cualquier carpeta de respaldo.
  List<File> leftoverPartials() {
    final base = Directory(p.join(root.path, 'local_migration_backups'));
    if (!base.existsSync()) return const [];
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.contains('.partial'))
        .toList();
  }

  group('respaldo previo a migración con bases grandes', () {
    for (final megabytes in [5, 25, 85, 200]) {
      test(
        '${megabytes}MB: copia consistente verificada y original intacto',
        () async {
          final name = 'outbox_${megabytes}mb.db';
          createLargeOutbox(name, megabytes, pendingRows: 4);
          final dbPath = p.join(root.path, name);
          final originalBytes = File(dbPath).lengthSync();
          final originalSha = await _sha256(File(dbPath));
          expect(originalBytes, greaterThan(megabytes * 1000 * 1000));

          final watch = Stopwatch()..start();
          await backupLocalDatabaseBeforeMigration(
            fileName: name,
            label: 'offline_outbox',
            targetVersion: 5,
          );
          watch.stop();

          final manifests = manifestsFor('offline_outbox');
          expect(
            manifests,
            hasLength(1),
            reason: 'debe publicar exactamente una copia',
          );
          final manifest =
              jsonDecode(await manifests.single.readAsString())
                  as Map<String, dynamic>;
          final copy = File(p.join(manifests.single.parent.path, name));

          expect(manifest['method'], 'SQLite Backup API');
          expect(manifest['integrityCheck'], 'ok');
          expect(manifest['schemaVersion'], 3);
          expect(manifest['pendingActions'], 4);
          expect(manifest['sha256'], await _sha256(copy));
          expect(
            manifest['steps'],
            lessThanOrEqualTo(20),
            reason: 'los pasos deben quedar acotados sin importar el tamaño',
          );
          expect(manifest['durationMs'], lessThan(60000));

          // La copia es utilizable: integridad, claves foráneas y registros.
          final copyDb = sqlite3.open(copy.path, mode: OpenMode.readOnly);
          try {
            expect(
              copyDb.select('PRAGMA integrity_check').first.values.first,
              'ok',
            );
            expect(copyDb.select('PRAGMA foreign_key_check'), isEmpty);
            expect(
              copyDb
                  .select('SELECT COUNT(*) FROM pending_actions')
                  .first
                  .values
                  .first,
              4,
            );
            expect(
              copyDb
                  .select('SELECT COUNT(*) FROM bulk_payload')
                  .first
                  .values
                  .first,
              megabytes,
            );
            expect(copyDb.select('PRAGMA user_version').first.values.first, 3);
          } finally {
            copyDb.close();
          }

          // El original no se toca ni se "repara" para que la prueba pase.
          expect(File(dbPath).existsSync(), isTrue);
          expect(await _sha256(File(dbPath)), originalSha);
          expect(countRows(dbPath, 'pending_actions'), 4);

          // Sin restos parciales en ninguna carpeta de respaldo.
          expect(leftoverPartials(), isEmpty);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }

    test('base ya migrada (v5) no vuelve a respaldar', () async {
      final name = 'outbox_v5.db';
      createLargeOutbox(name, 5);
      final db = sqlite3.open(p.join(root.path, name));
      db.execute('PRAGMA user_version=5');
      db.close();

      await backupLocalDatabaseBeforeMigration(
        fileName: name,
        label: 'offline_outbox',
        targetVersion: 5,
      );
      expect(manifestsFor('offline_outbox'), isEmpty);
    });

    test(
      'un fichero que no es una base falla seguro y no deja copias',
      () async {
        final name = 'roto.db';
        final broken = File(p.join(root.path, name));
        await broken.writeAsBytes(
          Uint8List.fromList(List<int>.generate(4096, (i) => i % 251)),
        );
        final before = await _sha256(broken);

        await expectLater(
          backupLocalDatabaseBeforeMigration(
            fileName: name,
            label: 'offline_outbox',
            targetVersion: 5,
          ),
          throwsA(isA<LocalMigrationBackupException>()),
        );

        expect(
          await _sha256(broken),
          before,
          reason: 'un respaldo fallido no puede alterar el original',
        );
        final leftovers = leftoverPartials();
        expect(
          leftovers,
          isEmpty,
          reason: 'una copia parcial nunca se conserva',
        );
      },
    );

    test(
      'restos parciales de un intento anterior no bloquean ni se publican',
      () async {
        final name = 'outbox_restos.db';
        createLargeOutbox(name, 1);
        final dbPath = p.join(root.path, name);
        final before = await _sha256(File(dbPath));

        // Restos del fallo real de 147: directorios con copias .partial antiguas.
        final old = DateTime.now().subtract(const Duration(hours: 5));
        for (final suffix in ['a', 'b']) {
          final dir = Directory(
            p.join(
              root.path,
              'local_migration_backups',
              'offline_outbox',
              suffix,
            ),
          );
          await dir.create(recursive: true);
          for (final file in ['$name.partial', '$name.partial-journal']) {
            final created = File(p.join(dir.path, file));
            await created.writeAsString('parcial');
            created.setLastModifiedSync(old);
          }
        }

        await backupLocalDatabaseBeforeMigration(
          fileName: name,
          label: 'offline_outbox',
          targetVersion: 5,
        );

        final manifests = manifestsFor('offline_outbox');
        expect(manifests, hasLength(1));
        final manifest =
            jsonDecode(await manifests.single.readAsString())
                as Map<String, dynamic>;
        expect(manifest['integrityCheck'], 'ok');
        final copy = File(p.join(manifests.single.parent.path, name));
        expect(await _sha256(copy), manifest['sha256']);

        // Los restos antiguos se limpian; solo sobrevive la copia verificada.
        final leftovers = leftoverPartials();
        expect(leftovers, isEmpty);
        expect(await _sha256(File(dbPath)), before);
      },
    );

    test(
      'bloqueo exclusivo del origen no cuelga el respaldo',
      () async {
        final name = 'outbox_bloqueada.db';
        createLargeOutbox(name, 5);
        final dbPath = p.join(root.path, name);

        final holder = sqlite3.open(dbPath);
        try {
          holder.execute('PRAGMA journal_mode=DELETE');
          holder.execute('BEGIN EXCLUSIVE');
          holder.execute("INSERT INTO cache_entries VALUES ('lock', 'x', 1)");

          final watch = Stopwatch()..start();
          await expectLater(
            backupLocalDatabaseBeforeMigration(
              fileName: name,
              label: 'offline_outbox',
              targetVersion: 5,
            ),
            throwsA(isA<LocalMigrationBackupException>()),
          );
          watch.stop();
          expect(
            watch.elapsed,
            lessThan(const Duration(seconds: 90)),
            reason: 'debe fallar por falta de progreso, no colgarse',
          );
        } finally {
          holder.execute('ROLLBACK');
          holder.close();
        }

        expect(File(dbPath).existsSync(), isTrue);
        final leftovers = leftoverPartials();
        expect(leftovers, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Future<String> _sha256(File file) async {
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    hasher.add(chunk);
  }
  hasher.close();
  final digest = sink.value;
  if (digest == null) throw StateError('no se pudo calcular el sha256');
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
