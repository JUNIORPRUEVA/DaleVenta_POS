import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'guardian_agent_log.dart';

/// Autorización de enrolamiento obtenida con la **sesión autenticada**.
///
/// Sustituye el código manual por equipo: la instalación pide al servidor una
/// autorización de vida corta (un código de un solo uso) usando el JWT de la
/// empresa. El servidor decide si la empresa puede auto-enrolarse; el cliente
/// nunca envía ni elige `companyId`.
///
/// Garantías:
/// - **Nunca lanza**: sin sesión, sin red o con error del servidor devuelve
///   `null` y el POS sigue funcionando igual.
/// - Sin sesión válida no hay petición: no se genera tráfico ni ruido offline.
/// - Espaciado mínimo entre intentos para no martillear el backend cuando la
///   instalación está offline o el despliegue aún no incluye a la empresa.
/// - No registra el código ni el token en los logs.
class GuardianAutoEnrollmentCodeSource {
  GuardianAutoEnrollmentCodeSource({
    required this.baseUrl,
    required this.tokenProvider,
    required this.installId,
    this.platform,
    this.appVersion,
    Dio? dio,
    this.timeout = const Duration(seconds: 6),
    this.minIntervalBetweenAttempts = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _dio = dio ?? Dio(BaseOptions(validateStatus: (_) => true)),
       _clock = clock ?? DateTime.now;

  static const String grantPath = '/guardian/installations/enrollment-grant';

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final String installId;
  final String? platform;
  final String? appVersion;
  final Duration timeout;

  /// Ventana mínima entre solicitudes (evita ráfagas y consumo de cuota).
  final Duration minIntervalBetweenAttempts;

  final Dio _dio;
  final DateTime Function() _clock;

  DateTime? _lastAttemptAt;
  bool _inFlight = false;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && installId.trim().isNotEmpty;

  /// Devuelve el código de un solo uso o `null` si no se puede obtener.
  Future<String?> read() async {
    if (!isConfigured) return null;

    // Una sola petición a la vez: dos flujos de arranque no duplican solicitudes.
    if (_inFlight) return null;

    final now = _clock();
    final last = _lastAttemptAt;
    if (last != null && now.difference(last) < minIntervalBetweenAttempts) {
      return null;
    }
    _lastAttemptAt = now;

    String? token;
    try {
      token = (await tokenProvider())?.trim();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) {
      // Offline sin sesión: no hay nada que autorizar todavía.
      return null;
    }

    _inFlight = true;
    final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _dio
          .post<dynamic>(
            '$normalizedBase$grantPath',
            data: <String, dynamic>{
              'installId': installId.trim(),
              if (platform != null && platform!.isNotEmpty)
                'platform': platform,
              if (appVersion != null && appVersion!.isNotEmpty)
                'appVersion': appVersion,
            },
            options: Options(
              validateStatus: (_) => true,
              headers: <String, String>{
                'content-type': 'application/json',
                'authorization': 'Bearer $token',
              },
            ),
          )
          .timeout(timeout);

      final status = response.statusCode ?? 0;
      final body = _asJsonMap(response.data);

      if (status < 200 || status >= 300) {
        // 403/404 son el resultado normal de una empresa aún no incluida en el
        // despliegue: se registra el motivo, nunca el token.
        unawaited(
          GuardianAgentLog.info(
            'auto-enrolamiento no disponible http=$status motivo=${body?['code'] ?? 'sin-codigo'}',
          ),
        );
        return null;
      }

      final code = (body?['code'] ?? '').toString().trim();
      if (code.isEmpty) {
        unawaited(
          GuardianAgentLog.warn(
            'auto-enrolamiento sin autorizacion utilizable',
          ),
        );
        return null;
      }
      unawaited(
        GuardianAgentLog.info(
          'autorizacion de enrolamiento obtenida (caduca ${body?['expiresAt'] ?? 'n/a'})',
        ),
      );
      return code;
    } catch (error) {
      // Sin red o servidor caído: se reintentará en el siguiente ciclo.
      unawaited(GuardianAgentLog.info('auto-enrolamiento fallido: $error'));
      return null;
    } finally {
      _inFlight = false;
    }
  }

  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
