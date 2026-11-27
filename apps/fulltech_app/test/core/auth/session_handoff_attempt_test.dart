import 'package:daleventa_pos/core/auth/session_handoff_attempt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('regression: nullable Uri.replace parameters keep the consumed ticket', () {
    final original = Uri.parse('https://example.invalid/home?handoff=fixture');
    // Reproduces the previous cleanup implementation, without a live ticket.
    expect(original.replace(queryParameters: null).queryParameters['handoff'], 'fixture');
    expect(sessionHandoffCleanPath(original), '/home');
  });
  test('ticket cleanup preserves other route parameters and fragments', () {
    final cleaned = sessionHandoffCleanPath(Uri.parse(
      'https://example.invalid/home?handoff=fixture&view=welcome#help'));
    expect(cleaned, '/home?view=welcome#help');
    expect(sessionHandoffCleanPath(Uri.parse('https://example.invalid/home')), '/home');
  });
  test('strips the ticket, clears the old identity and stores the new one before entering', () async {
    final steps = <String>[];
    final ready = await completeSessionHandoff(
      stripTicket: () => steps.add('strip'),
      clearSession: () async { steps.add('clear'); },
      exchange: () async { steps.add('exchange'); },
      sessionIsStored: () async { steps.add('stored'); return true; },
    );
    expect(ready, true); expect(steps, ['strip','clear','exchange','stored']);
  });
  for (final failure in ['expired', 'network', 'partial-write']) {
    test('$failure never retries a one-use ticket or leaves a previous/partial identity', () async {
      var exchanges=0, clears=0;
      final ready=await completeSessionHandoff(
        stripTicket: () {}, clearSession: () async {clears++;},
        exchange: () async {exchanges++; if(failure!='partial-write') throw StateError(failure);},
        sessionIsStored: () async => false,
      );
      expect(ready,false);expect(exchanges,1);expect(clears,2);
    });
  }
  test('storage cleanup failure cannot turn failed access into a success', () async {
    var exchanges=0;
    expect(await completeSessionHandoff(stripTicket:(){},clearSession:() async => throw StateError('storage'),
      exchange:() async {exchanges++;},sessionIsStored:() async=>true),false);
    expect(exchanges,0);
  });
}
