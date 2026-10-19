import 'dart:convert';
import 'dart:io';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_repository.dart';
import 'package:daleventa_pos/core/app_update/update_downloader_io.dart';
import 'package:daleventa_pos/core/app_update/update_signature_verifier_io.dart';
import 'package:daleventa_pos/core/app_update/update_trust_policy.dart';
import 'package:daleventa_pos/core/app_update/update_verifier_io.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  if (Platform.environment['FULLPOS_PHASE17_HTTPS'] != 'true') {
    test('phase17 real HTTPS/native verifier laboratory', () {},
      skip: 'Opt-in requires the isolated candidate and ephemeral TLS fixture.');
    return;
  }
  final repo = Directory.current.parent.parent;
  final bank = Directory('${repo.path}/.uat/phase17-https');
  final package = File('${repo.path}/.uat/phase17-update-final-bank/packages/FullPOS-Phase17-Candidate-17002.exe');
  final helper = File('${repo.path}/.uat/phase17-update-final-bank/app/updater/FullposUpdater.exe');
  final results = <Map<String, Object?>>[];

  Future<void> scenario(String name, Future<void> Function(_Lab lab) body) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final serverContext = SecurityContext()
        ..useCertificateChain('${bank.path}/certificate.pem')
        ..usePrivateKey('${bank.path}/key.pem');
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      final certificate = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${bank.path}/certificate.pem');
      final dio = Dio(BaseOptions(baseUrl: 'https://127.0.0.1:${server.port}',
        connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10)))
        ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient(context: certificate));
      final root = Directory('${bank.path}/$name');
      expect(await root.exists(), isFalse, reason: 'Never overwrite bank evidence.');
      await root.create();
      final manifestRecord = jsonDecode(await File('${repo.path}/.uat/evidence/phase17-update-bank.json').readAsString()) as Map<String, dynamic>;
      final lab = _Lab(server, dio, root, package, manifestRecord['packageSha256'] as String);
      server.listen(lab.respond);
      try {
        await body(lab);
        results.add({'case': name, 'status': 'PASS', 'requests': lab.requests,
          'tlsTrust': 'Only ephemeral localhost certificate in this client context'});
      } finally {
        dio.close(force: true);
        await server.close(force: true);
      }
    }, _RealLocalHttp());
  }

  test('real HTTPS check/download/SHA succeeds but unsigned native package fails signature', () async {
    await scenario('signature-required', (lab) async {
      final manifest = await AppUpdateRepository(dio: lab.dio).checkForUpdate(_installed(14017));
      expect(manifest.buildNumber, 17002);
      final download = await lab.downloader.download(manifest);
      await const UpdateVerifier().verifySha256(filePath: download.partPath, expectedSha256: lab.sha);
      final decision = const UpdateTrustPolicy(allowUnsignedProduction: false,
        allowedHosts: {'127.0.0.1'}).evaluate(manifest: manifest, currentBuild: 14017,
          bytesDownloaded: download.bytesDownloaded);
      expect(decision.errorCode, 'UNSIGNED_PRODUCTION_DISABLED');
      await expectLater(UpdateSignatureVerifier(updaterExecutable: helper).verifyPackage(
        filePath: download.partPath, updateRootPath: download.updateRootPath,
        expectedSha256: lab.sha, expectedPublisher: 'FullPOS laboratory expected publisher',
        allowUnsignedForUat: false, allowUnsignedForProduction: false),
        throwsA(isA<UpdateSignatureVerificationException>().having((error) => error.code,
          'code', 'SIGNATURE_INVALID')));
      expect(await File(download.readyPath).exists(), isFalse);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('altered expected hash never becomes ready', () async {
    await scenario('wrong-hash', (lab) async {
      final download = await lab.downloader.download(lab.manifest());
      await expectLater(const UpdateVerifier().verifySha256(filePath: download.partPath,
        expectedSha256: '0' * 64), throwsA(isA<UpdateVerificationException>()));
      expect(await File(download.readyPath).exists(), isFalse);
    });
  });

  test('real incomplete HTTPS response removes the partial file', () async {
    await scenario('incomplete', (lab) async {
      lab.mode = 'incomplete';
      await expectLater(lab.downloader.download(lab.manifest()),
        throwsA(isA<UpdateDownloadException>().having((error) => error.code, 'code', 'SIZE_MISMATCH')));
      expect(lab.root.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });

  test('download does not follow a redirect to another host', () async {
    await scenario('redirect', (lab) async {
      lab.mode = 'redirect';
      await expectLater(lab.downloader.download(lab.manifest()),
        throwsA(isA<UpdateDownloadException>().having((error) => error.code, 'code', 'DOWNLOAD_HTTP_ERROR')));
      expect(lab.requests, 1);
    });
  });

  test('traversal filename is rejected before contacting HTTPS', () async {
    await scenario('traversal', (lab) async {
      await expectLater(lab.downloader.download(lab.manifest(fileName: '../outside.exe')),
        throwsA(isA<UpdateDownloadException>().having((error) => error.code, 'code', 'INVALID_FILE_NAME')));
      expect(lab.requests, 0);
    });
  });

  test('replayed manifest cannot offer the already installed build', () async {
    await scenario('replay', (lab) async {
      final manifest = await AppUpdateRepository(dio: lab.dio).checkForUpdate(_installed(17002));
      expect(manifest.updateAvailable, isFalse);
      expect(lab.requests, 1);
    });
    expect(results, hasLength(6));
    await File('${repo.path}/.uat/evidence/phase17-https-bank.json').writeAsString(
      jsonEncode({'status': 'PASS', 'cases': results, 'installed': false,
        'scope': 'Actual loopback TLS/repository/downloader/hash/native signature rejection; no UAC or publisher validation'}));
  });
}

InstalledReleaseInfo _installed(int build) => InstalledReleaseInfo(
  platform: ReleasePlatform.windows, currentVersion: '1.0.6', currentBuild: build);

class _RealLocalHttp extends HttpOverrides {}

class _Lab {
  _Lab(this.server, this.dio, this.root, this.package, this.sha);
  final HttpServer server;
  final Dio dio;
  final Directory root;
  final File package;
  final String sha;
  var mode = 'normal';
  var requests = 0;

  UpdateDownloader get downloader => UpdateDownloader(dio: dio, rootDirectory: root,
    streamIdleTimeout: const Duration(seconds: 5));

  UpdateManifest manifest({String fileName = 'candidate.exe'}) => UpdateManifest.fromJson({
    'updateAvailable': true, 'version': '1.0.6', 'buildNumber': 17002,
    'fileName': fileName, 'fileSize': package.lengthSync(), 'sha256': sha,
    'downloadUrl': 'https://127.0.0.1:${server.port}/candidate', 'signed': false,
    'publishedAt': '2026-10-14T00:00:00Z',
  });

  Future<void> respond(HttpRequest request) async {
    requests++;
    if (request.uri.path == ApiRoutes.releaseCheckUpdate) {
      final value = manifest();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'updateAvailable': true, 'version': value.version,
        'buildNumber': value.buildNumber, 'fileName': value.fileName, 'fileSize': value.fileSize,
        'sha256': value.sha256, 'downloadUrl': value.downloadUrl, 'signed': false,
        'publishedAt': '2026-10-14T00:00:00Z'}));
    } else if (mode == 'redirect') {
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader, 'https://example.invalid/not-contacted');
    } else {
      final size = mode == 'incomplete' ? 4096 : await package.length();
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = size;
      await request.response.addStream(package.openRead(0, size));
    }
    await request.response.close();
  }
}
