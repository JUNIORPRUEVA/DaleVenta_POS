import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Stable across retries/restarts; independent of cart contents and prices.
String? posSaleRequestId({required String? companyId, required String? userId,
  required String? deviceId, required String? ticketId, int attemptRevision = 0}) {
  final values = [companyId, userId, deviceId, ticketId].map((v) => v?.trim() ?? '').toList();
  if (values.any((v) => v.isEmpty) || values.last.length > 128 || attemptRevision < 0) return null;
  // Revision zero preserves every existing ticket's idempotency key.
  final identity = <Object>[...values, if (attemptRevision > 0) attemptRevision];
  return 'pos_${sha256.convert(utf8.encode(jsonEncode(identity)))}';
}

int posSaleAttemptRevision(Map<String, dynamic> payload) {
  final value = payload['posAttemptRevision'];
  if (value == null) return 0;
  if (value is! int || value < 0) throw StateError('La identidad del cobro requiere revisión.');
  return value;
}
