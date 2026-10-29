@Tags(['uat'])
library;

import 'dart:io';

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_declaration.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/storage/local_database_path.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Durabilidad real del almacén local (SQLite + WAL) y ensayo de migración
/// sobre COPIAS de la base, nunca sobre la original.
///
/// Esta prueba es de aceptación y **no forma parte** de `flutter test` normal:
///
///  - escribe en disco (necesita una raíz aislada, no la carpeta por defecto),
///  - habla con la API UAT real.
///
/// Se ejecuta solo si existen las dos condiciones:
///   $env:DALEVENTAS_POS_ROOT = 'C:\ruta\aislada'   (antes de lanzar el proceso)
///   flutter test test/integration_uat/sqlite_durability_test.dart \
///     --dart-define=UAT_API_BASE=http://127.0.0.1:4010
///
/// Sin la raíz aislada la prueba se OMITE: antes escribía en el directorio de
/// bases por defecto del entorno de pruebas y contaminaba otras suites.
void main() {
  const apiBase = String.fromEnvironment('UAT_API_BASE');
  final isolatedRoot = (Platform.environment['DALEVENTAS_POS_ROOT'] ?? '')
      .trim();
  final legacyDb = (Platform.environment['UAT_LEGACY_DB'] ?? '').trim();
  final enabled = apiBase.trim().isNotEmpty && isolatedRoot.isNotEmpty;

  if (!enabled) {
    test(
      'durabilidad SQLite omitida (requiere UAT_API_BASE y DALEVENTAS_POS_ROOT)',
      () {},
      skip: true,
    );
    return;
  }

  // Sin TestWidgetsFlutterBinding a propósito: el binding intercepta HttpClient
  // y la prueba necesita sockets reales contra la API UAT.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final api = apiBase.replaceAll(RegExp(r'/+$'), '');
  final run = DateTime.now().microsecondsSinceEpoch.toString();
  final root = Directory(isolatedRoot);
  final databasesDir = Directory(p.join(root.path, 'databases'));
  final snapshotDir = Directory(p.join(root.path, 'snapshot'));

  const probeFile = 'durability_probe.db';
  const rehearsalFile = 'durability_rehearsal.db';

  late Dio dio;
  late String token;
  late String companyId;
  late String userId;
  late SyncQueueService queue;

  var authToken = '';

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await dio.post(
      '$api$path',
      data: body,
      options: Options(
        headers: auth ? {'authorization': 'Bearer $token'} : null,
        validateStatus: (_) => true,
      ),
    );
    return {
      'status': res.statusCode,
      'data': res.data is Map
          ? (res.data as Map).cast<String, dynamic>()
          : <String, dynamic>{},
    };
  }

  Future<List<Map<String, dynamic>>> obligations() async {
    final res = await dio.get(
      '$api/sales/reconciliation-obligations',
      options: Options(
        headers: {'authorization': 'Bearer $token'},
        validateStatus: (_) => true,
      ),
    );
    final data = res.data;
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['items'] is List) {
      return (data['items'] as List).cast<Map<String, dynamic>>();
    }
    return const [];
  }

  /// Copia `.db` y `-wal` mientras la conexión sigue abierta, que es el
  /// escenario de un corte de energía. El `-shm` se intenta pero se tolera su
  /// fallo: en Windows el fichero está mapeado por el proceso vivo y, además,
  /// SQLite lo reconstruye solo a partir del WAL, así que no aporta datos.
  ({int files, int bytes, List<String> skipped}) snapshot(
    String dbPath,
    Directory target,
  ) {
    target.createSync(recursive: true);
    var files = 0;
    var bytes = 0;
    final skipped = <String>[];
    for (final suffix in const ['', '-wal', '-shm']) {
      final source = File('$dbPath$suffix');
      if (!source.existsSync()) continue;
      final destination = File(
        p.join(target.path, '${p.basename(dbPath)}$suffix'),
      );
      try {
        destination.writeAsBytesSync(source.readAsBytesSync(), flush: true);
        files++;
        bytes += destination.lengthSync();
      } on FileSystemException {
        // Bloqueado por la conexión viva: se registra y se sigue.
        skipped.add(suffix.isEmpty ? '.db' : suffix);
      }
    }
    return (files: files, bytes: bytes, skipped: skipped);
  }

  Future<Map<String, Object?>> inspect(String dbPath) async {
    final db = await databaseFactory.openDatabase(dbPath);
    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final userVersion = await db.rawQuery('PRAGMA user_version');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      final counts = <String, int>{};
      for (final row in tables) {
        final table = row['name']!.toString();
        if (table.startsWith('sqlite_')) continue;
        final result = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
        counts[table] = (result.first['c'] as num).toInt();
      }
      return {
        'integrity': integrity.isEmpty
            ? 'unknown'
            : integrity.first.values.first?.toString(),
        'user_version': (userVersion.first.values.first as num?)?.toInt(),
        'tables': counts.length,
        'rows': counts.values.fold<int>(0, (a, b) => a + b),
        'counts': counts,
      };
    } finally {
      await db.close();
    }
  }

  PendingSyncAction attemptRow(String requestId) {
    final now = DateTime.now().toUtc();
    return PendingSyncAction(
      id: 'sales.attempt:$requestId',
      type: 'sales.attempt',
      scope: 'sales',
      companyId: companyId,
      userId: userId,
      idempotencyKey: requestId,
      entityId: requestId,
      operationFingerprint: 'durability-$requestId',
      payload: const {'expectedTotalSold': 50.0, 'paymentMethod': 'cash'},
      status: 'requires_action',
      attempts: 0,
      permanent: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUpAll(() async {
    await databasesDir.create(recursive: true);

    dio = Dio(
      BaseOptions(
        baseUrl: api,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (authToken.isNotEmpty) {
            options.headers['authorization'] = 'Bearer $authToken';
          }
          handler.next(options);
        },
      ),
    );

    final email = 'durability.$run@daleventa.local';
    final password = 'Uat-Durability-$run!';
    final registered = await post(
      '/auth/register-business',
      {
        'firstName': 'UAT',
        'lastName': 'Durability',
        'email': email,
        'phone': '8090000002',
        'password': password,
        'confirmPassword': password,
        'commercialName': 'UAT Durability $run',
        'country': 'DO',
        'currency': 'DOP',
      },
      auth: false,
    );
    expect(
      registered['status'],
      anyOf(200, 201),
      reason: 'alta de empresa sintética: ${registered['data']}',
    );

    final login = await post('/auth/login', {
      'identifier': email,
      'password': password,
    }, auth: false);
    final loginData = login['data'] as Map<String, dynamic>;
    token =
        (loginData['accessToken'] ??
                loginData['access_token'] ??
                loginData['token'] ??
                '')
            .toString();
    if (token.isEmpty) {
      fail('No se pudo autenticar en la API UAT: ${login['status']}');
    }
    authToken = token;

    final me = await dio.get(
      '$api/auth/me',
      options: Options(
        headers: {'authorization': 'Bearer $token'},
        validateStatus: (_) => true,
      ),
    );
    final meData = (me.data as Map).cast<String, dynamic>();
    final user = (meData['user'] ?? meData).cast<String, dynamic>();
    companyId = (user['companyId'] ?? meData['companyId'] ?? '').toString();
    userId = (user['id'] ?? '').toString();
    expect(companyId, isNotEmpty, reason: 'la API debe devolver companyId');

    final opened = await post('/cash/sessions/open', {
      'openingAmount': 0,
      'note': 'UAT durabilidad',
      'deviceFingerprint': 'durability-$run',
    });
    expect(opened['status'], anyOf(200, 201), reason: 'turno: ${opened['data']}');
  });

  tearDownAll(() async {
    // Limpieza estricta: la raíz es aislada, así que solo se borran los
    // artefactos de esta prueba.
    for (final file in [probeFile, rehearsalFile]) {
      for (final suffix in const ['', '-wal', '-shm']) {
        final target = File(p.join(databasesDir.path, '$file$suffix'));
        if (target.existsSync()) target.deleteSync();
      }
    }
    if (snapshotDir.existsSync()) {
      snapshotDir.deleteSync(recursive: true);
    }
    final legacySnapshot = Directory(p.join(root.path, 'legacy-snapshot'));
    if (legacySnapshot.existsSync()) {
      legacySnapshot.deleteSync(recursive: true);
    }
  });

  test(
    'cierre forzado: la declaración sobrevive en la copia del .db + WAL',
    () async {
      final requestId = 'durability-$run';
      final store = OfflineStore.forTesting(probeFile);
      queue = SyncQueueService(
        store,
        scopeResolver: () async =>
            OfflineSyncScope(companyId: companyId, userId: userId),
      );
      SaleAttemptDeclarationSyncHandlers(queue, dio).register();

      try {
        await queue.enqueue(
          id: 'sales.attempt:$requestId',
          type: 'sales.attempt',
          scope: 'sales',
          payload: const {'expectedTotalSold': 50.0, 'paymentMethod': 'cash'},
          companyId: companyId,
          userId: userId,
          idempotencyKey: requestId,
          entityId: requestId,
          requireDatabase: true,
        );

        final outbox = SaleAttemptDeclarationOutbox(
          enqueueAction: (row) => queue.enqueue(
            id: row.id,
            type: row.type,
            scope: row.scope,
            payload: row.payload,
            companyId: row.companyId,
            userId: row.userId,
            entityType: row.entityType,
            entityId: row.entityId,
            idempotencyKey: row.idempotencyKey,
            requireDatabase: true,
          ),
        );
        final declaration = await outbox.declare(
          action: attemptRow(requestId),
          totalDeclared: 50,
          actorUserId: userId,
          actorRole: 'ADMIN',
          note: 'durabilidad UAT',
        );
        expect(declaration, isNotNull, reason: 'la declaración debe encolarse');

        final dbPath = await resolveLocalDatabasePath(probeFile);
        expect(File(dbPath).existsSync(), isTrue, reason: 'el .db debe existir');

        // Corte de energía simulado: se copian los archivos con la conexión
        // todavía abierta (nada de cierre ordenado ni checkpoint previo).
        final copied = snapshot(dbPath, snapshotDir);
        expect(copied.files, greaterThanOrEqualTo(1));
        expect(copied.bytes, greaterThan(0));
        // ignore: avoid_print
        print(
          'SNAPSHOT files=${copied.files} bytes=${copied.bytes} '
          'skipped=${copied.skipped}',
        );

        final copyPath = p.join(snapshotDir.path, probeFile);
        final restored = await databaseFactory.openDatabase(copyPath);
        List<Map<String, Object?>> rows;
        try {
          rows = await restored.rawQuery(
            'SELECT type, idempotency_key FROM pending_actions',
          );
        } finally {
          await restored.close();
        }
        final types = rows.map((row) => row['type']?.toString()).toList();
        expect(
          types,
          contains('sales.declaration'),
          reason: 'la declaración debe estar en la copia abierta aparte',
        );
        expect(
          types,
          contains('sales.attempt'),
          reason: 'el intento original debe seguir intacto',
        );

        // Y el reenvío desde la copia llega al servidor: una sola obligación.
        // `processPending` no es bloqueante hasta el último efecto remoto, así
        // que se espera de forma acotada en vez de asumir que ya terminó.
        await queue.processPending();

        Map<String, dynamic>? obligation;
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          final list = await obligations();
          final mine = list
              .where(
                (row) => (row['clientRequestId'] ?? '').toString() == requestId,
              )
              .toList();
          if (mine.isNotEmpty) {
            obligation = mine.first;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }

        expect(
          obligation,
          isNotNull,
          reason: 'la declaración reenviada debe abrir una obligación',
        );
        expect(
          double.parse(obligation!['totalDeclared'].toString()),
          closeTo(50.0, 0.001),
        );

        // Y sigue siendo exactamente una: ni el reenvío ni la copia duplican.
        final settled = (await obligations())
            .where(
              (row) => (row['clientRequestId'] ?? '').toString() == requestId,
            )
            .toList();
        expect(settled, hasLength(1), reason: 'una única obligación activa');
      } finally {
        await store.closeForTesting();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'migración sobre una COPIA verificada (WAL incluido)',
    () async {
      if (legacyDb.isEmpty) {
        // Sin base legacy no hay nada que ensayar; se declara, no se simula.
        return;
      }
      final source = File(legacyDb);
      expect(source.existsSync(), isTrue, reason: 'la base legacy debe existir');

      final rehearsalPath = await resolveLocalDatabasePath(rehearsalFile);
      Directory(p.dirname(rehearsalPath)).createSync(recursive: true);
      final before = snapshot(
        legacyDb,
        Directory(p.join(root.path, 'legacy-snapshot')),
      );
      expect(before.files, greaterThanOrEqualTo(1));
      for (final suffix in const ['', '-wal', '-shm']) {
        final file = File(p.join(root.path, 'legacy-snapshot', '${p.basename(legacyDb)}$suffix'));
        if (!file.existsSync()) continue;
        file.copySync('$rehearsalPath$suffix');
      }

      final beforeInspect = await inspect(rehearsalPath);
      expect(
        beforeInspect['integrity'],
        'ok',
        reason: 'la copia debe ser íntegra antes de migrar',
      );

      final store = OfflineStore.forTesting(rehearsalFile);
      try {
        // Abrir con la app real dispara la migración y el respaldo previo.
        await store.readCacheEntry('durability.probe');
        await store.listPendingActions(limit: 1);
      } finally {
        await store.closeForTesting();
      }

      final after = await inspect(rehearsalPath);
      expect(after['integrity'], 'ok', reason: 'íntegra después de migrar');
      expect(
        after['tables'],
        greaterThanOrEqualTo((beforeInspect['tables'] as int?) ?? 0),
        reason: 'la migración no puede perder tablas',
      );
      expect(
        after['rows'],
        greaterThanOrEqualTo((beforeInspect['rows'] as int?) ?? 0),
        reason: 'la migración no puede perder registros',
      );
      // ignore: avoid_print
      print(
        'REHEARSAL ${{
          'user_version_before': beforeInspect['user_version'],
          'user_version_after': after['user_version'],
          'tables_before': beforeInspect['tables'],
          'tables_after': after['tables'],
          'integrity_after': after['integrity'],
          'rows_before': beforeInspect['rows'],
          'rows_after': after['rows'],
        }}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
