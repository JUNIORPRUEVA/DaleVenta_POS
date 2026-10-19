import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('candidate opens a consistent UAT SQLite v3 copy without changing historical rows', () async {
    const expectedRoot = r'C:\src\fullpos-offline-safe-48h\.uat\phase15-sqlite-copy';
    expect(Platform.environment['DALEVENTAS_POS_ROOT'], expectedRoot);
    final path = '$expectedRoot/databases/fulltech_offline.db';
    expect(File(path).existsSync(), isTrue);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    const tables = ['pending_actions', 'offline_sales', 'offline_sale_items',
      'offline_sale_payments', 'offline_inventory_intents'];
    Future<Map<String, dynamic>> snapshot() async {
      final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true));
      try {
        final result = <String, dynamic>{'schemaVersion': await db.getVersion()};
        expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
        for (final table in tables) {
          final rows = await db.query(table);
          final encoded = rows.map(jsonEncode).toList()..sort();
          result[table] = {'rows': rows.length,
            'sha256': sha256.convert(utf8.encode(jsonEncode(encoded))).toString()};
        }
        return result;
      } finally { await db.close(); }
    }
    final before = await snapshot();
    expect(before['schemaVersion'], 3);
    final store = OfflineStore.forTesting('fulltech_offline.db');
    try {
      final sales = await store.listOfflineSales(
        companyId: '11111111-1111-4111-8111-111111111111',
        userId: '33333333-3333-4333-8333-333333333333');
      expect(sales.length, 8);
      final pending = await store.listPendingActions(
        companyId: '11111111-1111-4111-8111-111111111111',
        userId: '33333333-3333-4333-8333-333333333333');
      expect(pending.single.id, 'quotes.create:local_quote_1791944878261619');
      expect(pending.single.permanent, isTrue);
    } finally { await store.closeForTesting(); }
    final after = await snapshot();
    expect(after, before);
    await File('$expectedRoot/verification.json').writeAsString(jsonEncode({
      'status': 'PASS', 'before': before, 'after': after,
      'scope': 'Authentic manual UAT v3 backup opened by candidate; no claim of v1/v2 migration or historical binary execution',
    }));
  }, skip: Platform.environment['FULLPOS_PHASE15_SQLITE_COPY'] != 'true');
}
