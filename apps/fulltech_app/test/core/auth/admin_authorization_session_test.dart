import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daleventa_pos/core/auth/admin_authorization_session.dart';

void main() {
  test('action authorization is single use', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeAction(const Duration(minutes: 10), 'token-action');

    expect(controller.tokenForRequest('/api/products/1'), 'token-action');
    controller.consumeActionAuthorization();
    expect(controller.tokenForRequest('/api/products/1'), isNull);
  });

  test('route authorization only matches the authorized route path', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 10),
      'token-route',
      '/users/abc/permissions',
    );

    expect(controller.isAuthorizedForRoute('/users/abc/permissions'), isTrue);
    expect(controller.isAuthorizedForRoute('/users/abc/permissions?x=1'), isTrue);
    expect(controller.isAuthorizedForRoute('/users'), isFalse);

    controller.clearIfInvalidForLocation('/users');
    expect(controller.isAuthorizedForRoute('/users/abc/permissions'), isFalse);
  });
}
