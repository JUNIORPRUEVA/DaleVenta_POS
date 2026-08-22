import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await OfflineStore.instance.clearAll();
    await LocalJsonCache().remove('company_settings_cache_v1');
    await LocalJsonCache().remove('company_settings_cache_v1:company-a');
  });

  test(
    'getSettings returns empty settings when API response is invalid',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) async => ResponseBody.fromString(
            '[]',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
      final repository = CompanySettingsRepository(
        dio,
        SyncQueueService(OfflineStore.instance),
      );

      final settings = await repository.getSettings();

      expect(settings.companyName, isEmpty);
      expect(settings.hasAdminAuthorizationPin, isFalse);
    },
  );

  test(
    'getSettings keeps cached settings when background refresh fails',
    () async {
      await LocalJsonCache().writeMap('company_settings_cache_v1', {
        'companyName': 'FullPOS Cloud',
      });
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/settings'),
            type: DioExceptionType.connectionError,
            error: 'sin conexion',
          );
        });
      final repository = CompanySettingsRepository(
        dio,
        SyncQueueService(OfflineStore.instance),
      );
      final unhandledErrors = <Object>[];

      final settings = await runZonedGuarded<Future<dynamic>>(() async {
        final loaded = await repository.getSettings();
        await Future<void>.delayed(Duration.zero);
        return loaded;
      }, (error, _) => unhandledErrors.add(error));

      expect(settings.companyName, 'FullPOS Cloud');
      expect(unhandledErrors, isEmpty);
    },
  );

  test('scoped settings do not inherit stale global company cache', () async {
    await LocalJsonCache().writeMap('company_settings_cache_v1', {
      'companyName': 'Nombre Viejo',
    });
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/settings'),
          type: DioExceptionType.connectionError,
          error: 'sin conexion',
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
    );

    final settings = await repository.getSettings();

    expect(settings.companyName, isEmpty);
  });

  test('non-admin settings saves never call PATCH /settings', () async {
    var patchCount = 0;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method.toUpperCase() == 'PATCH') patchCount++;
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
      canWriteSettings: false,
    );

    await expectLater(
      repository.saveSettingsOrQueue(
        CompanySettings.empty().copyWith(companyName: 'Nombre Viejo'),
      ),
      throwsA(isA<Exception>()),
    );
    expect(patchCount, 0);
  });

  test(
    'tax and NCF false values survive save payload and fresh reload',
    () async {
      var serverSettings = CompanySettings.empty().copyWith(
        companyName: 'FullPOS Cloud',
        taxEnabled: true,
        pricesIncludeTax: true,
        ncfEnabled: true,
        defaultTaxRate: 0.18,
      );
      Map<String, dynamic>? patchPayload;
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.method.toUpperCase() == 'PATCH') {
            patchPayload = (options.data as Map).cast<String, dynamic>();
            serverSettings = CompanySettings.fromMap({
              ...serverSettings.toMap(),
              ...patchPayload!,
            });
            return ResponseBody.fromString(
              jsonEncode(serverSettings.toMap()),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode(serverSettings.toMap()),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      final repository = CompanySettingsRepository(
        dio,
        SyncQueueService(OfflineStore.instance),
        cacheScope: 'company-a',
      );

      await repository.saveSettingsOrQueue(
        serverSettings.copyWith(
          taxEnabled: false,
          pricesIncludeTax: false,
          ncfEnabled: false,
        ),
      );
      final reloaded = await repository.getSettingsRemoteAndCache();

      expect(patchPayload, containsPair('taxEnabled', false));
      expect(patchPayload, containsPair('pricesIncludeTax', false));
      expect(patchPayload, containsPair('ncfEnabled', false));
      // El nombre de empresa es dato maestro: el guardado genérico NO lo envía.
      expect(patchPayload!.containsKey('companyName'), isFalse);
      expect(reloaded.taxEnabled, isFalse);
      expect(reloaded.pricesIncludeTax, isFalse);
      expect(reloaded.ncfEnabled, isFalse);
    },
  );

  test(
    'non-admin sync handler discards stale settings.save without PATCH',
    () async {
      var patchCount = 0;
      final syncQueue = SyncQueueService(
        OfflineStore.instance,
        scopeResolver: () async =>
            const OfflineSyncScope(companyId: 'company-a'),
      );
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.method.toUpperCase() == 'PATCH') patchCount++;
          return ResponseBody.fromString(
            '{}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      final repository = CompanySettingsRepository(
        dio,
        syncQueue,
        cacheScope: 'company-a',
        canWriteSettings: false,
      );
      repository.registerSyncHandlers();
      await syncQueue.enqueue(
        id: 'settings.save:legacy',
        type: 'settings.save',
        scope: 'global',
        companyId: 'company-a',
        payload: {
          'settings': CompanySettings.empty()
              .copyWith(companyName: 'Nombre Viejo')
              .toMap(),
        },
      );

      await syncQueue.processPending();
      await _waitForPendingActionsToDrain();

      expect(patchCount, 0);
      expect((await OfflineStore.instance.pendingActionStats())['pending'], 0);
    },
  );

  test('generic settings save never sends companyName', () async {
    Map<String, dynamic>? patchPayload;
    String? patchPath;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method.toUpperCase() == 'PATCH') {
          patchPath = options.path;
          patchPayload = (options.data as Map).cast<String, dynamic>();
        }
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
    );

    await repository.saveSettingsOrQueue(
      CompanySettings.empty().copyWith(
        companyName: 'DaleVenta POS',
        phone: '809-555-0101',
      ),
    );

    expect(patchPath, '/settings');
    expect(patchPayload, isNotNull);
    expect(patchPayload!.containsKey('companyName'), isFalse);
    expect(patchPayload, containsPair('phone', '809-555-0101'));
  });

  test('legacy settings.save replay strips companyName and keeps other fields',
      () async {
    final paths = <String>[];
    final payloads = <Map<String, dynamic>>[];
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method.toUpperCase() == 'PATCH') {
          paths.add(options.path);
          payloads.add((options.data as Map).cast<String, dynamic>());
        }
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final syncQueue = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: 'company-a'),
    );
    final repository = CompanySettingsRepository(
      dio,
      syncQueue,
      cacheScope: 'company-a',
    );
    repository.registerSyncHandlers();

    // Operación LEGACY ya persistida en el dispositivo (versión anterior):
    // incluye companyName = 'DaleVenta POS'. Al reproducirse NO debe
    // modificar Company.name, pero sí debe persistir el resto de campos.
    await syncQueue.enqueue(
      id: 'settings.save:legacy',
      type: 'settings.save',
      scope: 'company-a',
      companyId: 'company-a',
      payload: {
        'settings': CompanySettings.empty()
            .copyWith(companyName: 'DaleVenta POS', phone: '809-555-0101')
            .toMap(),
      },
    );

    await syncQueue.processPending();
    await _waitForPendingActionsToDrain();

    expect(paths.single, '/settings');
    expect(payloads.single.containsKey('companyName'), isFalse);
    expect(payloads.single, containsPair('phone', '809-555-0101'));
    expect((await OfflineStore.instance.pendingActionStats())['pending'], 0);
  });

  test('saveCompanyNameOrQueue uses the dedicated /settings/company-name endpoint',
      () async {
    Map<String, dynamic>? namePayload;
    String? namePath;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method.toUpperCase() == 'PATCH') {
          namePath = options.path;
          namePayload = (options.data as Map).cast<String, dynamic>();
        }
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
    );

    final queued = await repository.saveCompanyNameOrQueue('FULLTECH, SRL');

    expect(queued, isFalse);
    expect(namePath, '/settings/company-name');
    expect(namePayload, containsPair('companyName', 'FULLTECH, SRL'));
  });

  test('offline rename queues settings.save_name and replays it on reconnect',
      () async {
    var online = false;
    final paths = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        paths.add(options.path);
        if (!online) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'offline',
          );
        }
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final syncQueue = SyncQueueService(
      OfflineStore.instance,
      scopeResolver: () async =>
          const OfflineSyncScope(companyId: 'company-a'),
    );
    final repository = CompanySettingsRepository(
      dio,
      syncQueue,
      cacheScope: 'company-a',
    );
    repository.registerSyncHandlers();

    // Intento de rename estando offline → se encola.
    final queued = await repository.saveCompanyNameOrQueue('FULLTECH, SRL');
    expect(queued, isTrue);

    // Reconexión: procesa la cola.
    online = true;
    await syncQueue.processPending();
    await _waitForPendingActionsToDrain();

    expect(paths, contains('/settings/company-name'));
    expect((await OfflineStore.instance.pendingActionStats())['pending'], 0);
  });

  test('saveCompanyNameOrQueue rejects empty names', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
    );

    await expectLater(
      repository.saveCompanyNameOrQueue('   '),
      throwsA(isA<Exception>()),
    );
  });

  test('non-admin rename is rejected without PATCH', () async {
    var patchCount = 0;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method.toUpperCase() == 'PATCH') patchCount++;
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CompanySettingsRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      cacheScope: 'company-a',
      canWriteSettings: false,
    );

    await expectLater(
      repository.saveCompanyNameOrQueue('FULLTECH, SRL'),
      throwsA(isA<Exception>()),
    );
    expect(patchCount, 0);
  });
}

Future<void> _waitForPendingActionsToDrain() async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final stats = await OfflineStore.instance.pendingActionStats();
    final remaining =
        (stats['pending'] ?? 0) +
        (stats['syncing'] ?? 0) +
        (stats['error'] ?? 0);
    if (remaining == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
