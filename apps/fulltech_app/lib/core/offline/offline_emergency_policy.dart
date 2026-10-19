import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineEmergencyDecision {
  const OfflineEmergencyDecision._({
    required this.allowed,
    required this.reason,
    required this.message,
    this.lastServerValidationUtc,
    this.elapsedSinceValidation,
  });

  factory OfflineEmergencyDecision.allowed({
    required DateTime lastServerValidationUtc,
    required Duration elapsedSinceValidation,
  }) {
    return OfflineEmergencyDecision._(
      allowed: true,
      reason: OfflineEmergencyBlockReason.none,
      message: '',
      lastServerValidationUtc: lastServerValidationUtc,
      elapsedSinceValidation: elapsedSinceValidation,
    );
  }

  factory OfflineEmergencyDecision.blocked({
    required OfflineEmergencyBlockReason reason,
    required String message,
    DateTime? lastServerValidationUtc,
    Duration? elapsedSinceValidation,
  }) {
    return OfflineEmergencyDecision._(
      allowed: false,
      reason: reason,
      message: message,
      lastServerValidationUtc: lastServerValidationUtc,
      elapsedSinceValidation: elapsedSinceValidation,
    );
  }

  final bool allowed;
  final OfflineEmergencyBlockReason reason;
  final String message;
  final DateTime? lastServerValidationUtc;
  final Duration? elapsedSinceValidation;
}

enum OfflineEmergencyBlockReason {
  none,
  missingScope,
  missingValidation,
  expired,
  clockRollback,
  corruptedValidation,
}

