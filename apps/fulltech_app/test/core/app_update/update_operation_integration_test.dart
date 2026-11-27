import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/api/api_client.dart';
import 'package:daleventa_pos/core/app_update/update_critical_operation_gate.dart';
import 'package:daleventa_pos/core/update/print_activity_tracker.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.body);
  final Future<ResponseBody> Function(RequestOptions) body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => body(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gate = UpdateCriticalOperationGate.instance;
  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:14627\n');
    gate.releaseRestart();
  });
  tearDown(gate.releaseRestart);

  test(
    'HTTP mutation holds gate until actual response and releases on error',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final dio = ApiClient().dio;
      addTearDown(() => dio.close(force: true));
      dio.httpClientAdapter = Adapter((options) async {
        expect(gate.hasActiveCriticalOperation, isTrue);
        started.complete();
        await finish.future;
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      final request = dio.post('/synthetic-write', data: {'fixture': true});
      await started.future;
      expect(gate.reserveRestart(), isFalse);
      finish.complete();
      await request;
      expect(gate.hasActiveCriticalOperation, isFalse);
      dio.httpClientAdapter = Adapter(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        dio.post('/synthetic-failure'),
        throwsA(isA<DioException>()),
      );
      expect(gate.hasActiveCriticalOperation, isFalse);
      expect(gate.reserveRestart(), isTrue);
    },
  );

  test(
    'reserved restart prevents new write without contacting server and can be released',
    () async {
      final dio = ApiClient().dio;
      addTearDown(() => dio.close(force: true));
      var requests = 0;
      dio.httpClientAdapter = Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
      expect(gate.reserveRestart(), isTrue);
      await expectLater(
        dio.post('/synthetic-write'),
        throwsA(isA<DioException>()),
      );
      expect(requests, 0);
      gate.releaseRestart();
      await dio.post('/synthetic-write');
      expect(requests, 1);
      expect(gate.hasActiveCriticalOperation, isFalse);
    },
  );

  test('actual print tracker participates in shared restart gate', () {
    final printer = PrintActivityTracker.instance;
    printer.markPrintStarted();
    expect(gate.reserveRestart(), isFalse);
    printer.markPrintCompleted();
    expect(gate.reserveRestart(), isTrue);
    expect(() => printer.markPrintStarted(), throwsException);
    gate.releaseRestart();
    printer.markPrintStarted();
    printer.markPrintCompleted();
    expect(gate.hasActiveCriticalOperation, isFalse);
  });
}
