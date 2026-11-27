import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/update_downloader_io.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// El descargador es API Win32: `update_downloader_io.dart` rechaza cualquier
// otro sistema con UNSUPPORTED_PLATFORM. La prueba necesita Windows y se omite
// (con motivo explícito) en el resto de runners; el job `windows-updater` de CI
// la ejecuta de verdad en windows-latest.
final bool _notWindows = !Platform.isWindows;
const String _windowsOnlyReason = 'Requiere Windows: descarga Win32';

void main() {
  test(
    'completed partial survives restart; corrupt partial is fetched again',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fullpos-completed-part-',
      );
      addTearDown(() => root.delete(recursive: true));
      final bytes = List<int>.generate(10, (i) => i);
      final manifest = UpdateManifest(
        updateAvailable: true,
        buildNumber: 135,
        fileName: 'complete.exe',
        fileSize: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        downloadUrl: 'https://localhost/candidate',
      );
      final part = File('${root.path}/135/complete.exe.part');
      await part.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
          requests++;
          return ResponseBody.fromBytes(bytes, 200);
        });
      addTearDown(() => dio.close(force: true));
      final downloader = UpdateDownloader(dio: dio, rootDirectory: root);
      final recovered = await downloader.download(manifest);
      expect(requests, 0);
      expect(recovered.bytesDownloaded, bytes.length);
      await part.writeAsBytes(List.filled(10, 99), flush: true);
      await downloader.download(manifest);
      expect(requests, 1);
      expect(await part.readAsBytes(), bytes);
    },
    skip: _notWindows ? _windowsOnlyReason : null,
  );
  test(
    'oversized stream stops before writing beyond declared package size',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fullpos-update-size-',
      );
      addTearDown(() => root.delete(recursive: true));
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) async => ResponseBody(
            Stream.fromIterable([
              Uint8List.fromList(List.filled(6, 1)),
              Uint8List.fromList(List.filled(6, 2)),
            ]),
            200,
          ),
        );
      addTearDown(() => dio.close(force: true));
      var maximumProgress = 0;
      await expectLater(
        UpdateDownloader(dio: dio, rootDirectory: root).download(
          _manifest(),
          onProgress: (value) => maximumProgress = value.bytesDownloaded,
        ),
        throwsA(
          isA<UpdateDownloadException>().having(
            (value) => value.code,
            'code',
            'SIZE_MISMATCH',
          ),
        ),
      );
      expect(maximumProgress, 6);
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    },
    skip: _notWindows ? _windowsOnlyReason : null,
  );

  test(
    'prepared file must exist with exact size and stay inside its build',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fullpos-prepared-path-',
      );
      addTearDown(() => root.delete(recursive: true));
      final downloader = UpdateDownloader(rootDirectory: root);
      final state = PersistedUpdateState.initial().copyWith(
        targetBuild: 135,
        artifactRelativePath: '135/setup.exe.ready',
        fileSizeExpected: 10,
      );
      await expectLater(
        downloader.resolvePreparedArtifact(state),
        throwsA(isA<FileSystemException>()),
      );
      final file = File('${root.path}/135/setup.exe.ready');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.filled(9, 1));
      await expectLater(
        downloader.resolvePreparedArtifact(state),
        throwsA(isA<UpdateDownloadException>()),
      );
      await file.writeAsBytes(List.filled(10, 1));
      expect(
        await downloader.resolvePreparedArtifact(state),
        await file.resolveSymbolicLinks(),
      );
      await expectLater(
        downloader.resolvePreparedArtifact(
          state.copyWith(artifactRelativePath: '../setup.exe.ready'),
        ),
        throwsA(isA<UpdateDownloadException>()),
      );
    },
    skip: _notWindows ? _windowsOnlyReason : null,
  );

  test(
    'stalled partial download fails instead of staying in progress',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fullpos-update-test-',
      );
      final controller = StreamController<Uint8List>();
      addTearDown(() async {
        await controller.close();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((_) async {
          scheduleMicrotask(() {
            controller.add(Uint8List.fromList(<int>[1, 2, 3]));
          });
          return ResponseBody(
            controller.stream,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/octet-stream'],
              Headers.contentLengthHeader: ['10'],
            },
          );
        });
      final downloader = UpdateDownloader(
        dio: dio,
        rootDirectory: root,
        streamIdleTimeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        downloader.download(_manifest()),
        throwsA(
          isA<UpdateDownloadException>().having(
            (error) => error.code,
            'code',
            'DOWNLOAD_TIMEOUT',
          ),
        ),
      );

      final buildDirectory = Directory(
        '${root.path}${Platform.pathSeparator}135',
      );
      final leftovers = buildDirectory.existsSync()
          ? buildDirectory.listSync(recursive: true)
          : const <FileSystemEntity>[];
      expect(leftovers.whereType<File>().map((file) => file.path), isEmpty);
    },
    skip: _notWindows ? _windowsOnlyReason : null,
  );
}

UpdateManifest _manifest() {
  return UpdateManifest.fromJson({
    'updateAvailable': true,
    'version': '1.0.6',
    'buildNumber': 135,
    'fileName': 'FullPOS-UAT-Setup-1.0.6-135.exe',
    'fileSize': 10,
    'sha256':
        '087ab069d7bc3371fb4e434ccc9498d1840de3d17fd1e45ae9d619fbf98a8146',
    'downloadUrl': 'https://localhost:9443/artifacts/setup.exe',
    'publishedAt': '2026-10-11T00:00:00.000Z',
  });
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
