import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/uat_identity.dart';
import '../errors/api_exception.dart';
import '../models/user_model.dart';
import '../offline/offline_emergency_policy.dart';
import '../storage/serialized_secure_storage.dart';
import '../usage/client_telemetry_headers.dart';

class OfflineLoginSession {
  const OfflineLoginSession(this.user, this.accessToken, this.refreshToken);
  final UserModel user;
  final String accessToken;
  final String refreshToken;
}

/// Native, device-owned authentication only. Never uses a preferences fallback.
class OfflineLogin {
  OfflineLogin({
    required this.server,
    SerializedSecureStorage? storage,
    OfflineEmergencyPolicy? policy,
    Future<String> Function()? deviceId,
    DateTime Function()? now,
    bool? enabled,
    Future<List<int>> Function(String, List<int>)? derive,
  }) : _storage = storage ?? const SerializedSecureStorage(),
       _policy = policy ?? OfflineEmergencyPolicy(),
       _deviceId =
           deviceId ??
           (() async =>
               (await ClientTelemetryHeaders.instance
                   .headers())['x-client-device-id'] ??
               ''),
       _now = now ?? (() => DateTime.now().toUtc()),
       enabled =
           enabled ??
           (!kIsWeb &&
               {
                 TargetPlatform.windows,
                 TargetPlatform.android,
                 TargetPlatform.iOS,
               }.contains(defaultTargetPlatform)),
       _derive = derive ?? deriveVerifier;

  final String server;
  final bool enabled;
  final SerializedSecureStorage _storage;
  final OfflineEmergencyPolicy _policy;
  final Future<String> Function() _deviceId;
  final DateTime Function() _now;
  final Future<List<int>> Function(String, List<int>) _derive;
  static Future<void> _tail = Future<void>.value();
  static final Set<String> _revoked = {};
  String _revocationKey(String key) => 'offline_login_revoked.$key';

  static Future<List<int>> deriveVerifier(String password, List<int> salt) =>
      compute(_deriveInWorker, (password, salt));

  static Future<List<int>> _deriveInWorker((String, List<int>) input) async {
    final key = await Pbkdf2.hmacSha256(
      iterations: 600000,
      bits: 256,
    ).deriveKeyFromPassword(password: input.$1, nonce: input.$2);
    return key.extractBytes();
  }

  String _key(String email) => UatIdentity.storageKey(
    'offline_login.v1.${digest.sha256.convert(utf8.encode(jsonEncode([server, email.trim().toLowerCase()])))}',
  );

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _matchesToken(UserModel user, String access) {
    try {
      final parts = access.split('.');
      if (parts.length != 3) return false;
      final data =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map;
      return data['sub'] == user.id && data['companyId'] == user.companyId;
    } catch (_) {
      return false;
    }
  }

  Future<void> enroll({
    required String email,
    required String password,
    required OfflineLoginSession session,
    required Future<bool> Function() stillCurrent,
  }) async {
    if (!enabled) return;
    final user = session.user;
    final device = await _deviceId();
    if (device.isEmpty ||
        user.id.isEmpty ||
        user.blocked ||
        (user.companyId ?? '').isEmpty ||
        user.email.trim().toLowerCase() != email.trim().toLowerCase() ||
        !_matchesToken(user, session.accessToken) ||
        session.refreshToken.isEmpty) {
      return;
    }
    final decision = await _policy.canStartOfflineSale(
      companyId: user.companyId!,
      userId: user.id,
      deviceFingerprint: device,
      nowUtc: _now(),
    );
    if (!decision.allowed) return;
    final validationDeviceTime = _now().subtract(
      decision.elapsedSinceValidation ?? Duration.zero,
    );
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final verifier = await _derive(password, salt);
    await _serial(() async {
      if (!await stillCurrent()) return;
      final key = _key(email);
      await _storage.write(
        key: _key(email),
        value: jsonEncode({
          'version': 1,
          'server': server,
          'device': device,
          'user': user.toJson(),
          'access': session.accessToken,
          'refresh': session.refreshToken,
          'salt': base64Encode(salt),
          'verifier': base64Encode(verifier),
          'failures': 0,
          'validatedAt': decision.lastServerValidationUtc!.toIso8601String(),
          'validationDeviceTime': validationDeviceTime.toIso8601String(),
          'createdAt': _now().toIso8601String(),
          'lastSeen': _now().toIso8601String(),
        }),
      );
      await (await SharedPreferences.getInstance()).remove(_revocationKey(key));
      _revoked.remove(key);
    });
  }

