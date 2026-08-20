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

      // El refresh ahora es single-flight compartido vía AuthRefreshCoordinator.
      expect(source, contains('_refreshCoordinator.ensureRefreshed()'));
      expect(source, contains('if (refreshed.isInvalid)'));
      expect(source, contains('await _safeClearTokens();'));
      expect(source, contains('if (refreshed.isFailed && allowCachedFallback)'));
    },
  );

  test(
    'refresh is centralized in a single-flight coordinator shared by interceptor and repository',
    () {
      final coordinator = File(
        'lib/core/auth/auth_refresh_coordinator.dart',
      ).readAsStringSync();
      final interceptor = File(
        'lib/core/auth/auth_interceptor.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/core/auth/auth_repository.dart',
      ).readAsStringSync();

      // El coordinador garantiza un único POST /refresh concurrente.
      expect(coordinator, contains('Future<AuthRefreshResult>? _inFlight;'));
      expect(coordinator, contains('_inFlight ??='));
      expect(coordinator, contains('AuthRefreshOutcome.invalid'));
      expect(coordinator, contains('AuthRefreshOutcome.failed'));

      // Interceptor y repositorio reutilizan el mismo coordinador.
      expect(interceptor, contains('refreshCoordinator.ensureRefreshed()'));
      expect(repository, contains('_refreshCoordinator.ensureRefreshed()'));
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

  test(
    'secure storage access is serialized with a single-flight mutex (Windows lock fix)',
    () {
      final source = File(
        'lib/core/auth/token_storage.dart',
      ).readAsStringSync();

      // El mutex encadena cada operación sobre flutter_secure_storage.dat.
      expect(source, contains('Future<void> _secureTail = Future.value();'));
      expect(source, contains('Future<T> _serializeSecure<T>'));
      expect(source, contains('_secureTail = result.then<void>((_) {}, onError: (_) {});'));

      // Todas las operaciones de secure storage pasan por el mutex.
      expect(source, contains('await _serializeSecure(() async {'));
      expect(source, contains('_secureStorage.read(key: key)'));
      expect(source, contains('_secureStorage.write(key: key, value: value)'));
      expect(source, contains('_secureStorage.delete(key: key)'));
      expect(source, contains('_secureStorage.write(key: _accessTokenKey'));
      expect(source, contains('_secureStorage.write(key: _refreshTokenKey'));
    },
  );

  test(
    'corrupt secure storage is detected and recovered once without clearing session',
    () {
      final source = File(
        'lib/core/auth/token_storage.dart',
      ).readAsStringSync();

      // Detección de corrupción (CryptUnprotectData / PathAccessException).
      expect(source, contains('_secureCorrupted = true;'));
      expect(source, contains("msg.contains('cryptunprotectdata')"));
      expect(source, contains("msg.contains('being used by another process')"));

      // Recuperación segura una sola vez, sin borrar la sesión.
      expect(source, contains('Future<void> _recoverSecureIfNeeded()'));
      expect(source, contains('_secureRecoveryAttempted = true;'));
      expect(source, contains('_secureStorage.deleteAll()'));
      expect(source, contains('_secureCorrupted = false;'));
      expect(source, contains('Secure storage recovered (corrupt file rebuilt)'));
    },
  );

  test(
    'user snapshot save failure never clears valid tokens',
    () {
      final source = File(
        'lib/core/auth/token_storage.dart',
      ).readAsStringSync();

      // saveUserSnapshot solo escribe el snapshot; nunca borra tokens.
      expect(source, contains('Future<void> saveUserSnapshot(UserModel user)'));
      expect(source, contains('_memoryUserSnapshot = user;'));
      expect(source, contains('saveUserSnapshot() secure ERROR'));

      // Extrae el cuerpo del método saveUserSnapshot y verifica que NO llame a
      // clearTokens() (el método clearTokens existe en la clase, pero no debe
      // invocarse desde saveUserSnapshot).
      final start = source.indexOf('Future<void> saveUserSnapshot');
      final end = source.indexOf('Future<UserModel?> getUserSnapshot');
      final methodBody = source.substring(start, end);
      expect(methodBody, isNot(contains('clearTokens()')));
    },
  );

}
