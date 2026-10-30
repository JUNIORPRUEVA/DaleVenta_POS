import 'dart:convert';

import 'package:daleventa_pos/core/guardian/guardian_enrollment.dart';
import 'package:daleventa_pos/core/guardian/guardian_install_credential_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fase 13 — regresión del defecto de aceptación:
/// el servidor consumía el código y creaba la credencial, pero el cliente
/// devolvía `null` sin ninguna traza cuando el cuerpo no llegaba como `Map`.
class _FakeStore extends GuardianInstallCredentialStore {
  _FakeStore({this.failWrite = false});

  final bool failWrite;
  GuardianInstallCredential? _value;
  int writes = 0;

  @override
  bool get isSupported => true;

  @override
  Future<GuardianInstallCredential?> read() async => _value;

  @override
  Future<void> write(GuardianInstallCredential credential) async {
    writes += 1;
    if (!failWrite) _value = credential;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

Dio _dioReturning(dynamic body, {int status = 201}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.httpClientAdapter = _StubAdapter(body: body, status: status);
  return dio;
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body, required this.status});

  final dynamic body;
  final int status;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

Map<String, dynamic> _okBody({String credential = 'gmk_test_credential_123456'}) =>
    <String, dynamic>{
      'installId': 'install-abc',
      'credential': credential,
      'expiresAt': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      'ingestPath': '/guardian/machine/incidents',
    };

void main() {
  test('canjea el código y persiste la credencial (cuerpo Map)', () async {
    final store = _FakeStore();
    var consumed = 0;
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => 'genr_abc123',
      onCodeConsumed: () async => consumed += 1,
      dio: _dioReturning(_okBody()),
    );

    final credential = await service.ensureCredential(installId: 'install-abc');

    expect(credential, isNotNull);
    expect(credential!.credential, 'gmk_test_credential_123456');
    expect(store.writes, 1);
    expect(consumed, 1);
  });

  test('cuerpo devuelto como texto JSON: ya no se pierde la credencial', () async {
    final store = _FakeStore();
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => 'genr_abc123',
      dio: _dioReturning(jsonEncode(_okBody(credential: 'gmk_from_text_body'))),
    );

    final credential = await service.ensureCredential(installId: 'install-abc');

    // Este es exactamente el defecto de la aceptación: antes devolvía null y el
    // código ya estaba consumido en el servidor.
    expect(credential, isNotNull);
    expect(credential!.credential, 'gmk_from_text_body');
    expect(store.writes, 1);
  });

  test('reutiliza la credencial persistida sin volver a canjear', () async {
    final store = _FakeStore();
    await store.write(GuardianInstallCredential(
      installId: 'install-abc',
      credential: 'gmk_already_stored',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 20)),
    ));
    var hits = 0;
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => 'genr_abc123',
      dio: _dioReturning(_okBody()),
      );

    final credential = await service.ensureCredential(installId: 'install-abc');

    expect(credential!.credential, 'gmk_already_stored');
    expect(hits, 0);
    expect(store.writes, 1); // solo la escritura inicial del test
  });

  test('sin código disponible no hay credencial y no se escribe nada', () async {
    final store = _FakeStore();
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => null,
      dio: _dioReturning(_okBody()),
    );

    final credential = await service.ensureCredential(installId: 'install-abc');

    expect(credential, isNull);
    expect(store.writes, 0);
  });

  test('si el almacén no persiste, la credencial sigue sirviendo en memoria', () async {
    final store = _FakeStore(failWrite: true);
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => 'genr_abc123',
      dio: _dioReturning(_okBody(credential: 'gmk_memory_only')),
    );

    final credential = await service.ensureCredential(installId: 'install-abc');

    expect(credential, isNotNull);
    expect(credential!.credential, 'gmk_memory_only');
    expect(await store.read(), isNull);
  });

  test('http 400 con código agotado no produce credencial', () async {
    final store = _FakeStore();
    final service = GuardianEnrollmentService(
      baseUrl: 'https://example.test',
      store: store,
      codeProvider: () async => 'genr_used',
      dio: _dioReturning(
        <String, dynamic>{
          'statusCode': 400,
          'code': 'ENROLLMENT_CODE_EXHAUSTED',
          'message': 'Código de enrolamiento ya utilizado',
        },
        status: 400,
      ),
    );

    final credential = await service.ensureCredential(installId: 'install-abc');

    expect(credential, isNull);
    expect(store.writes, 0);
  });
}
