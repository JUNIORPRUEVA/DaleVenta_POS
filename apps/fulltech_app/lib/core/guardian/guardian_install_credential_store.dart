import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credencial de instalación emitida por Guardian.
///
/// Se obtiene canjeando un código de enrolamiento (una sola vez) y **no** es un
/// JWT de usuario: identifica a la instalación, caduca y es revocable.
@immutable
class GuardianInstallCredential {
  const GuardianInstallCredential({
    required this.installId,
    required this.credential,
    required this.expiresAt,
  });

  final String installId;
  final String credential;
  final DateTime expiresAt;

  bool isValid({Duration margin = const Duration(days: 1)}) {
    return credential.isNotEmpty &&
        installId.isNotEmpty &&
        expiresAt.isAfter(DateTime.now().add(margin));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'installId': installId,
        'credential': credential,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  static GuardianInstallCredential? fromJson(String raw) {
    try {
      final decoded = _decode(raw);
      if (decoded == null) return null;
      final installId = decoded['installId']?.toString() ?? '';
      final credential = decoded['credential']?.toString() ?? '';
      final expiresAt = DateTime.tryParse(decoded['expiresAt']?.toString() ?? '');
      if (installId.isEmpty || credential.isEmpty || expiresAt == null) return null;
      return GuardianInstallCredential(
        installId: installId,
        credential: credential,
        expiresAt: expiresAt.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final dynamic value = jsonDecode(raw);
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Almacén seguro de la credencial de instalación.
///
/// - Nunca escribe en la base de datos de ventas ni en `shared_preferences`.
/// - En plataformas sin almacén seguro (web) devuelve `null`: el agente cae al
///   transporte con sesión de usuario, como hasta ahora.
/// - Cualquier fallo se trata como "sin credencial" (fail-open).
class GuardianInstallCredentialStore {
  GuardianInstallCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'daleventas.guardian.install_credential.v1';

  final FlutterSecureStorage _storage;

  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<GuardianInstallCredential?> read() async {
    if (!isSupported) return null;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      return GuardianInstallCredential.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(GuardianInstallCredential credential) async {
    if (!isSupported) return;
    try {
      await _storage.write(key: _key, value: jsonEncode(credential.toJson()));
    } catch (_) {
      // Sin almacén seguro no hay credencial persistida: se reintentará.
    }
  }

  Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Ignorado a propósito.
    }
  }
}
