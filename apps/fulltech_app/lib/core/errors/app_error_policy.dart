import 'api_exception.dart';
import 'user_facing_error.dart';

/// Central error policy.
///
/// Single place that decides:
/// - whether an incident is silent (recorded but never shown to the user);
/// - how a technical cause maps to a human message.
///
/// Presentation layers (overlay, notifications, screens) must consume this
/// policy instead of inspecting raw exceptions or HTTP status codes.
class AppErrorPolicy {
  const AppErrorPolicy._();

  /// Markers of a non-critical media/resource load failure.
  ///
  /// A missing product thumbnail, avatar, or logo is expected and must never
  /// interrupt the POS. The widget falls back to a local placeholder.
  static const List<String> _mediaFailureMarkers = <String>[
    'invalid statuscode',
    'httpexceptionwithstatus',
    'networkimageloadexception',
    'http request failed, statuscode',
    'failed to load network image',
    'image failed to load',
    'failed to load image',
    'resolving an image stream completer',
    'invalid image data',
    'codec failed',
    'unable to load asset',
    'image resource service',
  ];

  /// Markers of a transient connectivity failure.
  static const List<String> _transientNetworkMarkers = <String>[
    'clientexception with socketexception',
    'clientsocketexception',
    'socketexception',
    'sockettimeout',
    'timed out',
    'timeoutexception',
    'semaphore timeout',
    'connection refused',
    'connection reset',
    'connection failed',
    'connection timed out',
    'failed host lookup',
    'no address associated',
    'network is unreachable',
    'host unreachable',
    'operation timed out',
    'address is unreachable',
  ];

  /// True when the technical text describes a media/resource failure.
  static bool isMediaFailure(String technicalText) {
    return _containsAny(technicalText, _mediaFailureMarkers);
  }

  /// True when the technical text describes a transient network failure.
  static bool isTransientNetworkFailure(String technicalText) {
    return _containsAny(technicalText, _transientNetworkMarkers);
  }

  /// True when the incident must be recorded but never notified to the user.
  static bool isSilent(Object? error, String technicalText) {
    if (error is ApiException) {
      // Business/API errors are never silent; the caller decides presentation.
      return false;
    }
    return isMediaFailure(technicalText) ||
        isTransientNetworkFailure(technicalText);
  }

  /// Builds the human-facing description, honoring explicit copy overrides.
  ///
  /// [title], [message] and [helpText] are only applied when non-empty, so
  /// callers can enrich context without leaking technical text.
  static UserFacingError describe(
    Object? error, {
    String? title,
    String? message,
    String? helpText,
  }) {
    final base = UserFacingError.from(error ?? Object());
    return UserFacingError(
      title: _pick(title, base.title),
      message: _pick(message, base.message),
      helpText: _pick(helpText, base.helpText),
      autoRetry: base.autoRetry,
      kind: base.kind,
      silent: base.silent,
      recoverable: base.recoverable,
      retryable: base.retryable,
      actionLabel: base.actionLabel,
    );
  }

  static String _pick(String? override, String fallback) {
    final value = override?.trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }

  static bool _containsAny(String value, List<String> markers) {
    final normalized = value.toLowerCase();
    for (final marker in markers) {
      if (normalized.contains(marker)) return true;
    }
    return false;
  }
}
