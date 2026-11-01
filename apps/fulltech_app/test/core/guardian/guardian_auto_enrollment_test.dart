import 'dart:convert';

import 'package:daleventa_pos/core/guardian/guardian_auto_enrollment_code_source.dart';
import 'package:daleventa_pos/core/guardian/guardian_auto_transport.dart';
import 'package:daleventa_pos/core/guardian/guardian_enrollment.dart';
import 'package:daleventa_pos/core/guardian/guardian_event.dart';
import 'package:daleventa_pos/core/guardian/guardian_install_credential_store.dart';
import 'package:daleventa_pos/core/guardian/guardian_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auto-enrolamiento del cliente:
/// - la autorización solo se pide con sesión autenticada,
/// - nunca lanza ni bloquea,
/// - una instalación offline usa la sesión y se enrola cuando puede,
/// - un rechazo del servidor no deja la instalación muda.

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body, required this.status});

  final dynamic body;
  final int status;
  int calls = 0;
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    lastOptions = options;
    final payload = body is String ? body as String : jsonEncode(body);
    return ResponseBody.fromString(
      payload,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(requestOptions: options, reason: 'sin red');
  }
}

Dio _dio(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return dio;
}

class _FakeStore extends GuardianInstallCredentialStore {
  _FakeStore();

  GuardianInstallCredential? value;
  int clears = 0;

  @override
  bool get isSupported => true;

  @override
  Future<GuardianInstallCredential?> read() async => value;

  @override
  Future<void> write(GuardianInstallCredential credential) async {
    value = credential;
  }

  @override
  Future<void> clear() async {
    clears += 1;
    value = null;
  }
}

class _FakeEnrollment extends GuardianEnrollmentService {
  _FakeEnrollment({this.credential})
      : super(
          baseUrl: 'https://example.test',
          store: _FakeStore(),
          codeProvider: () async => null,
        );

  final GuardianInstallCredential? credential;
  int calls = 0;

  @override
  Future<GuardianInstallCredential?> ensureCredential({
    required String installId,
    String? platform,
    String? appVersion,
    bool forceEnroll = false,
  }) async {
    calls += 1;
    return credential;
  }
}

class _RecordingTransport implements GuardianTransport {
  _RecordingTransport({this.result = const GuardianSendResult(acked: <String>[]), this.reason});

  final GuardianSendResult result;
  final String? reason;
  int calls = 0;
  List<GuardianEvent> lastEvents = const <GuardianEvent>[];

  @override
  Future<GuardianSendResult> send(List<GuardianEvent> events) async {
    calls += 1;
    lastEvents = events;
    if (reason != null) {
      return GuardianSendResult(retryable: true, reason: reason);
    }
    return result;
  }
}

GuardianEvent _event(String id) => GuardianEvent(
      eventId: id,
      severity: 'SEV2',
      module: 'cash',
      operation: 'closeSession',
      platform: 'windows',
      appVersion: '1.0.6',
      deviceId: 'dev-test',
      occurredAt: DateTime.utc(2026, 10, 29, 12),
      message: 'timeout',
      attempts: 0,
    );

