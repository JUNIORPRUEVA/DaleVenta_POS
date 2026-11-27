import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';
import 'app_update_controller_test.dart' as fixtures;
import 'update_recovery_regression_test.dart' as regression;

void main() {
  for (final body in <Map<String, dynamic>>[
    {},
    {'message': 'temporarily unavailable'},
    {'updateAvailable': null},
    {'updateAvailable': 'false'},
    {'updateAvailable': 0},
  ]) {
    test(
      'invalid successful response ${jsonEncode(body)} preserves prepared package',
      () async {
        final downloader = fixtures.FakeUpdateDownloader();
        final repo = ContractRepository(body);
        addTearDown(repo.dio.close);
        final app = regression.controller(
          regression.prepared(),
          downloader,
          repository: repo,
        );
        await app.checkNow(force: true);
        expect(app.state.phase, AppUpdatePhase.readyToInstall);
        expect(app.state.persisted.targetBuild, 138);
        expect(app.state.persisted.lastUpdateResult, 'CHECK_ERROR');
        expect(downloader.discardedBuilds, isEmpty);
        expect(downloader.downloads, 0);
      },
    );
  }
  test('explicit boolean false remains a compatible no-update response', () {
    expect(
      UpdateManifest.fromJson({'updateAvailable': false}).updateAvailable,
      isFalse,
    );
  });
}

class ContractRepository extends fixtures.FakeAppUpdateRepository {
  ContractRepository(Map<String, dynamic> body)
    : dio = Dio(BaseOptions(baseUrl: 'https://127.0.0.1'))
        ..httpClientAdapter = ContractAdapter(body),
      super(
        installedRelease: const InstalledReleaseInfo(
          platform: ReleasePlatform.windows,
          currentVersion: '1.0.6',
          currentBuild: 137,
        ),
      );
  final Dio dio;
  @override
  Future<UpdateManifest> checkForUpdate(InstalledReleaseInfo info) =>
      AppUpdateRepository(dio: dio).checkForUpdate(info);
}

class ContractAdapter implements HttpClientAdapter {
  ContractAdapter(this.body);
  final Map<String, dynamic> body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}
