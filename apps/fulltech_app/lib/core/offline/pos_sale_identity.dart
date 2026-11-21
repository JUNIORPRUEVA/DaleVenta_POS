import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Stable across retries/restarts; independent of cart contents and prices.
String? posSaleRequestId({required String? companyId, required String? userId,
  required String? deviceId, required String? ticketId}) {
  final values = [companyId, userId, deviceId, ticketId].map((v) => v?.trim() ?? '').toList();
  if (values.any((v) => v.isEmpty) || values.last.length > 128) return null;
  return 'pos_${sha256.convert(utf8.encode(jsonEncode(values)))}';
}
