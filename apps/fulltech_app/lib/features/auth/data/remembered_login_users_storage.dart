import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the list of usernames (emails) used to log in from this device.
///
/// Rules:
/// - Only the username is ever stored. Passwords are never read, written or
///   kept by this storage.
/// - The list is ordered from most recently used to least recently used.
/// - The list is capped at [maxUsers] entries.
/// - Legacy keys of the removed "remember login/password" feature are purged so
///   no previous credential state survives on the device.
///
/// Used by the login screen on Windows, Android and iOS. The SharedPreferences
/// key keeps its original `windows_login_users` name on purpose: renaming it
/// would drop the users already remembered on installed PCs.
class RememberedLoginUsersStorage {
  const RememberedLoginUsersStorage();

  static const usersKey = 'windows_login_users';

  static const legacyRememberFlagKey = 'remember_flag';
  static const legacyRememberEmailKey = 'remember_email';
  static const legacyRememberPasswordKey = 'remember_password';

  static const maxUsers = 5;

  /// Reads the remembered usernames of this PC (already normalized).
  Future<List<String>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await _purgeLegacyKeys(prefs);
    final stored = prefs.getStringList(usersKey) ?? const <String>[];
    final normalized = _normalize(stored);
    if (!listEquals(stored, normalized)) {
      await _writeUsers(prefs, normalized);
    }
    return normalized;
  }

  /// Moves [email] to the top of the remembered list and returns the result.
  Future<List<String>> rememberUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await _purgeLegacyKeys(prefs);
    final stored = prefs.getStringList(usersKey) ?? const <String>[];
    final normalized = _normalize(<String>[email, ...stored]);
    await _writeUsers(prefs, normalized);
    return normalized;
  }

  /// Removes [email] from the remembered list and returns the result.
  Future<List<String>> removeUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await _purgeLegacyKeys(prefs);
    final target = email.trim().toLowerCase();
    final stored = prefs.getStringList(usersKey) ?? const <String>[];
    final normalized = _normalize(
      stored.where((user) => user.trim().toLowerCase() != target),
    );
    await _writeUsers(prefs, normalized);
    return normalized;
  }

  /// Deletes every legacy key of the removed "remember login" feature.
  Future<void> _purgeLegacyKeys(SharedPreferences prefs) async {
    for (final key in const <String>[
      legacyRememberPasswordKey,
      legacyRememberEmailKey,
      legacyRememberFlagKey,
    ]) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _writeUsers(
    SharedPreferences prefs,
    List<String> users,
  ) async {
    if (users.isEmpty) {
      if (prefs.containsKey(usersKey)) {
        await prefs.remove(usersKey);
      }
      return;
    }
    await prefs.setStringList(usersKey, users);
  }

  List<String> _normalize(Iterable<String> users) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in users) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final marker = value.toLowerCase();
      if (!seen.add(marker)) continue;
      result.add(value);
      if (result.length >= maxUsers) break;
    }
    return result;
  }
}
