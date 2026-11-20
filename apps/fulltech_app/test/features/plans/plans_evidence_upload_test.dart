import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/features/plans/data/plans_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  Duration delay = Duration.zero;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await requestStream?.drain<void>();
    await Future<void>.delayed(delay);
    return ResponseBody.fromString('{"license":{"status":"ACTIVE"},"message":"Recibido"}', 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _Adapter adapter;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000', receiveTimeout: const Duration(seconds: 20)));
    adapter = _Adapter();
    dio.httpClientAdapter = adapter;
  });
  tearDown(() => dio.close(force: true));

  testWidgets('sube bytes de navegador y espera un resultado posterior a 20 segundos sin repetir POST', (tester) async {
    adapter.delay = const Duration(seconds: 30);
    var completed = false;
    Object? failure;
    final upload = PlansRepository(dio).uploadEvidence(orderId: 'synthetic-order',
        fileBytes: Uint8List.fromList([37, 80, 68, 70]), fileName: 'prueba.pdf')
      .then((result) { completed = result.activated; }).catchError((Object e) { failure = e; });
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(completed, false);
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 10));
    await upload;
    expect(completed, true);
    expect(failure, isNull);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.receiveTimeout!.inSeconds, greaterThan(120));
    expect(dio.options.receiveTimeout, const Duration(seconds: 20));
  });

  test('conserva la subida por ruta usada en aplicaciones nativas', () async {
    final dir = await Directory.systemTemp.createTemp('fullpos-evidence-test-');
    final file = File('${dir.path}/prueba.pdf');
    try {
      await file.writeAsString('%PDF-synthetic');
      final result = await PlansRepository(dio).uploadEvidence(orderId: 'synthetic-order', filePath: file.path, fileName: 'prueba.pdf');
      expect(result.activated, true);
      expect(adapter.requests, hasLength(1));
    } finally {
      await file.delete();
      await dir.delete();
    }
  });

  test('sin contenido informa el problema y no hace solicitudes', () async {
    await expectLater(PlansRepository(dio).uploadEvidence(orderId: 'synthetic-order', fileName: 'prueba.pdf'), throwsException);
    expect(adapter.requests, isEmpty);
  });
}
