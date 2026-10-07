import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_models.dart';

final updateDownloaderProvider = Provider<UpdateDownloader>((ref) {
  return const UpdateDownloader();
});

class UpdateDownloadException implements Exception {
  final String code;

  const UpdateDownloadException(this.code);
}

class UpdateDownloadResult {
  final String partPath;
  final String readyPath;
  final String artifactRelativePath;
  final int bytesDownloaded;
  final int fileSizeExpected;

  const UpdateDownloadResult({
    required this.partPath,
    required this.readyPath,
    required this.artifactRelativePath,
    required this.bytesDownloaded,
    required this.fileSizeExpected,
  });
}

class UpdateDownloader {
  const UpdateDownloader();

  Future<UpdateDownloadResult> download(
    UpdateManifest manifest, {
    void Function(UpdateDownloadProgress progress)? onProgress,
  }) async {
    throw const UpdateDownloadException('UNSUPPORTED_PLATFORM');
  }

  Future<void> promoteToReady(UpdateDownloadResult result) async {
    throw const UpdateDownloadException('UNSUPPORTED_PLATFORM');
  }

  Future<void> discardBuild(int buildNumber) async {}
}
