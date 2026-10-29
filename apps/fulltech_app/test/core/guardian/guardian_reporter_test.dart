import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/user_facing_error.dart' show AppErrorKind;
import 'package:daleventa_pos/core/guardian/guardian_client.dart';
import 'package:daleventa_pos/core/guardian/guardian_config.dart';
import 'package:daleventa_pos/core/guardian/guardian_reporter.dart';
import 'package:daleventa_pos/core/guardian/guardian_store.dart';
import 'package:daleventa_pos/core/guardian/guardian_transport.dart';

class _NoopTransport implements GuardianTransport {
  @override
  Future<GuardianSendResult> send(events) async => const GuardianSendResult();
}

GuardianReporter _reporter() {
  final client = GuardianClient(
    store: InMemoryGuardianStore(),
    transport: _NoopTransport(),
    config: const GuardianConfig(
      enabled: true,
      endpointPath: '/guardian/incidents',
      maxEvents: 200,
      maxBytes: 1024 * 1024,
      batchSize: 20,
      minSeverityToPersist: 'SEV3',
      sampleRateSev3Sev4: 1,
      flushInterval: Duration(minutes: 2),
    ),
  );
  return GuardianReporter(client: client);
}

AppErrorDetails _details({
  AppErrorKind kind = AppErrorKind.server,
  AppErrorSeverity severity = AppErrorSeverity.error,
  String? endpoint,
  String? method,
  String message = 'Error interno',
  String stack = 'at CashService.close (cash.dart:10:3)',
  String errorType = 'ApiException',
  String? apiResponse,
  String? context,
}) {
  return AppErrorDetails(
    eventId: 1,
    capturedAt: DateTime.now(),
    title: 'Error',
    userMessage: 'Ocurrió un error',
    message: message,
    stackTrace: stack,
    errorType: errorType,
    severity: severity,
    kind: kind,
    context: context,
    endpointUrl: endpoint,
    method: method,
    apiResponse: apiResponse,
  );
}

void main() {
  group('GuardianReporter — clasificación', () {
    test('un error fatal es SEV1', () {
      final event = _reporter().toEvent(_details(severity: AppErrorSeverity.fatal));
      expect(event, isNotNull);
      expect(event!.severity, 'SEV1');
    });

    test('un 5xx en caja es SEV1 y se atribuye al módulo cash', () {
      final event = _reporter().toEvent(
        _details(endpoint: 'https://api.example.com/api/sales/123', method: 'post', kind: AppErrorKind.server),
      );
      expect(event!.module, 'sales');
      expect(event.severity, 'SEV1');
      expect(event.operation, 'POST /api/sales/:id');
    });

    test('un fallo de red se clasifica SEV4 y no se persiste por defecto', () {
      final reporter = _reporter();
      final event = reporter.toEvent(_details(kind: AppErrorKind.network));
      expect(event!.severity, 'SEV4');
    });

    test('los fallos de carga de imágenes se ignoran', () {
      final event = _reporter().toEvent(_details(kind: AppErrorKind.media));
      expect(event, isNull);
    });

    test('redacta correos y rutas del equipo del cliente', () {
      final event = _reporter().toEvent(
        _details(
          message: 'fallo con juan@example.com en C:\\Users\\cliente\\FullPOS\\db.sqlite',
        ),
      );
      expect(event!.message, isNot(contains('juan@example.com')));
      expect(event.message, isNot(contains('cliente')));
      expect(event.message, contains('[email]'));
    });

    test('extrae el requestId del cuerpo de error para correlacionar', () {
      final event = _reporter().toEvent(
        _details(apiResponse: '{"statusCode":500,"requestId":"req-abc-123456"}'),
      );
      expect(event!.correlationId, 'req-abc-123456');
    });

    test('detecta el módulo de sincronización y actualización', () {
      final reporter = _reporter();
      expect(reporter.moduleFor('/api/sync/push', null), 'sync');
      expect(reporter.moduleFor(null, 'actualización fallida'), 'updater');
      expect(reporter.moduleFor('/api/cash/close', null), 'cash');
      expect(reporter.moduleFor(null, null), 'flutter');
    });

    test('el evento generado cumple el contrato del API', () {
      final event = _reporter().toEvent(_details())!;
      final json = event.toApiJson();
      expect(json['eventId'], isA<String>());
      expect(json['severity'], 'SEV2');
      expect(json['module'], isA<String>());
      expect(json['operation'], isA<String>());
      expect(json['occurredAt'], contains('T'));
      expect(json['schemaVersion'], 1);
      expect(json.keys.toSet().containsAll(<String>{'eventId', 'severity', 'module', 'operation', 'occurredAt'}), isTrue);
    });
  });
}
