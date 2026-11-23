import 'package:daleventa_pos/features/ecf/ecf_customer_message.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_dispatch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final providerOutcome in ['UNKNOWN', 'REJECTED', 'PENDING']) {
    test('resultado contradictorio $providerOutcome no anuncia aceptación', () {
      final outcome = EcfDosaDispatchOutcome.fromJson({
        'ok': true, 'result': 'FISCAL_RESULT_RECORDED', 'correlated': true,
        'observation': {'providerOutcome': providerOutcome, 'safeCode': 'ECF_DOSA_OBSERVED_ACCEPTED'},
      });
      expect(outcome.message, contains('revisión'));
      expect(outcome.message, isNot(contains('La DGII aceptó')));
    });
  }
  test('la presentación histórica conserva el sentido sin anunciar al proveedor', () {
    expect(ecfCustomerMessage('Resultado DGII comunicado por DOSA.'),
        'Resultado DGII comunicado por el servicio fiscal.');
    expect(ecfCustomerMessage('DOSA_CONFIRMED_DGII_ACCEPTED'),
        'Referencia fiscal disponible para soporte');
    expect(ecfCustomerMessage('Rechazado por la DGII'), 'Rechazado por la DGII');
  });

  for (final correlated in [false, true]) {
    for (final safeCode in [null, 'UNKNOWN', 'ECF_DOSA_OBSERVED_ACCEPTED',
      'ECF_DOSA_OBSERVED_CONDITIONALLY_ACCEPTED']) {
      test('resultado registrado: correlación $correlated, código $safeCode', () {
        final outcome = EcfDosaDispatchOutcome.fromJson({
          'ok': true, 'result': 'FISCAL_RESULT_RECORDED',
          'correlated': correlated,
          'observation': {'providerOutcome': 'ACCEPTED', 'safeCode': safeCode},
        });
        final confirmed = correlated && safeCode != null && safeCode != 'UNKNOWN';
        expect(outcome.message.contains('La DGII aceptó'), confirmed);
        expect(outcome.message.contains('DOSA'), false);
        expect(EcfDosaDispatchOutcome.canRetryPost, false);
      });
    }
  }
  test('una observación aceptada sin resultado fiscal sigue en revisión', () {
    final outcome = EcfDosaDispatchOutcome.fromJson({
      'ok': true, 'result': 'STOPPED_REVIEW_REQUIRED', 'correlated': true,
      'observation': {'providerOutcome': 'ACCEPTED', 'safeCode': 'ECF_DOSA_OBSERVED_ACCEPTED'},
    });
    expect(outcome.message, contains('revisión'));
    expect(outcome.message, isNot(contains('La DGII aceptó')));
  });
}
