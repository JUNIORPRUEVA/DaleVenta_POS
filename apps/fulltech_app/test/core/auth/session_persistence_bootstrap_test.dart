import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main injects durable auth launch snapshot before building app', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('final authLaunchSnapshotFuture = loadAuthLaunchSnapshot();'),
    );
    expect(
      source,
      contains('final authLaunchSnapshot = await authLaunchSnapshotFuture;'),
    );
    expect(
      source,
      contains(
        'authLaunchSnapshotProvider.overrideWithValue(authLaunchSnapshot)',
      ),
    );
    expect(source, contains('Future<void> _runStartupPrerequisitesInBackground() async {'));
    expect(source, contains('await prepareAppFirstFrame();'));
    expect(source, contains('await AppStorageScopeGuard.ensureCurrentScope();'));
    expect(source, contains('unawaited(_runStartupPrerequisitesInBackground());'));
  });

  test('storage scope migration never clears durable auth tokens', () {
    final source = File(
      'lib/core/startup/app_storage_scope_guard.dart',
    ).readAsStringSync();

    expect(source, contains('if (previous != null) {'));
    expect(source, isNot(contains('TokenStorage().clearTokens()')));
  });

  test(
    'refresh network failure is deferred without clearing persisted tokens',
    () {
      final source = File(
        'lib/core/auth/auth_repository.dart',
      ).readAsStringSync();

      expect(source, contains('enum _RefreshSessionResult'));
      expect(source, contains('_RefreshSessionResult.failed'));
      expect(
        source,
        contains('if (refreshed == _RefreshSessionResult.invalid)'),
      );
      expect(source, contains('await _safeClearTokens();'));
      expect(source, contains('_refreshFuture ??='));
    },
  );

  test('resume verification no longer forces refreshCurrentUser before UI use', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('verifySessionInBackground()'));
    expect(source, isNot(contains('refreshCurrentUser(silent: true)')));
  });

  test('fast launch snapshot can restore from secure storage fallback', () {
    final source = File('lib/core/auth/token_storage.dart').readAsStringSync();

    expect(source, contains("await _readSecure(_accessTokenKey)"));
    expect(source, contains("source: 'secure-launch'"));
    expect(source, contains('return TokenStorageLaunchSnapshot('));
  });
}
