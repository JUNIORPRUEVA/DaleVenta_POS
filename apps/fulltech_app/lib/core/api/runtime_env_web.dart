import 'package:js/js.dart';

String? runtimeEnvGet(String key) {
  // Keep this file small and stable: runtime values are injected by `env.js`.
  // Values are injected by `env.js` (generated at container start).
  switch (key) {
    case 'API_BASE_URL':
      return _apiBaseUrl;
    case 'API_TIMEOUT_MS':
      return _apiTimeoutMs;
    case 'META_PIXEL_ID':
      return _metaPixelId;
    case 'MARKETING_ANALYTICS_DEBUG':
      return _marketingAnalyticsDebug;
    default:
      return null;
  }
}

@JS('API_BASE_URL')
external String? get _apiBaseUrl;

@JS('API_TIMEOUT_MS')
external String? get _apiTimeoutMs;

@JS('META_PIXEL_ID')
external String? get _metaPixelId;

@JS('MARKETING_ANALYTICS_DEBUG')
external String? get _marketingAnalyticsDebug;
