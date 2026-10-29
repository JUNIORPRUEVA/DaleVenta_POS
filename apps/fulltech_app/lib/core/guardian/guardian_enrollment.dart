import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'guardian_agent_log.dart';
import 'guardian_install_credential_store.dart';

/// Enrolamiento de la instalación contra Guardian.
///
/// Canjea un **código de enrolamiento de un solo uso** por una credencial de
/// instalación (caduca y es revocable).
///
/// El código **nunca** se compila dentro del ejecutable: se obtiene en tiempo de
/// ejecución mediante `codeProvider` (archivo local o variable de entorno) y,
/// una vez canjeado, `onCodeConsumed` lo elimina para que no pueda reutilizarse.
///
/// Garantías:
/// - Nunca lanza: cualquier fallo devuelve `null` y el agente sigue funcionando
///   con el transporte anterior (o sin enviar nada).
/// - Timeout corto: no puede retrasar el arranque de la app.
/// - La credencial se guarda en almacenamiento seguro; el código no se persiste.
class GuardianEnrollmentService {
  GuardianEnrollmentService({
    required this.baseUrl,
    required this.store,
    required this.codeProvider,
    this.onCodeConsumed,
    Dio? dio,
    this.timeout = const Duration(seconds: 6),
  }) : _dio = dio ?? Dio(BaseOptions(validateStatus: (_) => true));

  final String baseUrl;
  final GuardianInstallCredentialStore store;

  /// Obtiene el código de un solo uso en tiempo de ejecución (`null` si no hay).
  final Future<String?> Function() codeProvider;

  /// Se invoca justo después de un canje correcto (p. ej. borrar el archivo).
  final Future<void> Function()? onCodeConsumed;

  final Duration timeout;
  final Dio _dio;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Devuelve una credencial válida (existente o recién emitida).
  Future<GuardianInstallCredential?> ensureCredential({
    required String installId,
    String? platform,
    String? appVersion,
    bool forceEnroll = false,
  }) async {
    if (!store.isSupported) return null;

    if (!forceEnroll) {
      final stored = await store.read();
      if (stored != null && stored.isValid() && stored.installId == installId) {
        return stored;
      }
    }

    if (!isConfigured) return null;

    final code = await _readCode();
    if (code == null) return null;

    final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _dio
          .post<dynamic>(
            '$normalizedBase/guardian/installations/enroll',
            data: <String, dynamic>{
              'code': code,
              'installId': installId,
              if (platform != null && platform.isNotEmpty) 'platform': platform,
              if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
            },
            options: Options(
              validateStatus: (_) => true,
              headers: const <String, String>{'content-type': 'application/json'},
            ),
          )
          .timeout(timeout);

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        // El servidor pudo consumir el código y rechazar la respuesta: dejar
        // rastro es obligatorio para no diagnosticar esto a ciegas.
        unawaited(GuardianAgentLog.warn(
          'enrolamiento rechazado http=$status motivo=${_describeBody(response.data)}',
        ));
        return null;
      }

      final data = _asJsonMap(response.data);
      if (data == null) {
        // Defecto corregido (fase 13): antes se exigía `Map` y, si el proxy
        // devolvía el cuerpo como texto, el código ya consumido se perdía sin
        // una sola traza en el log. Ahora se decodifica y se deja evidencia.
        unawaited(GuardianAgentLog.warn(
          'enrolamiento con cuerpo no interpretable: ${_describeBody(response.data)}',
        ));
        return null;
      }
      final credential = data['credential']?.toString() ?? '';
      final resolvedInstallId = data['installId']?.toString() ?? installId;
      final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
      if (credential.isEmpty || expiresAt == null) {
        unawaited(GuardianAgentLog.warn(
          'enrolamiento sin credencial utilizable (credential=${credential.isNotEmpty} expiresAt=${expiresAt != null})',
        ));
        return null;
      }

      final issued = GuardianInstallCredential(
        installId: resolvedInstallId,
        credential: credential,
        expiresAt: expiresAt.toUtc(),
      );
      await store.write(issued);

      // Verificación de persistencia: si el almacén seguro no guarda, el código
      // ya está consumido y la instalación se quedaría sin credencial al
      // reiniciar. Se usa la credencial en memoria y se deja constancia.
      final persisted = await store.read();
      if (persisted == null || persisted.credential != issued.credential) {
        unawaited(GuardianAgentLog.warn(
          'credencial emitida pero NO persistida: se usa solo en memoria (revisar almacén seguro)',
        ));
      }

      await _consumeCode();
      return issued;
    } catch (error) {
      // Guardian no disponible: no se reintenta en el arranque, no se bloquea.
      unawaited(GuardianAgentLog.warn('enrolamiento fallido: $error'));
      return null;
    }
  }

  /// Decodifica el cuerpo aunque llegue como texto (proxies, compresión).
  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is String) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Resumen del cuerpo para el log: nunca incluye la credencial.
  static String _describeBody(dynamic raw) {
    if (raw == null) return 'vacio';
    if (raw is Map) {
      final code = raw['code']?.toString() ?? '';
      final message = raw['message']?.toString() ?? '';
      if (code.isNotEmpty || message.isNotEmpty) return '${code.isEmpty ? 'sin_code' : code} ${message.isEmpty ? '' : message}'.trim();
      return 'mapa(${raw.length} claves)';
    }
    final text = raw.toString();
    return 'texto(${text.length}) ${text.length > 120 ? text.substring(0, 120) : text}';
  }

  Future<String?> _readCode() async {
    try {
      final value = await codeProvider();
      final trimmed = (value ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _consumeCode() async {
    try {
      await onCodeConsumed?.call();
    } catch (_) {
      // Best-effort: si no se puede borrar, el código sigue siendo de un uso.
    }
  }
}
