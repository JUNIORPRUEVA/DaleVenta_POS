enum ApiErrorType {
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  timeout,
  noInternet,
  dns,
  tls,
  network,
  server,
  parse,
  cancelled,
  config,
  unknown,
}

class ApiException implements Exception {
  final String message;
  final int? code;
  final ApiErrorType type;
  final String displayCode;
  final String? technicalDetails;
  final String? responseBody;
  final Uri? uri;
  final String? method;
  final bool retryable;
  final Duration? retryAfter;

  ApiException(String message, [int? code])
    : this.detailed(
        message: message,
        code: code,
        type: _inferType(code, message),
        displayCode: _inferDisplayCode(code, message),
        retryable: _inferRetryable(code, message),
      );

  const ApiException.detailed({
    required this.message,
    this.code,
    this.type = ApiErrorType.unknown,
    this.displayCode = 'UNKNOWN',
    this.technicalDetails,
    this.responseBody,
    this.uri,
    this.method,
    this.retryable = false,
    this.retryAfter,
  });

  bool get isNetworkError {
    return type == ApiErrorType.timeout ||
        type == ApiErrorType.noInternet ||
        type == ApiErrorType.dns ||
        type == ApiErrorType.tls ||
        type == ApiErrorType.network;
  }

  bool get isConfigError => type == ApiErrorType.config;

  String get debugSummary {
    final parts = <String>[
      'code=$displayCode',
      'type=$type',
      if (method != null && method!.trim().isNotEmpty) 'method=$method',
      if (uri != null) 'uri=$uri',
      if (responseBody != null && responseBody!.trim().isNotEmpty)
        'response=$responseBody',
      if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
        'detail=$technicalDetails',
    ];
    return parts.join(' | ');
  }

  @override
  String toString() => 'ApiException: $message (code: $displayCode)';

  static ApiErrorType _inferType(int? code, String message) {
    if (code != null) {
      if (code == 400 || code == 422) return ApiErrorType.badRequest;
      if (code == 401) return ApiErrorType.unauthorized;
      if (code == 403) return ApiErrorType.forbidden;
      if (code == 404) return ApiErrorType.notFound;
      if (code == 409) return ApiErrorType.conflict;
      if (code >= 500) return ApiErrorType.server;
      return ApiErrorType.unknown;
    }

    final normalized = message.trim().toUpperCase();
    if (normalized.contains('[TIMEOUT]')) return ApiErrorType.timeout;
    if (normalized.contains('[NETWORK]')) return ApiErrorType.network;
    if (normalized.contains('SIN INTERNET')) return ApiErrorType.noInternet;
    if (normalized.contains('DNS')) return ApiErrorType.dns;
    if (normalized.contains('CERTIFIC') || normalized.contains('TLS')) {
      return ApiErrorType.tls;
    }
    if (normalized.contains('CONFIG')) return ApiErrorType.config;
    return ApiErrorType.unknown;
  }

  static String _inferDisplayCode(int? code, String message) {
    if (code != null) return code.toString();
    switch (_inferType(code, message)) {
      case ApiErrorType.timeout:
        return 'NETWORK_TIMEOUT';
      case ApiErrorType.noInternet:
        return 'NETWORK_OFFLINE';
      case ApiErrorType.dns:
        return 'NETWORK_DNS';
      case ApiErrorType.tls:
        return 'NETWORK_TLS';
      case ApiErrorType.network:
        return 'NETWORK_UNAVAILABLE';
      case ApiErrorType.config:
        return 'CONFIG_ERROR';
      case ApiErrorType.parse:
        return 'PARSE_ERROR';
      case ApiErrorType.cancelled:
        return 'REQUEST_CANCELLED';
      case ApiErrorType.badRequest:
        return '400';
      case ApiErrorType.unauthorized:
        return '401';
      case ApiErrorType.forbidden:
        return '403';
      case ApiErrorType.notFound:
        return '404';
      case ApiErrorType.conflict:
        return '409';
      case ApiErrorType.server:
        return 'SERVER_ERROR';
      case ApiErrorType.unknown:
        return 'UNKNOWN';
    }
  }

  static bool _inferRetryable(int? code, String message) {
    if (code != null) {
      return code == 408 || code == 429 || code >= 500;
    }
    final type = _inferType(code, message);
    return type == ApiErrorType.timeout ||
        type == ApiErrorType.noInternet ||
        type == ApiErrorType.dns ||
        type == ApiErrorType.tls ||
        type == ApiErrorType.network;
  }
}
