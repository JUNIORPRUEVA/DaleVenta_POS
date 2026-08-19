import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main injects durable auth launch snapshot before building app', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('final authLaunchSnapshot = await loadAuthLaunchSnapshot();'),
    );
    expect(
      source,
      contains(
        'authLaunchSnapshotProvider.overrideWithValue(authLaunchSnapshot)',
      ),
    );
  });

  test('storage scope initialization does not clear an existing session', () {
    final source = File(
      'lib/core/startup/app_storage_scope_guard.dart',
    ).readAsStringSync();

    expect(source, contains('if (previous != null) {'));
    expect(source, contains('await TokenStorage().clearTokens();'));
  });

  test('fast launch snapshot can restore from secure storage fallback', () {
    final source = File('lib/core/auth/token_storage.dart').readAsStringSync();

    expect(source, contains("await _readSecure(_accessTokenKey)"));
    expect(source, contains("source: 'secure-launch'"));
    expect(source, contains('return TokenStorageLaunchSnapshot('));
  });
}