void main() {
  group('autorizacion de enrolamiento con sesion', () {
    test('devuelve el codigo cuando el servidor lo concede', () async {
      final adapter = _StubAdapter(
        body: <String, dynamic>{
          'code': 'genr_autorizacion_1234567890',
          'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
          'enrollPath': '/guardian/installations/enroll',
        },
        status: 201,
      );
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'jwt-sesion',
        installId: 'install-abc123',
        platform: 'windows',
        dio: _dio(adapter),
      );

      final code = await source.read();

      expect(code, 'genr_autorizacion_1234567890');
      expect(adapter.calls, 1);
      expect(adapter.lastOptions?.headers['authorization'], 'Bearer jwt-sesion');
      expect(adapter.lastOptions?.path, contains('/guardian/installations/enrollment-grant'));
      // La empresa jamás se envía desde el cliente.
      final body = adapter.lastOptions?.data as Map<String, dynamic>;
      expect(body.containsKey('companyId'), isFalse);
    });

    test('sin sesion no hace ninguna peticion (offline / pre-login)', () async {
      final adapter = _StubAdapter(body: <String, dynamic>{}, status: 201);
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => null,
        installId: 'install-abc123',
        dio: _dio(adapter),
      );

      expect(await source.read(), isNull);
      expect(adapter.calls, 0);
    });

    test('una empresa fuera del despliegue devuelve null sin lanzar', () async {
      final adapter = _StubAdapter(
        body: <String, dynamic>{
          'code': 'COMPANY_NOT_ALLOWED',
          'message': 'La empresa no está incluida en el despliegue de auto-enrolamiento',
        },
        status: 403,
      );
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'jwt-sesion',
        installId: 'install-abc123',
        dio: _dio(adapter),
      );

      expect(await source.read(), isNull);
    });

    test('un error de red no lanza ni bloquea', () async {
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'jwt-sesion',
        installId: 'install-abc123',
        dio: _dio(_ThrowingAdapter()),
      );

      expect(await source.read(), isNull);
    });

    test('respeta el espaciado minimo entre intentos', () async {
      final adapter = _StubAdapter(
        body: <String, dynamic>{'code': 'genr_autorizacion_1234567890'},
        status: 201,
      );
      var now = DateTime.utc(2026, 10, 29, 12);
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'jwt-sesion',
        installId: 'install-abc123',
        dio: _dio(adapter),
        minIntervalBetweenAttempts: const Duration(minutes: 10),
        clock: () => now,
      );

      expect(await source.read(), 'genr_autorizacion_1234567890');
      // Segundo intento inmediato: se evita la petición.
      expect(await source.read(), isNull);
      expect(adapter.calls, 1);

      now = now.add(const Duration(minutes: 11));
      expect(await source.read(), 'genr_autorizacion_1234567890');
      expect(adapter.calls, 2);
    });

    test('interpreta el cuerpo aunque llegue como texto', () async {
      final source = GuardianAutoEnrollmentCodeSource(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'jwt-sesion',
        installId: 'install-abc123',
        dio: _dio(_StubAdapter(
          body: '{"code":"genr_desde_texto_1234567890"}',
          status: 201,
        )),
      );

      expect(await source.read(), 'genr_desde_texto_1234567890');
    });
  });

  group('transporte con enrolamiento diferido', () {
    test('sin credencial usa la sesion y no rompe el envio', () async {
      final session = _RecordingTransport(result: const GuardianSendResult(acked: <String>['e1']));
      final enrollment = _FakeEnrollment(credential: null);
      final transport = AutoEnrollingGuardianTransport(
        enrollment: enrollment,
        credentialStore: _FakeStore(),
        sessionTransport: session,
        machineTransportFactory: (_) => _RecordingTransport(),
        installId: 'install-abc123',
      );

      final result = await transport.send(<GuardianEvent>[_event('e1')]);

      expect(result.acked, <String>['e1']);
      expect(enrollment.calls, 1);
      expect(session.calls, 1);
      expect(transport.debugEnrollmentAttempts, 1);
    });

    test('con credencial envia por el canal de maquina', () async {
      final session = _RecordingTransport();
      final machine = _RecordingTransport(result: const GuardianSendResult(acked: <String>['e2']));
      final enrollment = _FakeEnrollment(
        credential: GuardianInstallCredential(
          installId: 'install-abc123',
          credential: 'gmk_test_credential_123456',
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
        ),
      );
      final transport = AutoEnrollingGuardianTransport(
        enrollment: enrollment,
        credentialStore: _FakeStore(),
        sessionTransport: session,
        machineTransportFactory: (_) => machine,
        installId: 'install-abc123',
      );

      final result = await transport.send(<GuardianEvent>[_event('e2')]);

      expect(result.acked, <String>['e2']);
      expect(machine.calls, 1);
      expect(session.calls, 0);
    });

    test('una credencial rechazada se descarta y se cae a la sesion', () async {
      final store = _FakeStore();
      final session = _RecordingTransport();
      final enrollment = _FakeEnrollment(
        credential: GuardianInstallCredential(
          installId: 'install-abc123',
          credential: 'gmk_revocada_1234567890',
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
        ),
      );
      final transport = AutoEnrollingGuardianTransport(
        enrollment: enrollment,
        credentialStore: store,
        sessionTransport: session,
        machineTransportFactory: (_) => _RecordingTransport(reason: 'HTTP_401'),
        installId: 'install-abc123',
      );

      await transport.send(<GuardianEvent>[_event('e3')]);

      expect(store.clears, 1);
      expect(session.calls, 1);
      expect(transport.debugEnrollmentAttempts, 1);
    });

    test('no recoloca enrolamiento en cada envio (evita ruido y coste)', () async {
      final enrollment = _FakeEnrollment(credential: null);
      final session = _RecordingTransport();
      var now = DateTime.utc(2026, 10, 29, 12);
      final transport = AutoEnrollingGuardianTransport(
        enrollment: enrollment,
        credentialStore: _FakeStore(),
        sessionTransport: session,
        machineTransportFactory: (_) => _RecordingTransport(),
        installId: 'install-abc123',
        clock: () => now,
      );

      await transport.send(<GuardianEvent>[_event('e4')]);
      now = now.add(const Duration(minutes: 2));
      await transport.send(<GuardianEvent>[_event('e5')]);

      expect(enrollment.calls, 1);
      expect(session.calls, 2);
    });
  });
}
