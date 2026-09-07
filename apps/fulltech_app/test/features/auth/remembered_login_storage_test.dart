import 'package:daleventa_pos/features/auth/data/remembered_login_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load preserves remembered email and removes legacy password', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginStorage.rememberFlagKey: true,
      RememberedLoginStorage.rememberEmailKey: 'user@example.test',
      RememberedLoginStorage.legacyRememberPasswordKey: 'do-not-keep',
    });

    final storage = const RememberedLoginStorage();
    final data = await storage.load();
    final prefs = await SharedPreferences.getInstance();

    expect(data.remember, isTrue);
    expect(data.email, 'user@example.test');
    expect(
      prefs.containsKey(RememberedLoginStorage.legacyRememberPasswordKey),
      isFalse,
    );
  });

  test('save remembers only email and never stores password', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginStorage.legacyRememberPasswordKey: 'legacy-password',
    });

    final storage = const RememberedLoginStorage();
    await storage.save(remember: true, email: ' user@example.test ');
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getBool(RememberedLoginStorage.rememberFlagKey), isTrue);
    expect(
      prefs.getString(RememberedLoginStorage.rememberEmailKey),
      'user@example.test',
    );
    expect(
      prefs.containsKey(RememberedLoginStorage.legacyRememberPasswordKey),
      isFalse,
    );
  });

  test('save disabled removes remembered login state', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginStorage.rememberFlagKey: true,
      RememberedLoginStorage.rememberEmailKey: 'user@example.test',
      RememberedLoginStorage.legacyRememberPasswordKey: 'legacy-password',
    });

    final storage = const RememberedLoginStorage();
    await storage.save(remember: false, email: 'user@example.test');
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.containsKey(RememberedLoginStorage.rememberFlagKey), isFalse);
    expect(prefs.containsKey(RememberedLoginStorage.rememberEmailKey), isFalse);
    expect(
      prefs.containsKey(RememberedLoginStorage.legacyRememberPasswordKey),
      isFalse,
    );
  });
}
