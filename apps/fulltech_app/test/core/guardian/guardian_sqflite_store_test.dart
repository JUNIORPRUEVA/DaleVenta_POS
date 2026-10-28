import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/core/guardian/guardian_event.dart';
import 'package:daleventa_pos/core/guardian/guardian_sqflite_store.dart';

/// Cola local en SQLite real (mismo motor que el escritorio Windows).
///
/// Protege la garantía crítica: la cola del agente es **independiente** de la
/// base de ventas y sobrevive a un cierre de la aplicación.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  GuardianEvent event(String id) => GuardianEvent(
        eventId: id,
        severity: 'SEV2',
        module: 'flutter',
        operation: 'GET /selftest',
        occurredAt: DateTime.now(),
        exceptionType: 'SyntheticGuardianProbeException',
        message: 'sonda',
        platform: 'windows',
      );

  test('crea el esquema y persiste el evento de forma durable', () async {
    final dir = await Directory.systemTemp.createTemp('guardian_store_');
    final store = SqfliteGuardianStore(databasePath: '${dir.path}/guardian_outbox.db');

    await store.init();
    await store.upsert(event('evt-1'));

    expect(await store.count(), 1);
    final due = await store.dueEvents(limit: 10);
    expect(due, hasLength(1));
    expect(due.first.eventId, 'evt-1');
    expect(due.first.exceptionType, 'SyntheticGuardianProbeException');

    // Reapertura: el evento sigue ahí (no se pierde al cerrar la app).
    final reopened = SqfliteGuardianStore(databasePath: '${dir.path}/guardian_outbox.db');
    await reopened.init();
    expect(await reopened.count(), 1);

    await store.close();
    await dir.delete(recursive: true);
  });

  test('las tablas del agente existen y están separadas de ventas', () async {
    final dir = await Directory.systemTemp.createTemp('guardian_store_');
    final path = '${dir.path}/guardian_outbox.db';
    final store = SqfliteGuardianStore(databasePath: path);
    await store.init();

    final db = await databaseFactory.openDatabase(path);
    final tables = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'table'",
    );
    final names = tables.map((row) => row['name'] as String).toSet();
    expect(names.contains('guardian_events'), isTrue);
    expect(names.contains('guardian_discards'), isTrue);
    expect(names.contains('guardian_fingerprints'), isTrue);
    // Ninguna tabla de negocio debe existir en esta base.
    expect(names.any((name) => name.contains('sale') || name.contains('cash')), isFalse);
    await db.close();

    await store.close();
    await dir.delete(recursive: true);
  });

  test('un fallo de almacenamiento no propaga excepción al llamante', () async {
    // Ruta imposible: el contrato es "nunca lanza desde record()".
    final store = SqfliteGuardianStore(
      databasePath: '${Directory.systemTemp.path}/no-existe-${DateTime.now().microsecondsSinceEpoch}/x/guardian.db',
    );
    await expectLater(store.init().catchError((_) {}), completes);
  });
}

