import 'dart:convert';

/// Routing hint only. The API still verifies the JWT and company authorization.
String? guardianCompanyFromToken(String? token) {
  try {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return null;
    final data = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final company = data is Map ? data['companyId'] : null;
    return company is String && company.isNotEmpty ? company : null;
  } catch (_) {
    return null;
  }
}
