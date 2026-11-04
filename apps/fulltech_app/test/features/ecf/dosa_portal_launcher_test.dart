import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adaptador falso: devuelve la respuesta indicada sin tocar la red.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.statusCode = 201, this.body = '{}', this.throwError});

  final int statusCode;
  final String body;
  final DioException? throwError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwError != null) throw throwError!;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DosaPortalApi _apiWith(_FakeAdapter adapter, {String? base}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3999'));
  dio.httpClientAdapter = adapter;
  return DosaPortalApi(dio, portalBaseUrl: base);
}

void main() {
  group('buildDosaPortalUrl', () {
    test('usa el dominio autorizado y codifica el ticket', () {
      final url = buildDosaPortalUrl(
        portalBaseUrl: 'https://fullposcloud.fulltechrd.com',
        ticket: 'abc123',
      );
      expect(
        url,
        'https://fullposcloud.fulltechrd.com/ecf/certificacion/?ticket=abc123',
      );
    });

    test('tolera barras finales y espacios', () {
      final url = buildDosaPortalUrl(
        portalBaseUrl: '  https://fullposcloud.fulltechrd.com///  ',
        ticket: ' abc123 ',
      );
      expect(
        url,
        'https://fullposcloud.fulltechrd.com/ecf/certificacion/?ticket=abc123',
      );
    });

    test('escapa caracteres que romperían la URL', () {
      final url = buildDosaPortalUrl(
        portalBaseUrl: 'https://fullposcloud.fulltechrd.com',
        ticket: 'a+b/c=d',
      );
      expect(url, contains('ticket=a%2Bb%2Fc%3Dd'));
      // El ticket nunca se concatena en crudo.
      expect(url, isNot(contains('ticket=a+b/c=d')));
    });

    test('la URL es https del dominio autorizado, no localhost', () {
      final url = buildDosaPortalUrl(
        portalBaseUrl: defaultDosaPortalBaseUrl,
        ticket: 'xyz',
      );
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'fullposcloud.fulltechrd.com');
      expect(uri.path, '/ecf/certificacion/');
    });
  });

  group('DosaPortalApi.requestTicket', () {
    test('devuelve la URL del portal con el ticket del servidor', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 201,
          body: jsonEncode({
            'ok': true,
            'ticket': 'ticket-de-prueba-123',
            'expiresAt': '2026-11-03T00:00:00.000Z',
          }),
        ),
      );

      final ticket = await api.requestTicket();
      expect(ticket.url, contains('/ecf/certificacion/?ticket=ticket-de-prueba-123'));
      expect(ticket.expiresAt, isNotEmpty);
    });

    test('sin ticket en la respuesta, falla con un mensaje claro', () async {
      final api = _apiWith(_FakeAdapter(body: jsonEncode({'ok': true})));

      await expectLater(
        api.requestTicket(),
        throwsA(
          isA<DosaPortalException>().having(
            (e) => e.message,
            'message',
            contains('no devolvió'),
          ),
        ),
      );
    });

    test('un 403 se traduce a falta de permisos, sin filtrar detalles', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 403,
          body: jsonEncode({'message': 'Forbidden resource'}),
        ),
      );

      await expectLater(
        api.requestTicket(),
        throwsA(
          isA<DosaPortalException>().having(
            (e) => e.message,
            'message',
            allOf(contains('permiso'), isNot(contains('Forbidden resource'))),
          ),
        ),
      );
    });

    test('el piloto cerrado se explica como tal, no como error de red', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 403,
          body: jsonEncode({'message': 'PORTAL_PILOT_NOT_INCLUDED'}),
        ),
      );

      await expectLater(
        api.requestTicket(),
        throwsA(
          isA<DosaPortalException>().having(
            (e) => e.message,
            'message',
            contains('piloto'),
          ),
        ),
      );
    });

    test('un fallo de red no expone el error interno', () async {
      final api = _apiWith(
        _FakeAdapter(
          throwError: DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
            error: 'ECONNREFUSED 127.0.0.1:3999',
          ),
        ),
      );

      await expectLater(
        api.requestTicket(),
        throwsA(
          isA<DosaPortalException>().having(
            (e) => e.message,
            'message',
            isNot(contains('ECONNREFUSED')),
          ),
        ),
      );
    });
  });

  group('DosaPortalApi.isEligible', () {
    test('la empresa piloto es elegible', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 200,
          body: jsonEncode({'ok': true, 'eligible': true, 'reason': 'ELIGIBLE'}),
        ),
      );

      expect(await api.isEligible(), isTrue);
    });

    test('una empresa fuera del piloto no es elegible', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 200,
          body: jsonEncode({'ok': true, 'eligible': false}),
        ),
      );

      expect(await api.isEligible(), isFalse);
    });

    test('sin permiso (403) queda cerrado', () async {
      final api = _apiWith(
        _FakeAdapter(
          statusCode: 403,
          body: jsonEncode({'message': 'Forbidden resource'}),
        ),
      );

      expect(await api.isEligible(), isFalse);
    });

    test('un fallo de red no abre la entrada', () async {
      final api = _apiWith(
        _FakeAdapter(
          throwError: DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        ),
      );

      expect(await api.isEligible(), isFalse);
    });
  });

  group('openDosaPortal', () {
    test('rechaza esquemas que no son http(s)', () async {
      expect(await openDosaPortal('javascript:alert(1)'), isFalse);
      expect(await openDosaPortal('file:///etc/passwd'), isFalse);
      expect(await openDosaPortal('no-es-una-url'), isFalse);
    });
  });
}
