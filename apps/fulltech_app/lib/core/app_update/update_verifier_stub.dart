import 'package:flutter_riverpod/flutter_riverpod.dart';

final updateVerifierProvider = Provider<UpdateVerifier>((ref) {
  return const UpdateVerifier();
});

class UpdateVerificationException implements Exception {
  final String code;

  const UpdateVerificationException(this.code);
}

class UpdateVerifier {
  const UpdateVerifier();

  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
  }) async {
    throw const UpdateVerificationException('UNSUPPORTED_PLATFORM');
  }
}
