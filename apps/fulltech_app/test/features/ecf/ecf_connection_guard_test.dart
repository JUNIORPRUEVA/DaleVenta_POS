import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/features/ecf/data/ecf_connection_guard.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  test('offline preflight stops before the fiscal POST', () async {
    var posts = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        if (request.method == 'POST') posts++;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      });
    await expectLater(
      postEcf(dio, '/ecf/documents/document-1/dispatch-dosa'),
      throwsA(
        isA<EcfConnectionException>()
            .having((e) => e.uncertain, 'not submitted', false)
            .having(
              (e) => e.message,
              'brief notice',
              'La factura electrónica requiere internet.',
            ),
      ),
    );
    expect(posts, 0);
  });
  test(
    'lost response is uncertain and is never automatically posted again',
    () async {
      var posts = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          if (request.path == '/health') return _json({'status': 'ok'});
          posts++;
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        });
      await expectLater(
        postEcf(dio, '/ecf/documents/document-1/dispatch-dosa'),
        throwsA(
          isA<EcfConnectionException>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(posts, 1);
    },
  );
  test(
    'HTTP service failure and captive portal are not reported as absent internet',
    () async {
      for (final response in [
        _json({'status': 'down'}, 503),
        _json('<html>portal</html>'),
      ]) {
        var posts = 0;
        final dio = Dio()
          ..httpClientAdapter = _Adapter((request) async {
            if (request.method == 'POST') posts++;
            return response;
          });
        await expectLater(
          postEcf(dio, '/ecf/documents/document-1/dispatch-dosa'),
          throwsA(
            isA<EcfConnectionException>().having(
              (e) => e.serviceUnavailable,
              'service failure',
              true,
            ),
          ),
        );
        expect(posts, 0);
      }
    },
  );
  test(
    'a business rejection keeps its HTTP response and does not retry',
    () async {
      var posts = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          if (request.path == '/health') return _json({'status': 'ok'});
          posts++;
          return _json({'message': 'not authorized'}, 403);
        });
      await expectLater(
        postEcf(dio, '/ecf/documents/document-1/dispatch-dosa'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'HTTP status',
            403,
          ),
        ),
      );
      expect(posts, 1);
    },
  );
}
