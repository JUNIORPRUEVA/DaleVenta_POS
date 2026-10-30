import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato Flutter del DESPACHO SIMULADO.
///
/// Fija la ruta y el cuerpo que envía el cliente, y que el resultado NUNCA se
/// interpreta como aceptación fiscal (`officialFiscalAcceptance`).
void main() {
  late RequestOptions? captured;

  EcfRepository repositoryWith(Object body, {int status = 200}) {
    final dio = Dio()
      ..httpClientAdapter = _RecordingAdapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    return EcfRepository(dio);
  }

  test('simulateDispatch llama a la ruta simulada con el escenario', () async {
    final repository = repositoryWith({
      'simulated': true,
      'officialFiscalAcceptance': false,
      'scenario': 'PROVIDER_ACCEPTED',
      'correlated': true,
      'documentType': 'E31',
      'observation': {
        'providerOutcome': 'ACCEPTED',
        'safeCode': 'ECF_OBSERVED_ACCEPTED',
      },
    });

    final outcome = await repository.simulateDispatch(
      documentId: 'doc-1',
      scenario: 'PROVIDER_ACCEPTED',
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/documents/doc-1/simulate-dispatch');
    expect(captured?.data, {'scenario': 'PROVIDER_ACCEPTED'});
    expect(outcome.simulated, isTrue);
    expect(outcome.correlated, isTrue);
    expect(outcome.providerOutcome, 'ACCEPTED');
    expect(outcome.safeCode, 'ECF_OBSERVED_ACCEPTED');
    // La regla de oro, también en el cliente.
    expect(outcome.officialFiscalAcceptance, isFalse);
    expect(EcfSimulatedDispatchOutcome.canRetryPost, isFalse);
  });

  test('un timeout simulado se refleja como no correlacionado', () async {
    final repository = repositoryWith({
      'simulated': true,
      'officialFiscalAcceptance': false,
      'scenario': 'TIMEOUT',
      'correlated': false,
      'documentType': 'E31',
      'observation': {'providerOutcome': 'UNKNOWN'},
    });

    final outcome = await repository.simulateDispatch(
      documentId: 'doc-2',
      scenario: 'TIMEOUT',
    );

    expect(outcome.correlated, isFalse);
    expect(outcome.providerOutcome, 'UNKNOWN');
    expect(outcome.safeCode, isNull);
    expect(outcome.officialFiscalAcceptance, isFalse);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
