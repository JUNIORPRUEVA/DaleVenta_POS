import 'package:path/path.dart' as p;

import 'app_update_models.dart';

class UpdateTrustPolicyDecision {
  final bool accepted;
  final String signatureStatus;
  final String acceptedBy;
  final String? errorCode;

  const UpdateTrustPolicyDecision.accepted({
    required this.signatureStatus,
    required this.acceptedBy,
  }) : accepted = true,
       errorCode = null;

  const UpdateTrustPolicyDecision.rejected(String code)
    : accepted = false,
      signatureStatus = 'Rejected',
      acceptedBy = 'None',
      errorCode = code;
}

class UpdateTrustPolicy {
  const UpdateTrustPolicy({
    required this.allowUnsignedProduction,
    required this.allowedHosts,
  });

  final bool allowUnsignedProduction;
  final Set<String> allowedHosts;

  UpdateTrustPolicyDecision evaluate({
    required UpdateManifest manifest,
    required int currentBuild,
    required int bytesDownloaded,
  }) {
    if (!manifest.isNewerThan(currentBuild)) {
      return const UpdateTrustPolicyDecision.rejected('BUILD_NOT_NEWER');
    }
    if (!manifest.isStablePublished) {
      return const UpdateTrustPolicyDecision.rejected(
        'RELEASE_NOT_STABLE_PUBLISHED',
      );
    }
    if (bytesDownloaded != manifest.fileSize) {
      return const UpdateTrustPolicyDecision.rejected('SIZE_MISMATCH');
    }

    final uri = Uri.tryParse((manifest.downloadUrl ?? '').trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') {
      return const UpdateTrustPolicyDecision.rejected('INVALID_DOWNLOAD_URL');
    }

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || !allowedHosts.contains(host)) {
      return const UpdateTrustPolicyDecision.rejected(
        'DOWNLOAD_HOST_NOT_ALLOWED',
      );
    }

    final fileName = (manifest.fileName ?? '').trim();
    if (fileName.isEmpty ||
        fileName.contains('/') ||
        fileName.contains(r'\') ||
        fileName.contains('..') ||
        p.basename(fileName) != fileName) {
      return const UpdateTrustPolicyDecision.rejected('INVALID_FILE_NAME');
    }

    if (manifest.signed) {
      return const UpdateTrustPolicyDecision.accepted(
        signatureStatus: 'Signed',
        acceptedBy: 'AuthenticodePolicy',
      );
    }

    if (!allowUnsignedProduction) {
      return const UpdateTrustPolicyDecision.rejected(
        'UNSIGNED_PRODUCTION_DISABLED',
      );
    }

    return const UpdateTrustPolicyDecision.accepted(
      signatureStatus: 'NotSigned',
      acceptedBy: 'ProductionUnsignedPolicy',
    );
  }
}
