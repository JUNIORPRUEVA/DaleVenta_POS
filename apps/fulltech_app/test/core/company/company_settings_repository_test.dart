import 'dart:async';
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
    'non-admin sync handler discards stale settings.save without PATCH',
    () async {
      var patchCount = 0;
      final syncQueue = SyncQueueService(OfflineStore.instance);
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
