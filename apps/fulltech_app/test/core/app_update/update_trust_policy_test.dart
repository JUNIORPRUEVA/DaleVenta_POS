import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/update_trust_policy.dart';

void main() {
  const allowedHost =
      '612fe68377329d5c3fbc84056a28aa64.r2.cloudflarestorage.com';

  UpdateTrustPolicy policy({bool allowUnsigned = true}) => UpdateTrustPolicy(
    allowUnsignedProduction: allowUnsigned,
    allowedHosts: {allowedHost},
  );

  UpdateManifest manifest({
    int build = 137,
    int size = 100,
    String sha = 'a',
    String scheme = 'https',
    String host = allowedHost,
    bool signed = false,
    String channel = UpdateManifest.stableChannel,
    String status = UpdateManifest.publishedStatus,
  }) {
    return UpdateManifest(
      updateAvailable: true,
      version: '1.0.6',
      buildNumber: build,
      fileName: 'FullPOS-Setup-1.0.6-$build.exe',
      fileSize: size,
      sha256: sha * 64,
      downloadUrl: '$scheme://$host/releases/windows/stable/setup.exe',
      signed: signed,
      channel: channel,
      status: status,
      publishedAt: DateTime.utc(2026, 10, 11),
    );
  }

  test('unsigned production disabled rejects unsigned packages', () {
    final decision = policy(
      allowUnsigned: false,
    ).evaluate(manifest: manifest(), currentBuild: 136, bytesDownloaded: 100);

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'UNSIGNED_PRODUCTION_DISABLED');
  });

  test('unsigned production enabled rejects wrong size', () {
    final decision = policy().evaluate(
      manifest: manifest(),
      currentBuild: 136,
      bytesDownloaded: 99,
    );

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'SIZE_MISMATCH');
  });

  test('unsigned production enabled rejects non-HTTPS URLs', () {
    final decision = policy().evaluate(
      manifest: manifest(scheme: 'http'),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'INVALID_DOWNLOAD_URL');
  });

  test('unsigned production enabled rejects wrong hosts', () {
    final decision = policy().evaluate(
      manifest: manifest(host: 'example.com'),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'DOWNLOAD_HOST_NOT_ALLOWED');
  });

  test('unsigned production enabled rejects DRAFT releases', () {
    final decision = policy().evaluate(
      manifest: manifest(status: 'draft'),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'RELEASE_NOT_STABLE_PUBLISHED');
  });

  test('unsigned production enabled rejects wrong channel', () {
    final decision = policy().evaluate(
      manifest: manifest(channel: 'beta'),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(decision.accepted, isFalse);
    expect(decision.errorCode, 'RELEASE_NOT_STABLE_PUBLISHED');
  });

  test('unsigned production enabled rejects lower or equal build', () {
    final equal = policy().evaluate(
      manifest: manifest(build: 136),
      currentBuild: 136,
      bytesDownloaded: 100,
    );
    final lower = policy().evaluate(
      manifest: manifest(build: 135),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(equal.accepted, isFalse);
    expect(equal.errorCode, 'BUILD_NOT_NEWER');
    expect(lower.accepted, isFalse);
    expect(lower.errorCode, 'BUILD_NOT_NEWER');
  });

  test(
    'unsigned production enabled accepts valid stable published package',
    () {
      final decision = policy().evaluate(
        manifest: manifest(),
        currentBuild: 136,
        bytesDownloaded: 100,
      );

      expect(decision.accepted, isTrue);
      expect(decision.signatureStatus, 'NotSigned');
      expect(decision.acceptedBy, 'ProductionUnsignedPolicy');
    },
  );

  test('signed valid release follows Authenticode policy', () {
    final decision = policy(allowUnsigned: false).evaluate(
      manifest: manifest(signed: true),
      currentBuild: 136,
      bytesDownloaded: 100,
    );

    expect(decision.accepted, isTrue);
    expect(decision.signatureStatus, 'Signed');
    expect(decision.acceptedBy, 'AuthenticodePolicy');
  });
}
