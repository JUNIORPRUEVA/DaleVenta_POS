import 'api_exception.dart';

/// Returns a message that is safe to display to an end user.
///
/// Never returns raw exception text, stack traces, endpoints, HTTP status
/// codes, or library names. Screens must use this instead of interpolating an
/// exception (`'No se pudo guardar: $e'`).
String userSafeErrorMessage(Object? error, {required String fallback}) {
  if (error is ApiException) {
    final message = error.message.trim();
    if (message.isNotEmpty && !looksTechnical(message)) {
      return message;
    }
  }
  return fallback;
}

/// Heuristic guard that detects technical text that must never reach the UI.
bool looksTechnical(String value) {
  final normalized = value.toLowerCase();
  for (final marker in _technicalMarkers) {
    if (normalized.contains(marker)) return true;
  }
  if (normalized.contains('http://') || normalized.contains('https://')) {
    return true;
  }
  return _containsStackTrace(normalized);
}

const List<String> _technicalMarkers = <String>[
  'exception',
  'stack trace',
  'stacktrace',
  'dioerror',
  'dioexception',
  'socketexception',
  'httpexception',
  'formatexception',
  'prisma',
  'nestjs',
  'statuscode',
  'status code',
  'internal server error',
  'null check operator',
  'type \'',
  'instance of',
  'sqlstate',
  'econnrefused',
  'uri=',
  '/uploads/',
];

bool _containsStackTrace(String value) {
  // Typical stack frames: "#0      Foo.bar (package:x/y.dart:10:2)".
  for (var i = 0; i < value.length - 2; i++) {
    if (value[i] == '#' &&
        value[i + 1].codeUnitAt(0) >= 0x30 &&
        value[i + 1].codeUnitAt(0) <= 0x39 &&
        (value[i + 2] == ' ' || value[i + 2] == '\t')) {
      return true;
    }
  }
  return value.contains('.dart:');
}
