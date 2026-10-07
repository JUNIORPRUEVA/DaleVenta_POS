import 'package:flutter_riverpod/flutter_riverpod.dart';

final updateSignatureVerifierProvider = Provider<UpdateSignatureVerifier>((
  ref,
) {
  return const UpdateSignatureVerifier();
});

class UpdateSignatureVerificationException implements Exception {
  final String code;

  const UpdateSignatureVerificationException(this.code);

  @override
  String toString() => 'UpdateSignatureVerificationException($code)';
}

class UpdateSignatureVerifier {
  const UpdateSignatureVerifier();

  Future<void> verifyPackage({
    required String filePath,
    required String updateRootPath,
    String? expectedSha256,
    String? expectedPublisher,
    bool? allowUnsignedForUat,
  }) async {
    if (allowUnsignedForUat == true &&
        (expectedPublisher ?? '').trim().isEmpty) {
      return;
    }
    throw const UpdateSignatureVerificationException('UNSUPPORTED_PLATFORM');
  }
}
