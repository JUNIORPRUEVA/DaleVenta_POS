import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/env.dart';
import '../auth/token_storage.dart';
import 'guardian_client.dart';
import 'guardian_config.dart';
import 'guardian_dio_transport.dart';
import 'guardian_reporter.dart';
import 'guardian_sqflite_store.dart';
import 'guardian_store.dart';
import 'guardian_web_store.dart';

/// Arranque del agente Guardian en la app.
///
/// - Fail-closed: sin `--dart-define=GUARDIAN_ENABLED=true` no hace nada.
/// - Nunca lanza: cualquier fallo de inicialización deja la app intacta.
/// - Desktop/móvil: cola SQLite propia. Web: cola persistente sobre
///   `shared_preferences` (localStorage/IndexedDB), separada de ventas.
class GuardianBootstrap {
  static Timer? _timer;
  static GuardianClient? _client;
  static GuardianReporter? _reporter;

  static bool get isRunning => _client != null;

  static Future<void> start() async {
    if (_client != null) return;
    final config = GuardianConfig.fromEnvironment();
    if (!config.enabled) {
      if (kDebugMode) {
        debugPrint('GUARDIAN: desactivado (sin --dart-define=GUARDIAN_ENABLED=true)');
      }
      return;
    }

    try {
      final GuardianStore store = kIsWeb ? WebGuardianStore() : SqfliteGuardianStore();
      await store.init();

      final transport = DioGuardianTransport(
        baseUrl: Env.apiBaseUrl,
        path: config.endpointPath,
        tokenProvider: () => TokenStorage().getAccessToken(),
      );

      final client = GuardianClient(store: store, transport: transport, config: config);
      GuardianClient.install(client);

      final reporter = GuardianReporter(client: client)..attach();

      _client = client;
      _reporter = reporter;

      unawaited(client.flush());
      _timer = Timer.periodic(config.flushInterval, (_) => unawaited(client.flush()));

      if (kDebugMode) {
        debugPrint('GUARDIAN: activo (${config.endpointPath})');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('GUARDIAN: no se pudo iniciar ($error)');
      }
    }
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _reporter?.detach();
    _reporter = null;
    await _client?.flush();
    _client = null;
  }
}