class OfflineEmergencyPolicy {
  OfflineEmergencyPolicy({
    Future<SharedPreferences> Function()? prefsProvider,
    OfflineEmergencySealStore? sealStore,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
       _sealStore = sealStore ?? const FlutterSecureOfflineEmergencySealStore();

  static const maxOfflineDuration = Duration(hours: 48);
  static const clockRollbackTolerance = Duration(minutes: 5);
  static const serverDateHeader = 'date';
  static const policyVersion = 'offline-safe-48h.v1';
  static const _prefix = 'offline_emergency.v1';
  static const _sealKey = '$_prefix.seal_key';

  final Future<SharedPreferences> Function() _prefsProvider;
  final OfflineEmergencySealStore _sealStore;

  static bool supportsAdvancedProtocol(dynamic data) {
    if (data is! Map || data['capabilities'] is! Map) return false;
    final capabilities = data['capabilities'] as Map;
    return capabilities['protocolVersion'] == 2 &&
        capabilities['minimumClientProtocol'] == 2 &&
        capabilities['productOperationId'] == true &&
        capabilities['productPayloadHash'] == true &&
        capabilities['inventoryOperationId'] == true &&
        capabilities['inventoryPayloadHash'] == true &&
        capabilities['stableProductIdentity'] == true &&
        capabilities['dependentSync'] == true;
  }

  Future<void> recordServerValidationFromHeaders({
    required Headers headers,
    required String companyId,
    required String userId,
    required String deviceFingerprint,
    DateTime? observedAtUtc,
  }) async {
    final rawServerDate = headers.value(serverDateHeader);
    if (rawServerDate == null || rawServerDate.trim().isEmpty) return;

    final serverUtc =
        DateTime.tryParse(rawServerDate)?.toUtc() ??
        _tryParseHttpDate(rawServerDate);
    if (serverUtc == null) return;

    await recordServerValidation(
      companyId: companyId,
      userId: userId,
      deviceFingerprint: deviceFingerprint,
      serverUtc: serverUtc,
      validUntilUtc: serverUtc.add(maxOfflineDuration),
      observedAtUtc: observedAtUtc,
    );
  }

  Future<void> recordAuthorizationResponse({
    required Map<String, dynamic> data,
    required String companyId,
    required String userId,
    required String deviceFingerprint,
    DateTime? observedAtUtc,
  }) async {
    if (data['authorized'] != true) return;
    if ((data['policyVersion'] ?? '').toString() != policyVersion) return;
    if ((data['companyId'] ?? '').toString().trim() != companyId.trim()) {
      return;
    }
    if ((data['userId'] ?? '').toString().trim() != userId.trim()) return;
    if ((data['deviceFingerprint'] ?? '').toString().trim() !=
        deviceFingerprint.trim()) {
      return;
    }

    final serverUtc = DateTime.tryParse(
      (data['serverUtc'] ?? '').toString(),
    )?.toUtc();
    final validUntilUtc = DateTime.tryParse(
      (data['validUntilUtc'] ?? '').toString(),
    )?.toUtc();
    if (serverUtc == null || validUntilUtc == null) return;
    if (validUntilUtc.isBefore(serverUtc)) return;
    if (validUntilUtc.difference(serverUtc) > maxOfflineDuration) return;

    await recordServerValidation(
      companyId: companyId,
      userId: userId,
      deviceFingerprint: deviceFingerprint,
      serverUtc: serverUtc,
      validUntilUtc: validUntilUtc,
      observedAtUtc: observedAtUtc,
      advancedProtocolVerified: supportsAdvancedProtocol(data),
      allowedOperations:
          (data['allowedOperations'] as List?)?.whereType<String>().toList() ??
          const ['sales.create'],
    );
  }

  Future<void> recordServerValidation({
    required String companyId,
    required String userId,
    required String deviceFingerprint,
    required DateTime serverUtc,
    DateTime? validUntilUtc,
    DateTime? observedAtUtc,
    List<String> allowedOperations = const ['sales.create'],
    bool advancedProtocolVerified = false,
  }) async {
    final normalizedCompanyId = companyId.trim();
    final normalizedUserId = userId.trim();
    final normalizedDeviceFingerprint = deviceFingerprint.trim();
    if (normalizedCompanyId.isEmpty ||
        normalizedUserId.isEmpty ||
        normalizedDeviceFingerprint.isEmpty) {
      return;
    }

    final server = serverUtc.toUtc();
    final snapshot = _OfflineEmergencySnapshot(
      policyVersion: policyVersion,
      companyId: normalizedCompanyId,
      userId: normalizedUserId,
      deviceFingerprint: normalizedDeviceFingerprint,
      serverUtc: server,
      validUntilUtc: (validUntilUtc ?? server.add(maxOfflineDuration)).toUtc(),
      observedDeviceUtc: (observedAtUtc ?? DateTime.now().toUtc()).toUtc(),
      allowedOperations: allowedOperations,
      advancedProtocolVerified: advancedProtocolVerified,
    );
    final prefs = await _prefsProvider();
    final key = _key(normalizedCompanyId, normalizedUserId);
    final raw = jsonEncode(snapshot.toJson());
    await prefs.setString(key, raw);
    await _writeSealSafe(key, raw);
  }

  Future<OfflineEmergencyDecision> canStartOfflineSale({
    required String companyId,
    required String userId,
    required String deviceFingerprint,
    DateTime? nowUtc,
  }) async {
    final normalizedCompanyId = companyId.trim();
    final normalizedUserId = userId.trim();
    final normalizedDeviceFingerprint = deviceFingerprint.trim();
    if (normalizedCompanyId.isEmpty ||
        normalizedUserId.isEmpty ||
        normalizedDeviceFingerprint.isEmpty) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.missingScope,
        message:
            'No pudimos comprobar tu usuario y empresa en este equipo. Conéctate a internet y verifica tu sesión para poder vender sin conexión.',
      );
    }

    final prefs = await _prefsProvider();
    final key = _key(normalizedCompanyId, normalizedUserId);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.missingValidation,
        message:
            'Conecta este equipo a internet y abre la empresa para autorizar las ventas sin conexión.',
      );
    }

    final sealValid = await _isSealValid(key, raw);
    if (!sealValid) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.corruptedValidation,
        message:
            'Necesitamos renovar el permiso para vender sin internet en este equipo. Conéctalo a internet y abre la empresa.',
      );
    }

    final snapshot = _OfflineEmergencySnapshot.tryDecode(raw);
    if (snapshot == null) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.corruptedValidation,
        message:
            'Necesitamos renovar el permiso para vender sin internet en este equipo. Conéctalo a internet y abre la empresa.',
      );
    }
    if (snapshot.policyVersion != policyVersion ||
        snapshot.companyId != normalizedCompanyId ||
        snapshot.userId != normalizedUserId ||
        snapshot.deviceFingerprint != normalizedDeviceFingerprint) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.missingValidation,
        message:
            'El permiso para vender sin internet no corresponde al usuario o empresa actual. Conéctate a internet y verifica la sesión de esta empresa.',
      );
    }

    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final elapsed = now.difference(snapshot.observedDeviceUtc);
    if (elapsed < -clockRollbackTolerance) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.clockRollback,
        message:
            'La fecha o la hora de este equipo cambió. Comprueba que sean correctas y conéctate a internet para volver a autorizar las ventas sin conexión.',
        lastServerValidationUtc: snapshot.serverUtc,
        elapsedSinceValidation: elapsed,
      );
    }

    final estimatedServerNow = snapshot.serverUtc.add(elapsed);
    if (elapsed > maxOfflineDuration ||
        estimatedServerNow.isAfter(snapshot.validUntilUtc)) {
      return OfflineEmergencyDecision.blocked(
        reason: OfflineEmergencyBlockReason.expired,
        message:
            'Venció el permiso para vender sin internet (máximo 48 horas). Conecta este equipo a internet y abre la empresa antes de registrar nuevas ventas.',
        lastServerValidationUtc: snapshot.serverUtc,
        elapsedSinceValidation: elapsed,
      );
    }

    return OfflineEmergencyDecision.allowed(
      lastServerValidationUtc: snapshot.serverUtc,
      elapsedSinceValidation: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  Future<void> assertOperationAllowed({
    required String companyId,
    required String userId,
    required String deviceFingerprint,
    required String operation,
  }) async {
    final decision = await canStartOfflineSale(
      companyId: companyId,
      userId: userId,
      deviceFingerprint: deviceFingerprint,
    );
    if (!decision.allowed) throw StateError(decision.message);
    final prefs = await _prefsProvider();
    final raw = prefs.getString(_key(companyId.trim(), userId.trim()));
    final snapshot = raw == null
        ? null
        : _OfflineEmergencySnapshot.tryDecode(raw);
    if (snapshot == null || !snapshot.allowedOperations.contains(operation)) {
      throw StateError(
        'Tu permiso actual para trabajar sin internet no incluye esta operación. Conecta este equipo y consulta al administrador de la empresa.',
      );
    }
    if ((operation == 'catalog.products.create' ||
            operation == 'catalog.products.stock') &&
        !snapshot.advancedProtocolVerified) {
      throw StateError(
        'Esta función necesita una actualización del servicio para funcionar sin internet. Conéctate para comprobar su compatibilidad.',
      );
    }
  }

  Future<void> disableAdvancedOperations({
    required String companyId,
    required String userId,
  }) async {
    final prefs = await _prefsProvider();
    final key = _key(companyId.trim(), userId.trim());
    final raw = prefs.getString(key);
    if (raw == null || !await _isSealValid(key, raw)) return;
    final snapshot = _OfflineEmergencySnapshot.tryDecode(raw);
    if (snapshot == null) return;
    final updated = snapshot.toJson()..['advancedProtocolVerified'] = false;
    final encoded = jsonEncode(updated);
    await prefs.setString(key, encoded);
    await _writeSealSafe(key, encoded);
  }

  String _key(String companyId, String userId) {
    return '$_prefix.company:$companyId.user:$userId';
  }

  String _sealStorageKey(String authorizationKey) {
    return '$_prefix.seal.$authorizationKey';
  }

  Future<void> _writeSealSafe(String authorizationKey, String raw) async {
    try {
      final secret = await _readOrCreateSealSecret();
      final seal = _seal(raw, secret);
      await _sealStore.write(_sealStorageKey(authorizationKey), seal);
    } catch (_) {
      // Secure storage may be unavailable on tests or unsupported platforms.
      // The policy still validates scope and expiry, but without tamper seal.
    }
  }

  Future<bool> _isSealValid(String authorizationKey, String raw) async {
    try {
      final expectedSeal = await _sealStore.read(
        _sealStorageKey(authorizationKey),
      );
      if (expectedSeal == null || expectedSeal.trim().isEmpty) return true;
      final secret = await _sealStore.read(_sealKey);
      if (secret == null || secret.trim().isEmpty) return false;
      return _constantTimeEquals(expectedSeal, _seal(raw, secret));
    } catch (_) {
      return true;
    }
  }

  Future<String> _readOrCreateSealSecret() async {
    final existing = await _sealStore.read(_sealKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final secret = base64UrlEncode(bytes);
    await _sealStore.write(_sealKey, secret);
    return secret;
  }

  String _seal(String raw, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(raw)).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i += 1) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  DateTime? _tryParseHttpDate(String raw) {
    try {
      return parseHttpDate(raw).toUtc();
    } catch (_) {
      return null;
    }
  }
}

