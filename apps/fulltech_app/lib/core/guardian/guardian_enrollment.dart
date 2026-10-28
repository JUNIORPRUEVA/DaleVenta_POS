import 'package:dio/dio.dart';

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
      if (status < 200 || status >= 300) return null;

      final data = response.data;
      if (data is! Map) return null;
      final credential = data['credential']?.toString() ?? '';
      final resolvedInstallId = data['installId']?.toString() ?? installId;
      final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
      if (credential.isEmpty || expiresAt == null) return null;

      final issued = GuardianInstallCredential(
        installId: resolvedInstallId,
        credential: credential,
        expiresAt: expiresAt.toUtc(),
      );
      await store.write(issued);
      await _consumeCode();
      return issued;
    } catch (_) {
      // Guardian no disponible: no se reintenta en el arranque, no se bloquea.
      return null;
    }
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
