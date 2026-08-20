import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deferred verification keeps restored auth state instead of logging out', () {
    final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

    expect(source, contains('final user = result.user ?? state.user;'));
    expect(
      source,
      contains('final canKeepSession = user != null || state.hasSessionHint;'),
    );
    expect(source, contains('isAuthenticated: true,'));
    expect(
      source,
      isNot(
        contains(
          'case SessionVerificationStatus.deferred:\n          if (result.user == null)',
        ),
      ),
    );
  });

  test(
    'deferred verification keeps tenant-incomplete identity in restoring state',
    () {
      final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

      expect(source, contains('bool _hasResolvedTenantIdentity(UserModel? user)'));
      expect(
        source,
        contains("(user.companyId?.trim().isNotEmpty ?? false)"),
      );
      expect(
        source,
        contains(
          'final tenantIdentityResolved = _hasResolvedTenantIdentity(user);',
        ),
      );
      expect(
        source,
        contains('restoringSession: !tenantIdentityResolved,'),
      );
    },
  );

  test(
    'unexpected verification errors keep a session hint restoring until tenant resolves',
    () {
      final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

      expect(source, contains('final canKeepSession = state.hasSessionHint;'));
      expect(
        source,
        contains(
          'final tenantIdentityResolved = _hasResolvedTenantIdentity(state.user);',
        ),
      );
      expect(
        source,
        contains(
          'restoringSession: canKeepSession && !tenantIdentityResolved,',
        ),
      );
    },
  );

  test(
    'authoritative authenticated verification still finishes restoration',
    () {
      final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();
      final authenticatedCase = source.indexOf(
        'case SessionVerificationStatus.authenticated:',
      );
      final invalidCase = source.indexOf(
        'case SessionVerificationStatus.invalid:',
      );

      expect(authenticatedCase, greaterThanOrEqualTo(0));
      expect(invalidCase, greaterThan(authenticatedCase));
      final block = source.substring(authenticatedCase, invalidCase);
      expect(block, contains('restoringSession: false,'));
    },
  );

  test('silent refresh now accepts cached fallback instead of forcing logout paths', () {
    final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

    expect(
      source,
      contains('getMeOrNull(silent: silent, allowCachedFallback: true)'),
    );
    expect(source, contains('Future<void>? _verifySessionFuture;'));
    expect(source, contains('verifySessionInBackground()'));
  });
}
