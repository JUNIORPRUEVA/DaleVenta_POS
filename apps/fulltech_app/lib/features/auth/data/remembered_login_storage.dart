import 'package:shared_preferences/shared_preferences.dart';

class RememberedLoginData {
  const RememberedLoginData({required this.remember, required this.email});

  final bool remember;
  final String email;
}

class RememberedLoginStorage {
  const RememberedLoginStorage();

  static const rememberEmailKey = 'remember_email';
  static const legacyRememberPasswordKey = 'remember_password';
  static const rememberFlagKey = 'remember_flag';

  Future<RememberedLoginData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(rememberFlagKey) ?? false;
    final email = prefs.getString(rememberEmailKey) ?? '';
    await prefs.remove(legacyRememberPasswordKey);
    return RememberedLoginData(remember: remembered, email: email);
  }

  Future<void> save({required bool remember, required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyRememberPasswordKey);
    if (remember) {
      await prefs.setBool(rememberFlagKey, true);
      await prefs.setString(rememberEmailKey, email.trim());
    } else {
      await prefs.remove(rememberFlagKey);
      await prefs.remove(rememberEmailKey);
    }
  }
}
