import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/core/storage/local_database_path.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/data/cotizaciones_local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('stores and reads quotations only inside the active company', () async {
    final dbName = 'tenant_quotes_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = CotizacionesLocalRepository(databaseFileName: dbName);

    await repo.upsert(_quote('q-a', 'Cliente A'), companyId: 'company-a');
    await repo.upsert(_quote('q-b', 'Cliente B'), companyId: 'company-b');
    await repo.saveDraft(
      _quote('draft-a', 'Borrador A'),
      companyId: 'company-a',
    );
    await repo.saveDraft(
      _quote('draft-b', 'Borrador B'),
      companyId: 'company-b',
    );

    expect(
      (await repo.listAll(companyId: 'company-a')).map((item) => item.id),
      ['q-a'],
    );
    expect(
      (await repo.listAll(companyId: 'company-b')).map((item) => item.id),
      ['q-b'],
    );
    expect((await repo.getDraft(companyId: 'company-a'))?.id, 'draft-a');
    expect((await repo.getDraft(companyId: 'company-b'))?.id, 'draft-b');
  });

  test('draft replacement is scoped to the active company only', () async {
    final dbName =
        'tenant_quote_drafts_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = CotizacionesLocalRepository(databaseFileName: dbName);

    await repo.saveDraft(
      _quote('draft-a-1', 'Borrador A 1'),
      companyId: 'company-a',
    );
    await repo.saveDraft(
      _quote('draft-b-1', 'Borrador B 1'),
      companyId: 'company-b',
    );
    await repo.saveDraft(
      _quote('draft-a-2', 'Borrador A 2'),
      companyId: 'company-a',
    );

    expect((await repo.getDraft(companyId: 'company-a'))?.id, 'draft-a-2');
    expect((await repo.getDraft(companyId: 'company-b'))?.id, 'draft-b-1');
  });

  test('delete and clear operations cannot affect another company', () async {
    final dbName =
        'tenant_quote_delete_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = CotizacionesLocalRepository(databaseFileName: dbName);

    await repo.upsert(_quote('shared-id', 'Cliente A'), companyId: 'company-a');
    await repo.upsert(_quote('shared-id', 'Cliente B'), companyId: 'company-b');
    await repo.upsert(_quote('only-b', 'Cliente B 2'), companyId: 'company-b');

    await repo.deleteById('shared-id', companyId: 'company-a');

    expect(await repo.listAll(companyId: 'company-a'), isEmpty);
    expect(
      (await repo.listAll(companyId: 'company-b')).map((item) => item.id),
      unorderedEquals(['only-b', 'shared-id']),
    );

    await repo.clearAll(companyId: 'company-b');

    expect(await repo.listAll(companyId: 'company-a'), isEmpty);
    expect(await repo.listAll(companyId: 'company-b'), isEmpty);
  });

  test('quarantines legacy rows without assigning ownership', () async {
    final dbName = 'legacy_quotes_${DateTime.now().microsecondsSinceEpoch}.db';
    final path = await resolveLocalDatabasePath(dbName);
    final legacyDb = await openDatabase(
      path,
      version: 6,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cotizaciones (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            customer_id TEXT,
            customer_name TEXT NOT NULL,
            customer_phone TEXT,
            note TEXT,
            include_itbis INTEGER NOT NULL DEFAULT 0,
            itbis_rate REAL NOT NULL DEFAULT 0.18,
            fiscal_tax_enabled INTEGER NOT NULL DEFAULT 0,
            fiscal_price_mode TEXT NOT NULL DEFAULT 'NO_TAX',
            taxable_base REAL NOT NULL DEFAULT 0,
            tax_amount REAL NOT NULL DEFAULT 0,
            exempt_amount REAL NOT NULL DEFAULT 0,
            discount_amount REAL NOT NULL DEFAULT 0,
            total REAL,
            global_discount_amount REAL NOT NULL DEFAULT 0,
            total_cost REAL,
            total_profit REAL,
            is_draft INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cotizacion_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cotizacion_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            nombre TEXT NOT NULL,
            unit_price REAL NOT NULL,
            qty REAL NOT NULL
          )
        ''');
        await db.insert('cotizaciones', {
          'id': 'legacy-q',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
          'updated_at': DateTime(2026, 1, 1).toIso8601String(),
          'customer_name': 'Legacy',
          'note': '',
          'is_draft': 0,
        });
      },
    );
    await legacyDb.close();

    final repo = CotizacionesLocalRepository(databaseFileName: dbName);

    expect(await repo.listAll(companyId: 'company-a'), isEmpty);

    final upgraded = await openDatabase(path);
    final rows = await upgraded.query(
      'cotizaciones',
      columns: ['id', 'company_id', 'legacy_quarantined'],
      where: 'id = ?',
      whereArgs: ['legacy-q'],
    );
    await upgraded.close();

    expect(rows, hasLength(1));
    expect(rows.single['company_id'], isNull);
    expect(rows.single['legacy_quarantined'], 1);

    final reopenedRepo = CotizacionesLocalRepository(databaseFileName: dbName);
    expect(await reopenedRepo.listAll(companyId: 'company-a'), isEmpty);
  });
}

CotizacionModel _quote(String id, String customerName) {
  return CotizacionModel(
    id: id,
    createdAt: DateTime(2026, 1, 1),
    customerId: null,
    customerName: customerName,
    customerPhone: null,
    note: '',
    includeItbis: false,
    itbisRate: 0.18,
    items: const [
      CotizacionItem(
        productId: 'p-1',
        nombre: 'Producto',
        imageUrl: null,
        unitPrice: 100,
        qty: 1,
      ),
    ],
  );
}
