import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/ecf_status_presentation.dart';

/// La bandeja solo puede ser tan honesta como este mapeo: es la única capa que
/// traduce el estado persistido a algo que el usuario lee.
void main() {
  test('the known-status list mirrors the persisted enum', () {
    // Si el esquema crece, esta lista debe crecer con él: de lo contrario un
    // estado nuevo se mostraría como "no reconocido" en lugar de traducirse.
    expect(kEcfKnownStatuses.toSet(), hasLength(kEcfKnownStatuses.length));
    expect(kEcfKnownStatuses, hasLength(14));
  });

  test('every persisted status has a presentation', () {
    for (final status in kEcfKnownStatuses) {
      final presentation = presentEcfStatus(status);
      expect(presentation.recognized, isTrue, reason: status);
      expect(presentation.label, isNotEmpty, reason: status);
      expect(presentation.description, isNotEmpty, reason: status);
      expect(presentation.status, status, reason: status);
    }
  });

  test('only DGII_ACCEPTED is fiscally accepted', () {
    for (final status in kEcfKnownStatuses) {
      expect(
        presentEcfStatus(status).isFiscallyAccepted,
        status == 'DGII_ACCEPTED',
        reason: '$status no debe presentarse como aceptado fiscalmente',
      );
    }
  });

  test('a provider acceptance is never presented as a DGII acceptance', () {
    final provider = presentEcfStatus('PROVIDER_ACCEPTED');
    expect(provider.fiscal, EcfFiscalOutcome.pending);
    expect(provider.isFiscallyAccepted, isFalse);
    expect(provider.label, isNot(contains('DGII')));

    final dgii = presentEcfStatus('DGII_ACCEPTED');
    expect(dgii.fiscal, EcfFiscalOutcome.accepted);
    expect(dgii.isFiscallyAccepted, isTrue);
  });

  test('a document that was only prepared has no fiscal outcome', () {
    for (final status in const [
      'LOCAL_DRAFT',
      'LOCAL_VALIDATION_PENDING',
      'LOCAL_VALIDATED',
      'READY_TO_SEND',
      'SEND_PENDING',
      'SEND_IN_PROGRESS',
    ]) {
      expect(
        presentEcfStatus(status).fiscal,
        EcfFiscalOutcome.none,
        reason: status,
      );
    }
    expect(
      presentEcfStatus('LOCAL_VALIDATED').operative,
      EcfOperativePhase.readyToSend,
    );
  });

  test('an unknown result stays open and needs a human', () {
    final presentation = presentEcfStatus('UNKNOWN_RESULT');
    expect(presentation.fiscal, EcfFiscalOutcome.none);
    expect(presentation.tone, EcfStatusTone.warning);
    expect(presentation.isFiscallyAccepted, isFalse);
  });

  test('a status this version does not know is shown literally, never guessed', () {
    final presentation = presentEcfStatus('SOMETHING_NEW');
    expect(presentation.recognized, isFalse);
    expect(presentation.label, 'SOMETHING_NEW');
    expect(presentation.fiscal, EcfFiscalOutcome.none);
    expect(presentation.operative, EcfOperativePhase.humanReview);
    expect(presentation.isFiscallyAccepted, isFalse);
    expect(presentation.description.toLowerCase(), contains('no reconocido'));
  });

  test('an empty status does not become a fake label', () {
    final presentation = presentEcfStatus('');
    expect(presentation.recognized, isFalse);
    expect(presentation.label, 'Sin estado');
  });

  test('status matching ignores case and surrounding whitespace', () {
    expect(
      presentEcfStatus(' dgii_accepted ').fiscal,
      EcfFiscalOutcome.accepted,
    );
    expect(
      presentEcfStatus('local_validated').operative,
      EcfOperativePhase.readyToSend,
    );
  });

  test('the operational phase describes where the document actually is', () {
    expect(presentEcfStatus('LOCAL_DRAFT').operative, EcfOperativePhase.draft);
    expect(
      presentEcfStatus('SEND_IN_PROGRESS').operative,
      EcfOperativePhase.sending,
    );
    expect(
      presentEcfStatus('PROVIDER_ACCEPTED').operative,
      EcfOperativePhase.awaitingResult,
    );
    expect(
      presentEcfStatus('DGII_ACCEPTED').operative,
      EcfOperativePhase.settled,
    );
    expect(
      presentEcfStatus('DGII_REJECTED').operative,
      EcfOperativePhase.settled,
    );
    expect(
      presentEcfStatus('HUMAN_REVIEW_REQUIRED').operative,
      EcfOperativePhase.humanReview,
    );
    expect(
      presentEcfStatus('PROVIDER_REJECTED').operative,
      EcfOperativePhase.humanReview,
    );
    expect(
      presentEcfStatus('CANCELLED').operative,
      EcfOperativePhase.cancelled,
    );
  });

  test('the fiscal rejection is reported as rejected, not as pending', () {
    expect(
      presentEcfStatus('DGII_REJECTED').fiscal,
      EcfFiscalOutcome.rejected,
    );
    expect(
      presentEcfStatus('PROVIDER_REJECTED').fiscal,
      EcfFiscalOutcome.rejected,
    );
  });
}
