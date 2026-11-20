import 'package:http_parser/http_parser.dart';

/// Retry-After accepts either delay-seconds or an HTTP date (RFC 9110).
Duration? parseRetryAfter(String? value, {DateTime? now}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final seconds = int.tryParse(text);
  if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
  try {
    final delay = parseHttpDate(
      text,
    ).difference((now ?? DateTime.now()).toUtc());
    return delay.isNegative ? Duration.zero : delay;
  } on FormatException {
    return null;
  }
}
