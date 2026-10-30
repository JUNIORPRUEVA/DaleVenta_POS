import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato Flutter del onboarding fiscal (proceso INTERNO).
///
/// Fija la ruta, el cuerpo y —lo importante— que los estados que se muestran son
/// internos: completar un paso **no** acredita certificación ante la DGII.
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

  test('onboarding lee pasos y estado interno', () async {
    final repository = repositoryWith({
      'config': {
        'enabled': true,
        'certificationStatus': 'IN_PROGRESS',
        'productionEnabled': false,
      },
      'steps': [
        {'stepKey': 'FISCAL_DATA', 'status': 'COMPLETED', 'mode': 'MANUAL'},
        {'stepKey': 'REQUIREMENTS', 'status': 'PENDING'},
        {
          'stepKey': 'CERTIFICATION',
          'status': 'BLOCKED',
          'blockedReason': 'Falta el set de pruebas',
        },
      ],
      'latestAudits': [
        {'action': 'STEP_UPDATED'},
      ],
    });

    final view = await repository.onboarding();

    expect(captured?.method, 'GET');
    expect(captured?.path, '/ecf/onboarding');
    expect(view.steps, hasLength(3));
    expect(view.certificationStatus, 'IN_PROGRESS');
    expect(view.productionEnabled, isFalse);
    expect(view.progress, closeTo(1 / 3, 0.001));

    final blocked = view.steps.firstWhere((s) => s.stepKey == 'CERTIFICATION');
    expect(blocked.isBlocked, isTrue);
    // Un paso bloqueado no se "arregla" marcándolo desde la interfaz.
    expect(blocked.canComplete, isFalse);
    expect(blocked.blockedReason, 'Falta el set de pruebas');

    final done = view.steps.firstWhere((s) => s.stepKey == 'FISCAL_DATA');
    expect(done.isDone, isTrue);
    expect(done.canComplete, isFalse);
    expect(done.label, 'Datos fiscales');

    final pending = view.steps.firstWhere((s) => s.stepKey == 'REQUIREMENTS');
    expect(pending.canComplete, isTrue);
  });

  test('tolera una carga útil incompleta sin romper la pantalla', () async {
    final repository = repositoryWith({'steps': <Object>[]});
    final view = await repository.onboarding();

    expect(view.steps, isEmpty);
    expect(view.progress, 0);
    expect(view.certificationStatus, 'NOT_STARTED');
    expect(view.productionEnabled, isFalse);
  });

  test('updateOnboardingStep envía el estado al paso correcto', () async {
    final repository = repositoryWith({'ok': true});

    await repository.updateOnboardingStep(
      stepKey: 'REQUIREMENTS',
      status: 'COMPLETED',
    );

    expect(captured?.method, 'PATCH');
    expect(captured?.path, '/ecf/onboarding/steps/REQUIREMENTS');
    expect(captured?.data, {'status': 'COMPLETED'});
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
