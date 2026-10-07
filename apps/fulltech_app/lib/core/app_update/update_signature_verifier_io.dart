import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../api/env.dart';

final updateSignatureVerifierProvider = Provider<UpdateSignatureVerifier>((
  ref,
) {
  return UpdateSignatureVerifier();
});

class UpdateSignatureVerificationException implements Exception {
  final String code;
  final Object? cause;

  const UpdateSignatureVerificationException(this.code, [this.cause]);

  @override
  String toString() => 'UpdateSignatureVerificationException($code)';
}

class UpdateSignatureVerifier {
  UpdateSignatureVerifier({File? updaterExecutable})
    : _updaterExecutable = updaterExecutable;

  final File? _updaterExecutable;

  Future<void> verifyPackage({
    required String filePath,
    required String updateRootPath,
    String? expectedSha256,
    String? expectedPublisher,
    bool? allowUnsignedForUat,
  }) async {
    if (kIsWeb || !Platform.isWindows) {
      throw const UpdateSignatureVerificationException('UNSUPPORTED_PLATFORM');
    }

    final publisher = (expectedPublisher ?? Env.expectedUpdatePublisher).trim();
    final allowUnsigned = allowUnsignedForUat ?? Env.allowUnsignedUpdatesForUat;
    if (allowUnsigned && publisher.isEmpty) return;
    if (publisher.isEmpty) {
      throw const UpdateSignatureVerificationException(
        'EXPECTED_PUBLISHER_MISSING',
      );
    }

    final updater = _updaterExecutable ?? _resolveUpdaterExecutable();
    if (!await updater.exists()) {
      throw const UpdateSignatureVerificationException('UPDATER_NOT_FOUND');
    }

    final result = await Process.run(updater.path, [
      '--verify-only',
      '--package',
      filePath,
      '--update-root',
      updateRootPath,
      '--expected-sha256',
      (expectedSha256 ?? '').trim().toLowerCase(),
      '--expected-publisher',
      publisher,
      if (allowUnsigned) '--allow-unsigned',
    ]);

    if (result.exitCode != 0) {
      final code = _extractResultCode(result.stdout) ?? 'SIGNATURE_INVALID';
      throw UpdateSignatureVerificationException(code, result.stderr);
    }
  }

  File _resolveUpdaterExecutable() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final installedRoot = p.dirname(exeDir);
    final candidates = <String>[
      p.join(installedRoot, 'updater', 'FullposUpdater.exe'),
      p.join(exeDir, 'updater', 'FullposUpdater.exe'),
    ];
    return File(
      candidates.firstWhere(
        (path) => File(path).existsSync(),
        orElse: () => candidates.first,
      ),
    );
  }

  String? _extractResultCode(Object? output) {
    final text = output?.toString() ?? '';
    final match = RegExp(r'RESULT=([A-Z0-9_]+)').firstMatch(text);
    return match?.group(1);
  }
}
