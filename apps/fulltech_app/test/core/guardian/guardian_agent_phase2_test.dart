import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/guardian/guardian_bootstrap.dart';
import 'package:daleventa_pos/core/guardian/guardian_client.dart';
import 'package:daleventa_pos/core/guardian/guardian_config.dart';
import 'package:daleventa_pos/core/guardian/guardian_install_credential_store.dart';
import 'package:daleventa_pos/core/guardian/guardian_self_test.dart';
import 'package:daleventa_pos/core/guardian/guardian_store.dart';
import 'package:daleventa_pos/core/guardian/guardian_transport.dart';

class _NoopTransport implements GuardianTransport {
  @override
  Future<GuardianSendResult> send(events) async => const GuardianSendResult();
}

const GuardianConfig _baseConfig = GuardianConfig(
  enabled: true,
  endpointPath: '/guardian/incidents',
  maxEvents: 200,
  maxBytes: 1024 * 1024,
  batchSize: 20,
  minSeverityToPersist: 'SEV3',
  sampleRateSev3Sev4: 1,
  flushInterval: Duration(minutes: 2),
);

GuardianClient _client() => GuardianClient(
      store: InMemoryGuardianStore(),
      transport: _NoopTransport(),
      config: _baseConfig,
    );

AppErrorDetails _details(int eventId) => AppErrorDetails(
      eventId: eventId,
      capturedAt: DateTime.now(),
      title: 'Error',
      userMessage: 'Ocurrió un error',
      message: 'fallo técnico',
      stackTrace: 'at main (main.dart:1:1)',
      errorType: 'Exception',
      severity: AppErrorSeverity.error,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('credencial de instalación (modelo)', () {
    test('serializa y recupera la credencial sin pérdida', () {
      final credential = GuardianInstallCredential(
        installId: 'pos-uat-01',
        credential: 'gmk_abc',
        expiresAt: DateTime.utc(2027, 1, 1),
      );

      final restored = GuardianInstallCredential.fromJson(
        '{"installId":"pos-uat-01","credential":"gmk_abc","expiresAt":"2027-01-01T00:00:00.000Z"}',
      );

      expect(restored, isNotNull);
      expect(restored!.installId, credential.installId);
      expect(restored.credential, credential.credential);
      expect(restored.expiresAt, credential.expiresAt);
    });

    test('una credencial caducada o incompleta no es válida', () {
      expect(
        GuardianInstallCredential(
          installId: 'pos',
          credential: 'gmk_abc',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ).isValid(),
        isFalse,
      );
      expect(
        GuardianInstallCredential(
          installId: 'pos',
          credential: 'gmk_abc',
          expiresAt: DateTime.now().add(const Duration(days: 10)),
        ).isValid(),
        isTrue,
      );
      expect(
        GuardianInstallCredential(
          installId: 'pos',
          credential: '',
          expiresAt: DateTime.now().add(const Duration(days: 10)),
        ).isValid(),
        isFalse,
        reason: 'sin credencial no es válida',
      );
    });

    test('JSON corrupto devuelve null en lugar de lanzar', () {
      expect(GuardianInstallCredential.fromJson('no-json'), isNull);
      expect(GuardianInstallCredential.fromJson('{}'), isNull);
    });
  });

  group('buffer de fallos de arranque', () {
    setUp(() async {
      await GuardianBootstrap.stop();
    });

    test('bufferiza el fallo previo al arranque y deduplica por eventId', () {
      GuardianBootstrap.debugRecordEarlyFault(_details(1));
      GuardianBootstrap.debugRecordEarlyFault(_details(1));
      expect(GuardianBootstrap.earlyFaultCount, 1);

      GuardianBootstrap.debugRecordEarlyFault(_details(2));
      expect(GuardianBootstrap.earlyFaultCount, 2);
    });

    test('acota el buffer para no crecer sin límite', () {
      for (var i = 0; i < 50; i++) {
        GuardianBootstrap.debugRecordEarlyFault(_details(100 + i));
      }
      expect(GuardianBootstrap.earlyFaultCount, lessThanOrEqualTo(20));
    });

    test('el agente no arranca sin bandera de compilación (fail-closed)', () {
      expect(GuardianConfig.fromEnvironment().enabled, isFalse);
      expect(GuardianBootstrap.isRunning, isFalse);
    });
  });

  group('sonda de UAT', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('no hace nada si no está compilada la bandera', () async {
      await GuardianSelfTest.maybeRun(
        config: _baseConfig,
        client: _client(),
        installId: 'pos-uat-01',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('daleventas.guardian.selftest.done.v1'), isNull);
    });

    test('se ejecuta una sola vez por instalación', () async {
      const config = GuardianConfig(
        enabled: true,
        endpointPath: '/guardian/incidents',
        maxEvents: 200,
        maxBytes: 1024 * 1024,
        batchSize: 20,
        minSeverityToPersist: 'SEV3',
        sampleRateSev3Sev4: 1,
        flushInterval: Duration(minutes: 2),
        selfTest: true,
      );

      await GuardianSelfTest.maybeRun(config: config, client: _client(), installId: 'pos-uat-01');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('daleventas.guardian.selftest.done.v1'), isTrue);

      // Segunda llamada: el marcador impide repetir la sonda.
      await GuardianSelfTest.maybeRun(config: config, client: _client(), installId: 'otra-instalacion');
      expect(prefs.getBool('daleventas.guardian.selftest.done.v1'), isTrue);
    });
  });

  group('configuración de endpoints', () {
    test('el modo máquina usa el endpoint de instalación', () {
      const machine = GuardianConfig(
        enabled: true,
        endpointPath: '/guardian/incidents',
        maxEvents: 10,
        maxBytes: 1024,
        batchSize: 5,
        minSeverityToPersist: 'SEV4',
        sampleRateSev3Sev4: 1,
        flushInterval: Duration(minutes: 1),
        useMachineApi: true,
      );
      expect(machine.effectiveEndpointPath, GuardianConfig.machineEndpointPath);
      expect(_baseConfig.effectiveEndpointPath, '/guardian/incidents');
    });
  });
}
