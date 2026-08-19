import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deferred verification keeps restored auth state instead of logging out', () {
    final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

    expect(source, contains('final user = result.user ?? state.user;'));
    expect(source, contains('final canKeepSession = user != null || state.hasSessionHint;'));
    expect(source, contains('isAuthenticated: true,'));
    expect(source, isNot(contains('case SessionVerificationStatus.deferred:\n          if (result.user == null)')));
  });

  test('silent refresh now accepts cached fallback instead of forcing logout paths', () {
    final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

    expect(source, contains('getMeOrNull(silent: silent, allowCachedFallback: true)'));
    expect(source, contains('Future<void>? _verifySessionFuture;'));
    expect(source, contains('verifySessionInBackground()'));
  });
}
