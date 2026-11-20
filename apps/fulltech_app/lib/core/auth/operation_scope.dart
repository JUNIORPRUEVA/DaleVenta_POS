import 'dart:async';
import 'dart:convert';

/// Pins background requests (including authentication retries) to their outbox
/// owner. This is a client guard; the server still verifies the JWT and tenant.
class OperationScope {
  const OperationScope(this.companyId, this.userId);
  final String companyId;
  final String userId;
  static const _key = #fullposOperationScope;
  static OperationScope? get current => Zone.current[_key] as OperationScope?;

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: this});

  bool matchesToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map &&
          claims['sub'] == userId &&
          claims['companyId'] == companyId;
    } catch (_) {
      return false;
    }
  }
}
