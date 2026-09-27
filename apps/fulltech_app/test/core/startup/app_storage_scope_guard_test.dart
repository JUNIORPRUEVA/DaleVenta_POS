import 'package:daleventa_pos/core/startup/app_storage_scope_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial storage scope does not clear a pre-seeded auth session', () {
    final shouldClear = AppStorageScopeGuard.shouldClearAuthSessionForScope(
      previous: null,
      current: 'scope-v1|web|web|https://example.test/api',
    );

    expect(shouldClear, isFalse);
  });

  test('changed storage scope clears stale auth session', () {
    final shouldClear = AppStorageScopeGuard.shouldClearAuthSessionForScope(
      previous: 'scope-v1|web|web|https://old.example.test/api',
      current: 'scope-v1|web|web|https://new.example.test/api',
    );

    expect(shouldClear, isTrue);
  });
}
