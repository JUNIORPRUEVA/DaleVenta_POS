import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/trace_log.dart';
import '../models/user_model.dart';

class TokenStorageLaunchSnapshot {
  final bool hasSessionHint;
  final UserModel? user;

  const TokenStorageLaunchSnapshot({required this.hasSessionHint, this.user});

  const TokenStorageLaunchSnapshot.empty() : this(hasSessionHint: false);

  bool get canRestoreSession => hasSessionHint && user != null;
}

class TokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _userSnapshotKey = 'authUserSnapshot';
  final _secureStorage = const FlutterSecureStorage();
  String? _memoryAccessToken;
  String? _memoryRefreshToken;
  UserModel? _memoryUserSnapshot;

  bool get _useSecureStorage {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Duration get _prefsTimeout =>
      _isDesktop ? const Duration(seconds: 6) : const Duration(seconds: 2);
  Duration get _secureTimeout =>
      _isDesktop ? const Duration(seconds: 6) : const Duration(seconds: 2);

  bool _prefsBroken = false;

  Future<SharedPreferences> _prefs() {
    if (_prefsBroken) {
      return Future.error(StateError('SharedPreferences unavailable'));
    }

    return SharedPreferences.getInstance().timeout(_prefsTimeout).catchError((
      e,
    ) {
      // On some Windows setups the underlying prefs JSON can become corrupted,
      // causing FormatException on any access. Mark as broken to avoid spamming logs.
      _prefsBroken = true;
      throw e;
    });
  }

  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('TokenStorage', 'saveTokens() start', seq: seq);
    _memoryAccessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _memoryRefreshToken = refreshToken;
    }

    await _saveInPrefs(accessToken, refreshToken); // Keep a durable fallback
    await _saveInSecure(accessToken, refreshToken);
    TraceLog.log('TokenStorage', 'saveTokens() end', seq: seq);
  }

  Future<String?> getAccessToken() async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('TokenStorage', 'getAccessToken() start', seq: seq);
    if (_memoryAccessToken != null && _memoryAccessToken!.isNotEmpty) {
      TraceLog.log('TokenStorage', 'getAccessToken() memory hit', seq: seq);
      return _memoryAccessToken;
    }

    final secure = await _readSecure(_accessTokenKey);
    if (secure != null && secure.isNotEmpty) {
      _memoryAccessToken = secure;
      unawaited(_writePrefValue(_accessTokenKey, secure));
      TraceLog.log('TokenStorage', 'getAccessToken() secure hit', seq: seq);
      return secure;
    }

    try {
      final prefs = await _prefs();
      final value = prefs.getString(_accessTokenKey);
      if (value != null && value.isNotEmpty) {
        _memoryAccessToken = value;
        unawaited(_writeSecureValue(_accessTokenKey, value));
        TraceLog.log('TokenStorage', 'getAccessToken() prefs hit', seq: seq);
        return value;
      }
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'getAccessToken() prefs ERROR',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    }

    TraceLog.log('TokenStorage', 'getAccessToken() miss', seq: seq);
    return null;
  }

  Future<String?> getRefreshToken() async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('TokenStorage', 'getRefreshToken() start', seq: seq);
    if (_memoryRefreshToken != null && _memoryRefreshToken!.isNotEmpty) {
      TraceLog.log('TokenStorage', 'getRefreshToken() memory hit', seq: seq);
      return _memoryRefreshToken;
    }

    final secure = await _readSecure(_refreshTokenKey);
    if (secure != null && secure.isNotEmpty) {
      _memoryRefreshToken = secure;
      unawaited(_writePrefValue(_refreshTokenKey, secure));
      TraceLog.log('TokenStorage', 'getRefreshToken() secure hit', seq: seq);
      return secure;
    }

    try {
      final prefs = await _prefs();
      final value = prefs.getString(_refreshTokenKey);
      if (value != null && value.isNotEmpty) {
        _memoryRefreshToken = value;
        unawaited(_writeSecureValue(_refreshTokenKey, value));
        TraceLog.log('TokenStorage', 'getRefreshToken() prefs hit', seq: seq);
        return value;
      }
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'getRefreshToken() prefs ERROR',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    }

    TraceLog.log('TokenStorage', 'getRefreshToken() miss', seq: seq);
    return null;
  }

  Future<void> saveUserSnapshot(UserModel user) async {
    _memoryUserSnapshot = user;
    final encoded = jsonEncode(user.toJson());
    try {
      final prefs = await _prefs();
      await prefs.setString(_userSnapshotKey, encoded);
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'saveUserSnapshot() ERROR',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await _secureStorage
          .write(key: _userSnapshotKey, value: encoded)
          .timeout(_secureTimeout);
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'saveUserSnapshot() secure ERROR',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<UserModel?> getUserSnapshot() async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('TokenStorage', 'getUserSnapshot() start', seq: seq);
    if (_memoryUserSnapshot != null) {
      TraceLog.log('TokenStorage', 'getUserSnapshot() memory hit', seq: seq);
      return _memoryUserSnapshot;
    }

    final secureUser = await _restoreUserSnapshot(
      await _readSecure(_userSnapshotKey),
      seq: seq,
      source: 'secure',
    );
    if (secureUser != null) {
      unawaited(saveUserSnapshot(secureUser));
      return secureUser;
    }

    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_userSnapshotKey);
      final user = await _restoreUserSnapshot(raw, seq: seq, source: 'prefs');
      if (user != null) {
        unawaited(saveUserSnapshot(user));
        return user;
      }
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'getUserSnapshot() ERROR',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    }

    TraceLog.log('TokenStorage', 'getUserSnapshot() miss', seq: seq);
    return null;
  }

  Future<TokenStorageLaunchSnapshot> readFastLaunchSnapshot({
    Duration timeout = const Duration(milliseconds: 180),
  }) async {
    if ((_memoryAccessToken?.isNotEmpty ?? false) &&
        _memoryUserSnapshot != null) {
      return TokenStorageLaunchSnapshot(
        hasSessionHint: true,
        user: _memoryUserSnapshot,
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance().timeout(timeout);
      final accessToken =
          _memoryAccessToken ?? prefs.getString(_accessTokenKey);
      final user =
          _memoryUserSnapshot ??
          _parseLaunchUserSnapshot(prefs.getString(_userSnapshotKey));

      if (accessToken != null && accessToken.isNotEmpty) {
        _memoryAccessToken = accessToken;
      }
      if (user != null) {
        _memoryUserSnapshot = user;
      }

      return TokenStorageLaunchSnapshot(
        hasSessionHint: accessToken != null && accessToken.isNotEmpty,
        user: user,
      );
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'readFastLaunchSnapshot() fallback to empty',
        error: e,
        stackTrace: st,
      );
      return const TokenStorageLaunchSnapshot.empty();
    }
  }

  Future<void> clearTokens() async {
    final seq = TraceLog.nextSeq();
    TraceLog.log('TokenStorage', 'clearTokens() start', seq: seq);
    _memoryAccessToken = null;
    _memoryRefreshToken = null;
    _memoryUserSnapshot = null;

    try {
      final prefs = await _prefs();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userSnapshotKey);
    } catch (_) {
      // Ignore prefs failures and still clear secure storage.
    }

    await _deleteSecure(_accessTokenKey);
    await _deleteSecure(_refreshTokenKey);
    await _deleteSecure(_userSnapshotKey);
    TraceLog.log('TokenStorage', 'clearTokens() end', seq: seq);
  }

  Future<void> _saveInPrefs(String accessToken, [String? refreshToken]) async {
    if (_prefsBroken) return;
    try {
      final prefs = await _prefs();
      await prefs.setString(_accessTokenKey, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
    } catch (e, st) {
      _prefsBroken = true;
      TraceLog.log(
        'TokenStorage',
        '_saveInPrefs ERROR',
        error: e,
        stackTrace: st,
      );
      // Keep in-memory tokens as fallback for this session.
    }
  }

  Future<void> _writePrefValue(String key, String value) async {
    if (value.isEmpty) return;
    if (_prefsBroken) return;
    try {
      final prefs = await _prefs();
      await prefs.setString(key, value);
    } catch (e, st) {
      _prefsBroken = true;
      TraceLog.log(
        'TokenStorage',
        '_writePrefValue ERROR key=$key',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _saveInSecure(String accessToken, [String? refreshToken]) async {
    if (!_useSecureStorage) return;
    try {
      if (accessToken.isNotEmpty) {
        await _secureStorage
            .write(key: _accessTokenKey, value: accessToken)
            .timeout(_secureTimeout);
      }
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage
            .write(key: _refreshTokenKey, value: refreshToken)
            .timeout(_secureTimeout);
      }
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        '_saveInSecure ERROR',
        error: e,
        stackTrace: st,
      );
      // Silently fall back to prefs when secure storage is unavailable
    }
  }

  Future<void> _writeSecureValue(String key, String value) async {
    if (!_useSecureStorage || value.isEmpty) return;
    try {
      await _secureStorage
          .write(key: key, value: value)
          .timeout(_secureTimeout);
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        '_writeSecureValue ERROR key=$key',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<String?> _readSecure(String key) async {
    if (!_useSecureStorage) return null;
    try {
      return await _secureStorage.read(key: key).timeout(_secureTimeout);
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        '_readSecure ERROR key=$key',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (!_useSecureStorage) return;
    try {
      await _secureStorage.delete(key: key).timeout(_secureTimeout);
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        '_deleteSecure ERROR key=$key',
        error: e,
        stackTrace: st,
      );
      // Ignore secure storage failures on platforms without support
    }
  }

  Future<UserModel?> _restoreUserSnapshot(
    String? raw, {
    required int seq,
    required String source,
  }) async {
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _removeCorruptedUserSnapshot(source);
        return null;
      }

      final user = UserModel.fromJson(decoded.cast<String, dynamic>());
      _memoryUserSnapshot = user;
      TraceLog.log('TokenStorage', 'getUserSnapshot() $source hit', seq: seq);
      return user;
    } catch (e, st) {
      TraceLog.log(
        'TokenStorage',
        'getUserSnapshot() $source ERROR',
        seq: seq,
        error: e,
        stackTrace: st,
      );
      await _removeCorruptedUserSnapshot(source);
      return null;
    }
  }

  Future<void> _removeCorruptedUserSnapshot(String source) async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_userSnapshotKey);
    } catch (_) {}

    try {
      await _secureStorage
          .delete(key: _userSnapshotKey)
          .timeout(_secureTimeout);
    } catch (_) {}

    TraceLog.log(
      'TokenStorage',
      'Removed corrupted user snapshot from $source',
    );
  }

  UserModel? _parseLaunchUserSnapshot(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return UserModel.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