  Future<OfflineLoginSession> unlock(String email, String password) async {
    if (!enabled) throw unavailable;
    return _serial(() async {
      final key = _key(email);
      final prefs = await SharedPreferences.getInstance();
      if (_revoked.contains(key) || prefs.getBool(_revocationKey(key)) == true) {
        throw unavailable;
      }
      final raw = await _storage.read(key: key);
      if (raw == null) throw unavailable;
      try {
        final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final user = UserModel.fromJson(
          (data['user'] as Map).cast<String, dynamic>(),
        );
        final device = await _deviceId();
        final now = _now();
        final created = DateTime.parse(data['createdAt'] as String);
        final lastSeen = DateTime.parse(data['lastSeen'] as String);
        final validated = DateTime.parse(
          data['validationDeviceTime'] as String,
        );
        if (data['version'] != 1 ||
            data['server'] != server ||
            device.isEmpty ||
            data['device'] != device ||
            user.id.isEmpty ||
            user.blocked ||
            (user.companyId ?? '').isEmpty ||
            user.email.trim().toLowerCase() != email.trim().toLowerCase() ||
            now.isBefore(
              lastSeen.subtract(OfflineEmergencyPolicy.clockRollbackTolerance),
            ) ||
            now.isBefore(
              created.subtract(OfflineEmergencyPolicy.clockRollbackTolerance),
            ) ||
            now.difference(validated) >
                OfflineEmergencyPolicy.maxOfflineDuration) {
          throw unavailable;
        }
        final policy = await _policy.canStartOfflineSale(
          companyId: user.companyId!,
          userId: user.id,
          deviceFingerprint: device,
          nowUtc: now,
        );
        if (!policy.allowed) throw unavailable;
        final blockedUntil = DateTime.tryParse(
          data['blockedUntil']?.toString() ?? '',
        );
        if (blockedUntil != null && now.isBefore(blockedUntil)) {
          throw const ApiException.detailed(
            message:
                'Espera unos minutos antes de volver a intentar el acceso local.',
            type: ApiErrorType.forbidden,
            displayCode: 'LOCAL_LOGIN_THROTTLED',
          );
        }
        final actual = await _derive(
          password,
          base64Decode(data['salt'] as String),
        );
        final expected = base64Decode(data['verifier'] as String);
        if (actual.length != 32 || expected.length != 32) throw unavailable;
        var difference = actual.length ^ expected.length;
        for (var i = 0; i < actual.length && i < expected.length; i++) {
          difference |= actual[i] ^ expected[i];
        }
        data['lastSeen'] = now.toIso8601String();
        if (difference != 0) {
          final failures = (data['failures'] as int? ?? 0) + 1;
          data['failures'] = failures;
          if (failures >= 5) {
            data['blockedUntil'] = now
                .add(const Duration(minutes: 5))
                .toIso8601String();
          }
          await _storage.write(key: _key(email), value: jsonEncode(data));
          throw const ApiException.detailed(
            message: 'Revisa tu correo y contraseña.',
            type: ApiErrorType.unauthorized,
            displayCode: 'LOCAL_LOGIN_INVALID',
          );
        }
        data['failures'] = 0;
        data.remove('blockedUntil');
        final access = data['access'] as String;
        final refresh = data['refresh'] as String;
        if (!_matchesToken(user, access) || refresh.isEmpty) throw unavailable;
        await _storage.write(key: _key(email), value: jsonEncode(data));
        return OfflineLoginSession(user, access, refresh);
      } on ApiException {
        rethrow;
      } catch (_) {
        throw unavailable;
      }
    });
  }

  Future<void> forget(String email) async {
    if (!enabled) return;
    final key = _key(email);
    _revoked.add(key);
    await _serial(() => _retire(key));
  }

  Future<void> _retire(String key) async {
    _revoked.add(key);
    // Non-secret tombstone remains even if native credential deletion fails.
    await (await SharedPreferences.getInstance()).setBool(
      _revocationKey(key),
      true,
    );
    await _storage.delete(key: key);
  }

  /// Refresh tokens without extending the password verification's deadline.
  /// A newly observed identity/permission change retires the old verifier.
  Future<void> observeSession(OfflineLoginSession session) async {
    if (!enabled) return;
    await _serial(() async {
      final key = _key(session.user.email);
      final raw = await _storage.read(key: key);
      if (raw == null) return;
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final before = (data['user'] as Map).cast<String, dynamic>();
      final after = session.user.toJson();
      const fields = ['id', 'companyId', 'role', 'blocked'];
      if (fields.any(
            (field) => jsonEncode(before[field]) != jsonEncode(after[field]),
          ) ||
          !mapEquals(
            (before['userPermissions'] as Map).cast<String, bool>(),
            session.user.userPermissions,
          ) ||
          !_matchesToken(session.user, session.accessToken) ||
          session.refreshToken.isEmpty ||
          data['device'] != await _deviceId() ||
          data['server'] != server) {
        await _retire(key);
        return;
      }
      data['access'] = session.accessToken;
      data['refresh'] = session.refreshToken;
      data['user'] = after;
      await _storage.write(key: key, value: jsonEncode(data));
    });
  }

  static const unavailable = ApiException.detailed(
    message:
        'Necesitas conexión para iniciar sesión en este equipo. El acceso local no está disponible o venció.',
    type: ApiErrorType.noInternet,
    displayCode: 'LOCAL_LOGIN_UNAVAILABLE',
    retryable: true,
  );
}
