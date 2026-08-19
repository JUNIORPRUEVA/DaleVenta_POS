import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daleventa_pos/core/auth/admin_authorization_session.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';

class _TestAuthController extends AuthController {
  _TestAuthController(
    super.ref, {
    required String userId,
    required String companyId,
  }) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: userId,
        email: '$userId@example.com',
        nombreCompleto: 'Usuario $userId',
        telefono: '',
        role: 'CAJERO',
        companyId: companyId,
      ),
    );
  }
}

ProviderContainer _container({
  String userId = 'employee-a',
  String companyId = 'company-a',
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => _TestAuthController(
          ref,
          userId: userId,
          companyId: companyId,
        ),
      ),
    ],
  );
}

void main() {
  test('action authorization is single use', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeAction(const Duration(minutes: 10), 'token-action');

    expect(controller.tokenForRequest('/api/products/1'), 'token-action');
    controller.consumeActionAuthorization();
    expect(controller.tokenForRequest('/api/products/1'), isNull);
  });

  test('route authorization only matches the authorized route path', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 10),
      'token-route',
      '/users/abc/permissions',
    );

    expect(controller.isAuthorizedForRoute('/users/abc/permissions'), isTrue);
    expect(
      controller.isAuthorizedForRoute('/users/abc/permissions?x=1'),
      isTrue,
    );
    expect(controller.isAuthorizedForRoute('/users'), isFalse);

    controller.clearIfInvalidForLocation('/users');
    expect(controller.isAuthorizedForRoute('/users/abc/permissions'), isFalse);
  });

  test('route authorization is available immediately after granting', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 10),
      'token-route',
      '/ventas/lista',
    );

    expect(controller.isAuthorizedForRoute('/ventas/lista'), isTrue);
    expect(
      container
          .read(adminAuthorizationProvider)
          .isAuthorizedForRoute('/ventas/lista'),
      isTrue,
    );
  });

  test('router refresh on the previous route does not consume route grant', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 10),
      'token-route',
      '/ventas/lista',
    );

    controller.clearIfExpired();

    expect(controller.isAuthorizedForRoute('/ventas/lista'), isTrue);
  });

  test('route authorization is revoked after leaving the authorized route', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 10),
      'token-route',
      '/settings/company',
    );

    expect(controller.isAuthorizedForRoute('/settings/company'), isTrue);
    controller.markRouteEntered('/settings/company');
    controller.clearIfRouteScopeExited('/cotizaciones');

    expect(controller.isAuthorizedForRoute('/settings/company'), isFalse);
  });

  test('company A authorization is not valid for company B', () {
    final containerA = _container(companyId: 'company-a');
    final containerB = _container(companyId: 'company-b');
    addTearDown(containerA.dispose);
    addTearDown(containerB.dispose);

    final controllerA = containerA.read(adminAuthorizationProvider.notifier);
    controllerA.authorizeAction(const Duration(minutes: 10), 'token-a');

    final stateA = containerA.read(adminAuthorizationProvider);
    expect(stateA.belongsTo('employee-a', 'company-a'), isTrue);
    expect(stateA.belongsTo('employee-a', 'company-b'), isFalse);

    final controllerB = containerB.read(adminAuthorizationProvider.notifier);
    expect(controllerB.tokenForRequest('/settings'), isNull);
  });

  test('employee A authorization is not valid for employee B', () {
    final container = _container(userId: 'employee-a');
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeAction(const Duration(minutes: 10), 'token-a');

    final state = container.read(adminAuthorizationProvider);
    expect(state.belongsTo('employee-a', 'company-a'), isTrue);
    expect(state.belongsTo('employee-b', 'company-a'), isFalse);
  });
}
