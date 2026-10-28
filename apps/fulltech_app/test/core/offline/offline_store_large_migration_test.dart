import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migración real del outbox a v5 sobre una base del tamaño de producción.
///
/// Reproduce el escenario que rompió la actualización 146→147: una base de
/// ~85 MB con acciones pendientes. La migración debe respaldar, migrar y
/// conservar exactamente los registros, sin duplicar ventas ni pagos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String previousPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    previousPath = await getDatabasesPath();
    root = await Directory.systemTemp.createTemp('fullpos-large-migrate-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await databaseFactory.setDatabasesPath(previousPath);
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // En Windows un fichero aún abierto puede impedir el borrado.
    }
  });

  void createV3Schema(raw.Database db) {
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
      CREATE TABLE offline_sales (
        local_id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        server_id TEXT,
        client_request_id TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        total_sold REAL NOT NULL DEFAULT 0,
        sale_occurred_at INTEGER NOT NULL,
        synced_at INTEGER,
        error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE offline_sale_items (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        product_id TEXT,
        product_name_snapshot TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE offline_sale_payments (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        method TEXT NOT NULL,
        cash_amount REAL NOT NULL DEFAULT 0,
        transfer_amount REAL NOT NULL DEFAULT 0,
        credit_amount REAL NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE offline_inventory_intents (
        id TEXT PRIMARY KEY,
        sale_local_id TEXT NOT NULL,
        company_id TEXT NOT NULL,
        product_id TEXT,
        quantity_delta REAL NOT NULL,
        idempotency_key TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  void createV4Extras(raw.Database db) {
    db.execute(
      'ALTER TABLE pending_actions ADD COLUMN operation_fingerprint TEXT',
    );
    db.execute('''
      CREATE TABLE sale_attempt_audit (
        id TEXT PRIMARY KEY,
        pending_action_id TEXT NOT NULL,
        client_request_id TEXT NOT NULL,
        company_id TEXT,
        user_id TEXT,
        decision TEXT NOT NULL,
        server_status TEXT,
        guidance TEXT,
        voided INTEGER NOT NULL DEFAULT 0,
        sale_id TEXT,
        total_sold REAL,
        payment_method TEXT,
        movement_id TEXT,
        actor_user_id TEXT,
        actor_role TEXT,
        note TEXT,
        operation_fingerprint TEXT,
        mechanism TEXT NOT NULL,
        checked_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE INDEX idx_sale_attempt_audit_scope
      ON sale_attempt_audit(company_id, client_request_id, checked_at)
    ''');
    db.execute('''
      CREATE INDEX idx_sale_attempt_audit_action
      ON sale_attempt_audit(pending_action_id, checked_at)
    ''');
    db.execute('''
      CREATE INDEX idx_pending_actions_attempt_fingerprint
      ON pending_actions(company_id, type, operation_fingerprint, status)
    ''');
  }

  /// Crea la base con [version] (3 o 4), la llena hasta ~[megabytes] y deja
  /// una venta offline y una acción pendiente que deben sobrevivir intactas.
  void seedDatabase(String name, int version, int megabytes) {
    final db = raw.sqlite3.open(p.join(root.path, name));
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=OFF');
      createV3Schema(db);
      if (version >= 4) createV4Extras(db);
      db.execute('''
        CREATE TABLE bulk_payload (id INTEGER PRIMARY KEY, blob BLOB NOT NULL)
      ''');

      final chunk = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 0x42);
      db.execute('BEGIN');
      for (var i = 0; i < megabytes; i++) {
        db.execute('INSERT INTO bulk_payload (blob) VALUES (?)', [chunk]);
      }
      const now = 1791242551423;
      db.execute(
        'INSERT INTO pending_actions '
        '(id, type, scope, company_id, user_id, idempotency_key, payload, '
        'status, attempts, created_at, updated_at'
        '${version >= 4 ? ', operation_fingerprint' : ''}) '
        "VALUES ('sales.attempt:req-historico', 'sales.attempt', 'sales', "
        "'company-a', 'user-a', 'req-historico', "
        "'{\"expectedTotalSold\":500.0}', 'requires_action', 0, ?, ?"
        '${version >= 4 ? ", 'huella-historica'" : ''})',
        [now, now],
      );
      db.execute(
        'INSERT INTO offline_sales VALUES '
        "('local_sale_req_1', 'company-a', 'user-a', NULL, 'req-1', "
        "'pending', '{}', 500.0, ?, NULL, NULL, ?, ?)",
        [now, now, now],
      );
      db.execute(
        'INSERT INTO offline_sale_items VALUES '
        "('local_sale_req_1_item_0', 'local_sale_req_1', 'company-a', "
        "'prod-1', 'Producto', 1.0, 250.0, '{}', ?)",
        [now],
      );
      db.execute(
        'INSERT INTO offline_sale_items VALUES '
        "('local_sale_req_1_item_1', 'local_sale_req_1', 'company-a', "
        "'prod-2', 'Producto', 1.0, 250.0, '{}', ?)",
        [now],
      );
      db.execute(
        'INSERT INTO offline_sale_payments VALUES '
        "('local_sale_req_1_payment', 'local_sale_req_1', 'company-a', "
        "'cash', 500.0, 0.0, 0.0, '{}', ?)",
        [now],
      );
      db.execute('COMMIT');
      db.execute('PRAGMA user_version=$version');
    } finally {
      db.close();
    }
  }

  int count(String path, String table) {
    final db = raw.sqlite3.open(path, mode: raw.OpenMode.readOnly);
    try {
      return db.select('SELECT COUNT(*) FROM "$table"').first.values.first
          as int;
    } finally {
      db.close();
    }
  }

  List<File> manifests() {
    final base = Directory(
      p.join(root.path, 'local_migration_backups', 'offline_outbox'),
    );
    if (!base.existsSync()) return const [];
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path) == 'manifest.json')
        .toList();
  }

  for (final version in [3, 4]) {
    test(
      'outbox v$version de 85 MB migra a v5 conservando los registros',
      () async {
        final name = 'fulltech_offline_v$version.db';
        seedDatabase(name, version, 85);
        final dbPath = p.join(root.path, name);
        expect(File(dbPath).lengthSync(), greaterThan(85 * 1000 * 1000));

        final watch = Stopwatch()..start();
        final store = OfflineStore.forTesting(name);
        try {
          final pending = await store.listPendingActions(
            companyId: 'company-a',
          );
          expect(
            pending.map((action) => action.idempotencyKey),
            contains('req-historico'),
            reason: 'la acción pendiente debe sobrevivir a la migración',
          );
        } finally {
          await store.closeForTesting();
        }
        watch.stop();

        // La copia previa se publicó una sola vez y verificada.
        final copies = manifests();
        expect(
          copies,
          hasLength(1),
          reason: 'una única copia verificada por migración',
        );
        final manifestText = await copies.single.readAsString();
        expect(manifestText, contains('"integrityCheck":"ok"'));
        expect(manifestText, contains('"pendingActions":1'));

        // Esquema v5 y datos intactos, sin duplicar venta ni pago.
        final check = raw.sqlite3.open(dbPath, mode: raw.OpenMode.readOnly);
        try {
          expect(check.select('PRAGMA user_version').first.values.first, 5);
          expect(
            check.select('PRAGMA integrity_check').first.values.first,
            'ok',
          );
          expect(check.select('PRAGMA foreign_key_check'), isEmpty);
          expect(count(dbPath, 'pending_actions'), 1);
          expect(count(dbPath, 'offline_sales'), 1);
          expect(count(dbPath, 'offline_sale_items'), 2);
          expect(count(dbPath, 'offline_sale_payments'), 1);
          expect(count(dbPath, 'bulk_payload'), 85);
          final tables = check
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((row) => row['name'])
              .toSet();
          expect(
            tables,
            containsAll(['sale_attempt_audit', 'sale_cart_override']),
          );
        } finally {
          check.close();
        }
        expect(watch.elapsed, lessThan(const Duration(minutes: 2)));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'reiniciar tras migrar v$version no vuelve a respaldar ni duplica',
      () async {
        final name = 'fulltech_offline_reopen_v$version.db';
        seedDatabase(name, version, 10);

        final first = OfflineStore.forTesting(name);
        await first.listPendingActions(companyId: 'company-a');
        await first.closeForTesting();
        expect(manifests(), hasLength(1));

        final second = OfflineStore.forTesting(name);
        try {
          final pending = await second.listPendingActions(
            companyId: 'company-a',
          );
          expect(
            pending.map((action) => action.idempotencyKey),
            contains('req-historico'),
          );
        } finally {
          await second.closeForTesting();
        }

        expect(
          manifests(),
          hasLength(1),
          reason: 'una base ya migrada no se respalda otra vez',
        );
        expect(count(p.join(root.path, name), 'offline_sales'), 1);
        expect(count(p.join(root.path, name), 'offline_sale_payments'), 1);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
