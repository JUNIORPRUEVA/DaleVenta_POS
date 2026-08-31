import 'dart:io';

import 'package:dio/dio.dart';

import '../errors/api_exception.dart';
import '../network/network_reachability.dart';

class ApiErrorMapper {
  static ApiException fromDio(
    DioException error, {
    required String fallbackMessage,
    Dio? dio,
  }) {
    final existing = error.error;
    if (existing is ApiException) {
      return existing;
    }

    final status = error.response?.statusCode;
    final method = error.requestOptions.method.toUpperCase();
    final uri = error.requestOptions.uri;
    final detail = _buildTechnicalDetail(error, dio: dio);
    final responseBody = _buildResponseBody(error.response?.data);
    final rawMessage = _extractMessage(error.response?.data, fallbackMessage);

    if (status != null) {
      final machineCode = _extractMachineCode(error.response?.data);
      return ApiException.detailed(
        message: _httpMessage(status, rawMessage, fallbackMessage),
        code: status,
        type: _httpType(status),
        displayCode: machineCode ?? status.toString(),
        technicalDetails: detail,
        responseBody: responseBody,
        method: method,
        uri: uri,
        retryable: status == 408 || status == 429 || status >= 500,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException.detailed(
          message:
              '$fallbackMessage. El servidor tardó demasiado en responder.',
          type: ApiErrorType.timeout,
          displayCode: 'NETWORK_TIMEOUT',
          technicalDetails: detail,
          method: method,
          uri: uri,
          retryable: true,
        );
      case DioExceptionType.badCertificate:
        return ApiException.detailed(
          message:
              '$fallbackMessage. La conexión segura con el servidor fue rechazada.',
          type: ApiErrorType.tls,
          displayCode: 'NETWORK_TLS',
          technicalDetails: detail,
          method: method,
          uri: uri,
          retryable: true,
        );
      case DioExceptionType.cancel:
        return ApiException.detailed(
          message: '$fallbackMessage. La petición fue cancelada.',
          type: ApiErrorType.cancelled,
          displayCode: 'REQUEST_CANCELLED',
          technicalDetails: detail,
          method: method,
          uri: uri,
          retryable: false,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        final networkType = _networkTypeFromDetail(error);
        return ApiException.detailed(
          message: _networkMessage(networkType, fallbackMessage),
          type: networkType,
          displayCode: _displayCodeForType(networkType),
          technicalDetails: detail,
          method: method,
          uri: uri,
          retryable: networkType != ApiErrorType.config,
        );
    }
  }

  static ApiException fromParse({
    required String fallbackMessage,
    required Uri uri,
    required String method,
    required Object error,
  }) {
    return ApiException.detailed(
      message:
          '$fallbackMessage. El servidor respondió con un formato inválido.',
      type: ApiErrorType.parse,
      displayCode: 'PARSE_ERROR',
      technicalDetails: error.toString(),
      method: method,
      uri: uri,
      retryable: false,
    );
  }

  static ApiException fromNetworkProbe({
    required NetworkProbeResult probe,
    required String fallbackMessage,
    required Uri uri,
    required String method,
  }) {
    switch (probe.status) {
      case NetworkProbeStatus.connected:
      case NetworkProbeStatus.unsupported:
        return ApiException.detailed(
          message: '$fallbackMessage. No se pudo establecer conexión.',
          type: ApiErrorType.network,
          displayCode: 'NETWORK_UNAVAILABLE',
          technicalDetails: probe.detail,
          uri: uri,
          method: method,
          retryable: true,
        );
      case NetworkProbeStatus.noInternet:
        return ApiException.detailed(
          message: '$fallbackMessage. No hay conexión a internet.',
          type: ApiErrorType.noInternet,
          displayCode: 'NETWORK_OFFLINE',
          technicalDetails: probe.detail,
          uri: uri,
          method: method,
          retryable: true,
        );
      case NetworkProbeStatus.dnsFailure:
        return ApiException.detailed(
          message:
              '$fallbackMessage. No se pudo resolver el host del servidor.',
          type: ApiErrorType.dns,
          displayCode: 'NETWORK_DNS',
          technicalDetails: probe.detail,
          uri: uri,
          method: method,
          retryable: true,
        );
      case NetworkProbeStatus.timeout:
        return ApiException.detailed(
          message: '$fallbackMessage. La verificación de red tardó demasiado.',
          type: ApiErrorType.timeout,
          displayCode: 'NETWORK_TIMEOUT',
          technicalDetails: probe.detail,
          uri: uri,
          method: method,
          retryable: true,
        );
    }
  }

  static ApiException? validateBaseUrl({
    required String rawBaseUrl,
    required Uri requestUri,
    required String method,
  }) {
    final baseUrl = rawBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return ApiException.detailed(
        message:
            'La API no está configurada. Define API_BASE_URL antes de usar la app.',
        type: ApiErrorType.config,
        displayCode: 'CONFIG_API_BASE_URL',
        technicalDetails: 'Dio baseUrl is empty.',
        uri: requestUri,
        method: method,
        retryable: false,
      );
    }

    final host = requestUri.host.trim().toLowerCase();
    const placeholders = <String>{
      'api.midominio.com',
      'midominio.com',
      'your-api.easypanel.host',
    };
    if (host.isEmpty ||
        placeholders.contains(host) ||
        host.contains('<your-api>')) {
      return ApiException.detailed(
        message:
            'La URL del backend no está configurada correctamente. Revisa API_BASE_URL.',
        type: ApiErrorType.config,
        displayCode: 'CONFIG_API_BASE_URL',
        technicalDetails: 'Invalid API host: $host (baseUrl=$baseUrl).',
        uri: requestUri,
        method: method,
        retryable: false,
      );
    }

    return null;
  }

  static bool shouldRetry(DioException error) {
    final mapped = fromDio(error, fallbackMessage: 'Request failed');
    return mapped.retryable;
  }

  static String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  static String? _extractMachineCode(dynamic data) {
    if (data is! Map) return null;
    final value = data['errorCode'] ?? data['code'];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _buildTechnicalDetail(DioException error, {Dio? dio}) {
    final parts = <String>[
      'dioType=${error.type}',
      if (error.message != null && error.message!.trim().isNotEmpty)
        'message=${error.message}',
      if (dio != null && dio.options.baseUrl.trim().isNotEmpty)
        'baseUrl=${dio.options.baseUrl}',
      if (error.error != null) 'error=${error.error}',
    ];
    return parts.join(' | ');
  }

  static String? _buildResponseBody(dynamic data) {
    if (data == null) return null;

    final raw = data is String ? data : data.toString();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    const maxChars = 6000;
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}\n…';
  }

  static ApiErrorType _httpType(int status) {
    if (status == 400) return ApiErrorType.badRequest;
    if (status == 401) return ApiErrorType.unauthorized;
    if (status == 403) return ApiErrorType.forbidden;
    if (status == 404) return ApiErrorType.notFound;
    if (status == 409) return ApiErrorType.conflict;
    if (status >= 500) return ApiErrorType.server;
    return ApiErrorType.unknown;
  }

  static String _httpMessage(int status, String rawMessage, String fallback) {
    if (status == 401) {
      return rawMessage.isNotEmpty
          ? rawMessage
          : 'Tu sesión expiró. Inicia sesión nuevamente.';
    }
    if (status == 404) {
      return rawMessage.isNotEmpty
          ? rawMessage
          : '$fallback no encontró el recurso solicitado.';
    }
    if (status >= 500) {
      return rawMessage.isNotEmpty
          ? rawMessage
          : '$fallback falló porque el backend devolvió un error interno.';
    }
    return rawMessage.isNotEmpty ? rawMessage : fallback;
  }

  static ApiErrorType _networkTypeFromDetail(DioException error) {
    final text = [
      error.message,
      error.error?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    if (error.error is HandshakeException ||
        text.contains('handshake') ||
        text.contains('certificate')) {
      return ApiErrorType.tls;
    }

    if (error.error is SocketException ||
        text.contains('failed host lookup') ||
        text.contains('name or service not known') ||
        text.contains('no address associated with hostname') ||
        text.contains('getaddrinfo')) {
      return ApiErrorType.dns;
    }

    return ApiErrorType.network;
  }

  static String _networkMessage(ApiErrorType type, String fallbackMessage) {
    switch (type) {
      case ApiErrorType.timeout:
        return '$fallbackMessage. El servidor tardó demasiado en responder.';
      case ApiErrorType.noInternet:
        return '$fallbackMessage. No hay conexión a internet.';
      case ApiErrorType.dns:
        return '$fallbackMessage. No se pudo resolver el dominio del backend.';
      case ApiErrorType.tls:
        return '$fallbackMessage. La conexión segura con el backend falló.';
      case ApiErrorType.network:
        return '$fallbackMessage. El backend no respondió o la conexión fue interrumpida.';
      case ApiErrorType.config:
        return '$fallbackMessage. La configuración del backend es inválida.';
      case ApiErrorType.badRequest:
      case ApiErrorType.unauthorized:
      case ApiErrorType.forbidden:
      case ApiErrorType.notFound:
      case ApiErrorType.conflict:
      case ApiErrorType.server:
      case ApiErrorType.parse:
      case ApiErrorType.cancelled:
      case ApiErrorType.unknown:
        return fallbackMessage;
    }
  }

  static String _displayCodeForType(ApiErrorType type) {
    switch (type) {
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
        return 'CONFIG_API_BASE_URL';
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
      case ApiErrorType.parse:
        return 'PARSE_ERROR';
      case ApiErrorType.cancelled:
        return 'REQUEST_CANCELLED';
      case ApiErrorType.unknown:
        return 'UNKNOWN';
    }
  }
}
