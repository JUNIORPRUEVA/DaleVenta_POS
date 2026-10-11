import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/update_downloader_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
