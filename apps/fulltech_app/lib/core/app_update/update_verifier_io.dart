import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final updateVerifierProvider = Provider<UpdateVerifier>((ref) {
  return const UpdateVerifier();
});

class UpdateVerificationException implements Exception {
  final String code;

  const UpdateVerificationException(this.code);

  @override
  String toString() => 'UpdateVerificationException($code)';
}

class UpdateVerifier {
  const UpdateVerifier();

  Future<void> verifySha256({
    required String filePath,
    required String expectedSha256,
  }) async {
    final expected = expectedSha256.trim().toLowerCase();
    final digest = await sha256.bind(File(filePath).openRead()).first;
    final actual = digest.toString().toLowerCase();
    if (actual != expected) {
      throw const UpdateVerificationException('HASH_MISMATCH');
    }
  }
}
