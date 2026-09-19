import 'package:flutter/foundation.dart';

import '../api/env.dart';
import 'marketing_analytics_bridge.dart';

class MarketingAnalyticsEvent {
  const MarketingAnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, String> parameters;
}

class MarketingAnalytics {
  static final List<MarketingAnalyticsEvent> _debugEvents = [];
  static bool _landingViewTracked = false;

  static List<MarketingAnalyticsEvent> get debugEventsForTests =>
      List.unmodifiable(_debugEvents);

  static void debugResetForTests() {
    _debugEvents.clear();
    _landingViewTracked = false;
  }

  static void trackLandingViewed() {
    if (_landingViewTracked) return;
    _landingViewTracked = true;
    _track(
      'ViewContent',
      parameters: const {
        'source_page': 'landing',
        'content_name': 'FullPOS Cloud landing',
      },
    );
  }

  static void trackCreateAccountClick({
    required String sourcePage,
    required String ctaName,
  }) {
    _track(
      'ClickCreateAccount',
      parameters: {'source_page': sourcePage, 'cta_name': ctaName},
    );
  }

  static void trackRegistrationStarted({required String sourcePage}) {
    _track('RegistrationStarted', parameters: {'source_page': sourcePage});
  }

  static void trackCompleteRegistration({required String sourcePage}) {
    _track('CompleteRegistration', parameters: {'source_page': sourcePage});
  }

  static void trackTrialStarted({required String sourcePage}) {
    _track('TrialStarted', parameters: {'source_page': sourcePage});
  }

  static void trackWhatsAppClicked({
    required String sourcePage,
    required String ctaName,
  }) {
    _track(
      'WhatsAppClicked',
      parameters: {'source_page': sourcePage, 'cta_name': ctaName},
    );
  }

  static void _track(
    String eventName, {
    required Map<String, String> parameters,
  }) {
    final safeParameters = Map<String, String>.unmodifiable(parameters);
    assert(() {
      _debugEvents.add(MarketingAnalyticsEvent(eventName, safeParameters));
      return true;
    }());

    final pixelId = Env.metaPixelId;
    final debugEnabled = Env.marketingAnalyticsDebugEnabled;
    if (debugEnabled) {
      debugPrint('[marketing_analytics] $eventName $safeParameters');
    }
    if (pixelId == null) return;

    trackMetaPixelEvent(
      pixelId: pixelId,
      eventName: eventName,
      parameters: safeParameters,
      debugEnabled: debugEnabled,
    );
  }
}
