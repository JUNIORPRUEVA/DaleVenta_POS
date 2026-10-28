import 'dart:io';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migración real a v4 desde outbox v1, v2 y v3, con SQLite de verdad.
///
/// El fallo que estas pruebas protegen: los índices de auditoría se creaban en
/// el tramo `v1→v3`, antes de que existiera `sale_attempt_audit`, y la
/// actualización fallaba con `no such table`.
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
    root = await Directory.systemTemp.createTemp('fullpos-mig4-');
    await databaseFactory.setDatabasesPath(root.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await databaseFactory.setDatabasesPath(previousPath);
    await root.delete(recursive: true);
  });

  Future<Database> openLegacy(String name, int version) {
    return databaseFactoryFfi.openDatabase(p.join(root.path, name));
  }

  Future<void> createV1(Database db) async {
    await db.execute('''
      CREATE TABLE cache_entries (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_actions (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        scope TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> createV2(Database db) async {
    await createV1(db);
    for (final column in [
      'company_id TEXT',
      'user_id TEXT',
      'terminal_id TEXT',
      'entity_type TEXT',
      'entity_id TEXT',
      'idempotency_key TEXT',
      'next_attempt_at INTEGER',
      'last_attempt_at INTEGER',
      'permanent INTEGER NOT NULL DEFAULT 0',
    ]) {
      await db.execute('ALTER TABLE pending_actions ADD COLUMN $column');
    }
  }

  Future<void> createV3(Database db) async {
    await createV2(db);
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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

  for (final legacy in [1, 2, 3]) {
    test('outbox v$legacy migra a la versión actual y crea la auditoría',
        () async {
      final name = 'legacy-v$legacy.db';
      final db = await openLegacy(name, legacy);
      switch (legacy) {
        case 1:
          await createV1(db);
        case 2:
          await createV2(db);
        default:
          await createV3(db);
      }
      final now = DateTime.utc(2026, 10, 7, 21, 26);
      await db.insert('pending_actions', {
        'id': 'sales.attempt:req-viejo',
        'type': 'sales.attempt',
        'scope': 'sales',
        if (legacy >= 2) 'company_id': 'company-a',
        if (legacy >= 2) 'user_id': 'user-a',
        if (legacy >= 2) 'idempotency_key': 'req-viejo',
        // En v1 no existen las columnas de identidad: el identificador vive en
        // el payload, igual que en los intentos reales de esa versión.
        'payload': '{"expectedTotalSold":1305.0,"clientRequestId":"req-viejo"}',
        'status': 'requires_action',
        'attempts': 0,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
      await db.setVersion(legacy);
      await db.close();

      final store = OfflineStore.forTesting(name);
      try {
        // En v1 las filas no llevan empresa: `includeUnscoped` las recupera tal
        // como las deja la migración, sin inventarles tenant.
        final actions = await store.listPendingActions(
          companyId: 'company-a',
          includeUnscoped: true,
        );
        expect(
          actions.map((a) => a.idempotencyKey),
          contains('req-viejo'),
          reason: 'el intento histórico debe sobrevivir a la migración',
        );

        // La tabla nueva existe y se puede escribir.
        await store.appendSaleAttemptAudit(
          SaleAttemptAuditEntry(
            id: 'audit-$legacy',
            pendingActionId: 'sales.attempt:req-viejo',
            clientRequestId: 'req-viejo',
            decision: SaleAttemptDecision.keptInconclusive,
            checkedAt: now,
            companyId: 'company-a',
            mechanism: 'sale-attempt-reconciliation-v1',
          ),
        );
        final audit = await store.listSaleAttemptAudit(companyId: 'company-a');
        expect(audit, hasLength(1));

        // La columna de huella existe: la reserva con huella funciona.
        await store.reserveRemoteSaleAttempt(
          PendingSyncAction(
            id: 'sales.attempt:req-nuevo',
            type: 'sales.attempt',
            scope: 'sales',
            companyId: 'company-a',
            userId: 'user-a',
            idempotencyKey: 'req-nuevo',
            operationFingerprint: 'huella-nueva',
            payload: const {'expectedTotalSold': 250.0},
            status: 'requires_action',
            attempts: 0,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        final unresolved = await store.listUnresolvedSaleAttempts(
          companyId: 'company-a',
          userId: 'user-a',
        );
        expect(
          unresolved.map((a) => a.idempotencyKey),
          contains('req-nuevo'),
          reason: 'tras migrar se puede reservar un intento con huella',
        );
        // Una fila v1 sin empresa NO se atribuye a ninguna empresa: aparece solo
        // en la consulta con `includeUnscoped`.
        expect(
          unresolved.length,
          legacy >= 2 ? 2 : 1,
          reason:
              'v1 no guarda empresa; atribuirla en silencio sería un riesgo '
              'de aislamiento multiempresa',
        );
      } finally {
        await store.closeForTesting();
      }

      final check = await databaseFactoryFfi.openDatabase(
        p.join(root.path, name),
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        expect(await check.getVersion(), 5);
        final integrity = await check.rawQuery('PRAGMA integrity_check');
        expect(integrity.single.values.single, 'ok');
      } finally {
        await check.close();
      }
    });
  }

  test('reabrir tras la migración no vuelve a migrar ni pierde la auditoría',
      () async {
    final name = 'legacy-reopen.db';
    final db = await openLegacy(name, 3);
    await createV3(db);
    await db.setVersion(3);
    await db.close();

    final first = OfflineStore.forTesting(name);
    await first.appendSaleAttemptAudit(
      SaleAttemptAuditEntry(
        id: 'audit-1',
        pendingActionId: 'sales.attempt:req-1',
        clientRequestId: 'req-1',
        decision: SaleAttemptDecision.autoConfirmed,
        checkedAt: DateTime.utc(2026, 10, 28, 9),
        companyId: 'company-a',
        mechanism: 'sale-attempt-reconciliation-v1',
      ),
    );
    await first.closeForTesting();

    final second = OfflineStore.forTesting(name);
    try {
      final audit = await second.listSaleAttemptAudit(companyId: 'company-a');
      expect(audit, hasLength(1));
      expect(audit.single.decision, SaleAttemptDecision.autoConfirmed);
    } finally {
      await second.closeForTesting();
    }
  });

  test('clearAll y cambio de empresa NO borran la evidencia histórica',
      () async {
    final name = 'legacy-clear.db';
    final db = await openLegacy(name, 3);
    await createV3(db);
    await db.setVersion(3);
    await db.close();

    final store = OfflineStore.forTesting(name);
    try {
      await store.appendSaleAttemptAudit(
        SaleAttemptAuditEntry(
          id: 'audit-a',
          pendingActionId: 'p1',
          clientRequestId: 'req-1',
          decision: SaleAttemptDecision.manualNotPerformed,
          checkedAt: DateTime.utc(2026, 10, 28, 9),
          companyId: 'company-a',
          actorRole: 'OWNER',
          mechanism: 'sale-attempt-reconciliation-v1',
        ),
      );
      await store.clearAll();
      final kept = await store.listSaleAttemptAudit(companyId: 'company-a');
      expect(kept, hasLength(1));

      final otherCompany = await store.listSaleAttemptAudit(
        companyId: 'company-b',
      );
      expect(otherCompany, isEmpty);
    } finally {
      await store.closeForTesting();
    }
  });
}
