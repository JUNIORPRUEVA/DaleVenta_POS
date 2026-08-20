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
    'authenticated verification cannot erase a resolved tenant for the same user',
    () {
      final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

      expect(
        source,
        contains(
          'UserModel? _preserveCurrentTenantIdentity(UserModel? verifiedUser)',
        ),
      );
      expect(
        source,
        contains('if (currentUser!.id.trim() != verifiedUser.id.trim()) return verifiedUser;'),
      );
      expect(source, contains("merged['companyId'] = currentUser.companyId;"));
      expect(
        source,
        contains('final user = _preserveCurrentTenantIdentity(rawUser);'),
      );
      expect(
        source,
        contains('restoringSession: !tenantIdentityResolved,'),
      );
    },
  );

  test(
    'preserved tenant identity is written back after incomplete me response',
    () {
      final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();

      expect(source, contains('final tenantIdentityPreserved ='));
      expect(
        source,
        contains('if (tenantIdentityPreserved && user != null) {'),
      );
      expect(
        source,
        contains('await ref.read(tokenStorageProvider).saveUserSnapshot(user);'),
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

  test('invalid verification still logs out instead of preserving tenant state', () {
    final source = File('lib/core/auth/auth_provider.dart').readAsStringSync();
    final invalidCase = source.indexOf('case SessionVerificationStatus.invalid:');
    final deferredCase = source.indexOf('case SessionVerificationStatus.deferred:');

    expect(invalidCase, greaterThanOrEqualTo(0));
    expect(deferredCase, greaterThan(invalidCase));
    final block = source.substring(invalidCase, deferredCase);
    expect(block, contains('isAuthenticated: false,'));
    expect(block, contains('user: null,'));
    expect(block, contains('hasSessionHint: false,'));
  });

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
