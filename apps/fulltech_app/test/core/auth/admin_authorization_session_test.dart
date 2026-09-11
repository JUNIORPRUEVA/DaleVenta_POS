import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daleventa_pos/core/auth/admin_authorization_session.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';

void main() {
  test('action authorization is single use', () {
    final container = _authorizedContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeAction(const Duration(minutes: 10), 'token-action');

    expect(controller.tokenForRequest('/api/products/1'), 'token-action');
    controller.consumeActionAuthorization();
    expect(controller.tokenForRequest('/api/products/1'), isNull);
  });

  test('route authorization only matches the authorized route path', () {
    final container = _authorizedContainer();
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
    final container = _authorizedContainer();
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
    final container = _authorizedContainer();
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

  test(
    'route authorization is invalidated after leaving the protected route',
    () {
      final container = _authorizedContainer();
      addTearDown(container.dispose);

      final controller = container.read(adminAuthorizationProvider.notifier);
      controller.authorizeRoute(
        const Duration(minutes: 20),
        'token-reports',
        '/ventas',
      );

      expect(controller.isAuthorizedForRoute('/ventas'), isTrue);

      controller.clearIfInvalidForLocation('/cotizaciones');

      expect(controller.isAuthorizedForRoute('/ventas'), isFalse);
      expect(container.read(adminAuthorizationProvider).token, isNull);
    },
  );

  test(
    'route authorization remains valid inside the same screen for 5 minutes',
    () {
      var now = DateTime(2026, 9, 9, 10);
      final container = _authorizedContainer(
        overrides: [adminAuthorizationNowProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      final controller = container.read(adminAuthorizationProvider.notifier);
      controller.authorizeRoute(
        const Duration(minutes: 20),
        'token-reports',
        '/ventas',
      );

      now = now.add(const Duration(minutes: 5));
      controller.clearIfInvalidForLocation('/ventas');

      expect(controller.isAuthorizedForRoute('/ventas?tab=resumen'), isTrue);
    },
  );

  test('route authorization expires after the 20 minute maximum ttl', () {
    var now = DateTime(2026, 9, 9, 10);
    final container = _authorizedContainer(
      overrides: [adminAuthorizationNowProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(hours: 1),
      'token-reports',
      '/ventas',
    );

    expect(
      container.read(adminAuthorizationProvider).authorizedUntil,
      DateTime(2026, 9, 9, 10, 20),
    );

    now = now.add(const Duration(minutes: 20, seconds: 1));
    controller.clearIfExpired();

    expect(controller.isAuthorizedForRoute('/ventas'), isFalse);
    expect(container.read(adminAuthorizationProvider).token, isNull);
  });

  test('route authorization does not unlock a different protected route', () {
    final container = _authorizedContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 20),
      'token-reports',
      '/ventas',
    );

    expect(controller.isAuthorizedForRoute('/ventas'), isTrue);
    expect(controller.isAuthorizedForRoute('/configuracion'), isFalse);
  });

  test('authorization is cleared when the current user logs out', () async {
    final container = _authorizedContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 20),
      'token-reports',
      '/ventas',
    );

    await container.read(authStateProvider.notifier).logout();

    expect(controller.isAuthorizedForRoute('/ventas'), isFalse);
    expect(container.read(adminAuthorizationProvider).token, isNull);
  });

  test('authorization is cleared when the company changes', () {
    final container = _authorizedContainer();
    addTearDown(container.dispose);

    final controller = container.read(adminAuthorizationProvider.notifier);
    controller.authorizeRoute(
      const Duration(minutes: 20),
      'token-reports',
      '/ventas',
    );

    container
        .read(authStateProvider.notifier)
        .setUser(_user(companyId: 'company-b'), persistSnapshot: false);

    expect(controller.isAuthorizedForRoute('/ventas'), isFalse);
    expect(container.read(adminAuthorizationProvider).token, isNull);
  });

  test('admin users still do not need temporary authorization state', () {
    final container = _authorizedContainer(user: _user(role: 'ADMIN'));
    addTearDown(container.dispose);

    expect(container.read(adminAuthorizationProvider).token, isNull);
  });
}

ProviderContainer _authorizedContainer({
  UserModel? user,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(overrides: overrides);
  container
      .read(authStateProvider.notifier)
      .setUser(user ?? _user(), persistSnapshot: false);
  return container;
}

UserModel _user({String role = 'CAJERO', String companyId = 'company-a'}) {
  return UserModel(
    id: 'user-1',
    email: 'user@example.com',
    nombreCompleto: 'Usuario de prueba',
    telefono: '8090000000',
    role: role,
    companyId: companyId,
  );
}
