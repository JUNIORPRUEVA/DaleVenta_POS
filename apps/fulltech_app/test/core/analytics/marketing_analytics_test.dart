import 'package:daleventa_pos/core/analytics/marketing_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MarketingAnalytics.debugResetForTests);

  test('landing view event is emitted once per app session', () {
    MarketingAnalytics.trackLandingViewed();
    MarketingAnalytics.trackLandingViewed();

    final events = MarketingAnalytics.debugEventsForTests;
    expect(events, hasLength(1));
    expect(events.single.name, 'ViewContent');
    expect(events.single.parameters, {
      'source_page': 'landing',
      'content_name': 'FullPOS Cloud landing',
    });
  });

  test('funnel events include only non-personal parameters', () {
    MarketingAnalytics.trackCreateAccountClick(
      sourcePage: 'landing',
      ctaName: 'Crear cuenta y probar gratis - hero',
    );
    MarketingAnalytics.trackRegistrationStarted(sourcePage: 'register');
    MarketingAnalytics.trackCompleteRegistration(sourcePage: 'register');
    MarketingAnalytics.trackTrialStarted(sourcePage: 'register');
    MarketingAnalytics.trackWhatsAppClicked(
      sourcePage: 'landing',
      ctaName: 'WhatsApp flotante',
    );

    final events = MarketingAnalytics.debugEventsForTests;
    expect(events.map((event) => event.name), [
      'ClickCreateAccount',
      'RegistrationStarted',
      'CompleteRegistration',
      'TrialStarted',
      'WhatsAppClicked',
    ]);

    for (final event in events) {
      expect(event.parameters.keys, isNot(contains('email')));
      expect(event.parameters.keys, isNot(contains('phone')));
      expect(event.parameters.keys, isNot(contains('password')));
      expect(event.parameters.keys, isNot(contains('name')));
      expect(
        event.parameters.keys,
        everyElement(anyOf('source_page', 'cta_name')),
      );
    }
  });
}
