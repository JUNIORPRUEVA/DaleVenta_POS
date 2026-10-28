import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/env.dart';
import '../auth/token_storage.dart';
import '../debug/app_error_reporter.dart';
import '../usage/client_telemetry_headers.dart';
import 'guardian_agent_log.dart';
import 'guardian_client.dart';
import 'guardian_config.dart';
import 'guardian_dio_transport.dart';
import 'guardian_enrollment.dart';
import 'guardian_enrollment_code_source.dart';
import 'guardian_install_credential_store.dart';
import 'guardian_machine_transport.dart';
import 'guardian_reporter.dart';
import 'guardian_self_test.dart';
import 'guardian_sqflite_store.dart';
import 'guardian_store.dart';
import 'guardian_transport.dart';
import 'guardian_web_store.dart';

/// Fallo técnico ocurrido antes de que el agente estuviera listo.
class _EarlyFault {
  const _EarlyFault(this.details);

  final AppErrorDetails details;
}

/// Arranque del agente Guardian en la app.
///
/// - Fail-closed: sin `--dart-define=GUARDIAN_ENABLED=true` no hace nada.
/// - Nunca lanza: cualquier fallo de inicialización deja la app intacta.
/// - Desktop/móvil: cola SQLite propia. Web: cola persistente sobre
/// `shared_preferences` (localStorage/IndexedDB), separada de ventas.
/// - **Fallos de arranque**: `installStartupCapture()` se llama de forma
/// síncrona al principio de `main()` y bufferiza los errores previos a que el
/// cliente esté listo; se reinyectan en la cola en cuanto el agente arranca.
/// - **Autenticación**: con la instalación enrolada se usa la credencial de
/// instalación (`x-guardian-key`), que funciona antes del login. Sin ella se
/// mantiene el transporte con JWT de sesión.
class GuardianBootstrap {
  static Timer? _timer;
  static GuardianClient? _client;
  static GuardianReporter? _reporter;
  static bool _startupCaptureInstalled = false;
  static final List<_EarlyFault> _earlyFaults = <_EarlyFault>[];
  static const int _maxEarlyFaults = 20;

  static bool get isRunning => _client != null;

  /// Fallos bufferizados antes de que el agente estuviera listo.
  @visibleForTesting
  static int get earlyFaultCount => _earlyFaults.length;

  /// Instala la captura de arranque. Síncrona y barata: debe llamarse antes de
  /// inicializar SQLite, almacenamiento o licencias.
  static void installStartupCapture() {
    if (_startupCaptureInstalled) return;
    final config = GuardianConfig.fromEnvironment();
    if (!config.enabled) return;
    _startupCaptureInstalled = true;
    AppErrorReporter.instance.lastRecorded.addListener(_onEarlyFault);
  }

  static void _onEarlyFault() {
    if (_client != null) return;
    final details = AppErrorReporter.instance.lastRecorded.value;
    if (details == null) return;
    _bufferEarlyFault(details);
  }

  /// Punto de prueba: mismo buffer que usa la captura de arranque.
  @visibleForTesting
  static void debugRecordEarlyFault(AppErrorDetails details) => _bufferEarlyFault(details);

  static void _bufferEarlyFault(AppErrorDetails details) {
    if (_earlyFaults.any((fault) => fault.details.eventId == details.eventId)) return;
    _earlyFaults.add(_EarlyFault(details));
    while (_earlyFaults.length > _maxEarlyFaults) {
      _earlyFaults.removeAt(0);
    }
  }

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
      unawaited(GuardianAgentLog.info('store listo (${store.runtimeType})'));

      final resolvedBaseUrl = _resolveBaseUrl(config);
      final identity = await _loadIdentity();
      final installId = identity['x-client-device-id'] ?? '';

      final transport = await _resolveTransport(
        config: config,
        baseUrl: resolvedBaseUrl,
        installId: installId,
        platform: identity['x-client-platform'],
        appVersion: identity['x-client-app-version'],
      );