abstract class OfflineEmergencySealStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class FlutterSecureOfflineEmergencySealStore
    implements OfflineEmergencySealStore {
  const FlutterSecureOfflineEmergencySealStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class _OfflineEmergencySnapshot {
  const _OfflineEmergencySnapshot({
    required this.policyVersion,
    required this.companyId,
    required this.userId,
    required this.deviceFingerprint,
    required this.serverUtc,
    required this.validUntilUtc,
    required this.observedDeviceUtc,
    this.allowedOperations = const ['sales.create'],
    this.advancedProtocolVerified = false,
  });

  final String policyVersion;
  final String companyId;
  final String userId;
  final String deviceFingerprint;
  final DateTime serverUtc;
  final DateTime validUntilUtc;
  final DateTime observedDeviceUtc;
  final List<String> allowedOperations;
  final bool advancedProtocolVerified;

  Map<String, dynamic> toJson() {
    return {
      'policyVersion': policyVersion,
      'companyId': companyId,
      'userId': userId,
      'deviceFingerprint': deviceFingerprint,
      'serverUtc': serverUtc.toIso8601String(),
      'validUntilUtc': validUntilUtc.toIso8601String(),
      'observedDeviceUtc': observedDeviceUtc.toIso8601String(),
      'allowedOperations': allowedOperations,
      'advancedProtocolVerified': advancedProtocolVerified,
    };
  }

  static _OfflineEmergencySnapshot? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final policyVersion = (decoded['policyVersion'] ?? '').toString();
      final companyId = (decoded['companyId'] ?? '').toString().trim();
      final userId = (decoded['userId'] ?? '').toString().trim();
      final deviceFingerprint = (decoded['deviceFingerprint'] ?? '')
          .toString()
          .trim();
      final serverUtc = DateTime.tryParse(
        decoded['serverUtc']?.toString() ?? '',
      );
      final validUntilUtc = DateTime.tryParse(
        decoded['validUntilUtc']?.toString() ?? '',
      );
      final observedDeviceUtc = DateTime.tryParse(
        decoded['observedDeviceUtc']?.toString() ?? '',
      );
      if (policyVersion.isEmpty ||
          companyId.isEmpty ||
          userId.isEmpty ||
          deviceFingerprint.isEmpty ||
          serverUtc == null ||
          validUntilUtc == null ||
          observedDeviceUtc == null) {
        return null;
      }
      return _OfflineEmergencySnapshot(
        advancedProtocolVerified: decoded['advancedProtocolVerified'] == true,
        policyVersion: policyVersion,
        companyId: companyId,
        userId: userId,
        deviceFingerprint: deviceFingerprint,
        serverUtc: serverUtc.toUtc(),
        validUntilUtc: validUntilUtc.toUtc(),
        observedDeviceUtc: observedDeviceUtc.toUtc(),
        allowedOperations:
            (decoded['allowedOperations'] as List?)
                ?.whereType<String>()
                .toList() ??
            const ['sales.create'],
      );
    } catch (_) {
      return null;
    }
  }
}