      final client = GuardianClient(store: store, transport: transport, config: config);
      GuardianClient.install(client);
      unawaited(GuardianAgentLog.info(
        'cliente listo transporte=${transport.runtimeType} endpoint=${config.effectiveEndpointPath} baseUrl=$resolvedBaseUrl',
      ));

      final reporter = GuardianReporter(client: client)..attach();

      _client = client;
      _reporter = reporter;

      // Reinyecta los fallos de arranque capturados antes de existir el cliente.
      unawaited(_flushEarlyFaults());
      AppErrorReporter.instance.lastRecorded.removeListener(_onEarlyFault);


      unawaited(client.flush());
      _timer = Timer.periodic(config.flushInterval, (_) => unawaited(client.flush()));

      unawaited(GuardianSelfTest.maybeRun(config: config, client: client, installId: installId));

      if (kDebugMode) {
        debugPrint('GUARDIAN: activo (${config.effectiveEndpointPath})');
      }
    } catch (error) {
      unawaited(GuardianAgentLog.warn('arranque fallido: $error'));
      if (kDebugMode) {
        debugPrint('GUARDIAN: no se pudo iniciar ($error)');
      }
    }
  }

  static String _resolveBaseUrl(GuardianConfig config) {
    for (final candidate in <String>[config.baseUrl, Env.apiBaseUrl]) {
      final value = candidate.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Future<GuardianTransport> _resolveTransport({
    required GuardianConfig config,
    required String baseUrl,
    required String installId,
    String? platform,
    String? appVersion,
  }) async {
    final sessionTransport = DioGuardianTransport(
      baseUrl: baseUrl,
      path: config.endpointPath,
      tokenProvider: () => TokenStorage().getAccessToken(),
    );

    if (!config.useMachineApi || baseUrl.isEmpty || installId.isEmpty) {
      return sessionTransport;
    }

    try {
      final credentialStore = GuardianInstallCredentialStore();
      final codeSource = GuardianEnrollmentCodeSource(filePath: config.enrollmentCodeFile);
      final enrollment = GuardianEnrollmentService(
        baseUrl: baseUrl,
        store: credentialStore,
        codeProvider: codeSource.read,
        onCodeConsumed: codeSource.consume,
      );
      final credential = await enrollment.ensureCredential(
        installId: installId,
        platform: platform,
        appVersion: appVersion,
      );
      if (credential == null) {
        unawaited(GuardianAgentLog.info('sin credencial de instalación: se usa transporte de sesión'));
        return sessionTransport;
      }
      unawaited(GuardianAgentLog.info(
        'credencial de instalación activa (caduca ${credential.expiresAt.toIso8601String()})',
      ));
      return MachineGuardianTransport(
        baseUrl: baseUrl,
        path: GuardianConfig.machineEndpointPath,
        credential: credential.credential,
        onCredentialRejected: credentialStore.clear,
      );
    } catch (_) {
      // Cualquier problema de enrolamiento deja el transporte de sesión.
      return sessionTransport;
    }
  }

  static Future<Map<String, String>> _loadIdentity() async {
    try {
      return await ClientTelemetryHeaders.instance.headers();
    } catch (_) {
      return const <String, String>{};
    }
  }

  static Future<void> _flushEarlyFaults() async {
    final reporter = _reporter;
    final client = _client;
    if (reporter == null || client == null || _earlyFaults.isEmpty) return;

    final pending = List<_EarlyFault>.from(_earlyFaults);
    _earlyFaults.clear();
    for (final fault in pending) {
      try {
        final event = reporter.toEvent(fault.details);
        if (event == null) continue;
        await client.record(event);
      } catch (_) {
        // Best-effort: un fallo de arranque no puede romper el arranque.
      }
    }
    unawaited(GuardianAgentLog.info('fallos de arranque reinyectados=${pending.length}'));
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _reporter?.detach();
    _reporter = null;
    await _client?.flush();
    _client = null;
    _earlyFaults.clear();
    AppErrorReporter.instance.lastRecorded.removeListener(_onEarlyFault);
    _startupCaptureInstalled = false;
  }
}
