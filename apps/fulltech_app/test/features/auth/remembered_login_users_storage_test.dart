import 'package:daleventa_pos/features/auth/data/remembered_login_users_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = RememberedLoginUsersStorage();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadUsers purga las claves heredadas de recordar contraseña', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.legacyRememberFlagKey: true,
      RememberedLoginUsersStorage.legacyRememberEmailKey: 'user@example.test',
      RememberedLoginUsersStorage.legacyRememberPasswordKey: 'do-not-keep',
      RememberedLoginUsersStorage.usersKey: <String>['first@example.test'],
    });

    final users = await storage.loadUsers();
    final prefs = await SharedPreferences.getInstance();

    expect(users, <String>['first@example.test']);
    expect(
      prefs.containsKey(RememberedLoginUsersStorage.legacyRememberFlagKey),
      isFalse,
    );
    expect(
      prefs.containsKey(RememberedLoginUsersStorage.legacyRememberEmailKey),
      isFalse,
    );
    expect(
      prefs.containsKey(RememberedLoginUsersStorage.legacyRememberPasswordKey),
      isFalse,
    );
  });

  test('rememberUser guarda el usuario más reciente primero', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.usersKey: <String>[
        'primero@example.test',
        'segundo@example.test',
      ],
    });

    final users = await storage.rememberUser(' segundo@example.test ');
    final prefs = await SharedPreferences.getInstance();

    expect(users, <String>[
      'segundo@example.test',
      'primero@example.test',
    ]);
    expect(
      prefs.getStringList(RememberedLoginUsersStorage.usersKey),
      <String>['segundo@example.test', 'primero@example.test'],
    );
  });

  test('rememberUser nunca persiste la contraseña', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.legacyRememberPasswordKey: 'SuperSecreta123',
    });

    await storage.rememberUser('usuario@example.test');
    final prefs = await SharedPreferences.getInstance();

    final storedValues = prefs
        .getKeys()
        .map((key) => prefs.get(key).toString())
        .toList();
    expect(
      storedValues.any((value) => value.contains('SuperSecreta123')),
      isFalse,
    );
    expect(
      prefs.containsKey(RememberedLoginUsersStorage.legacyRememberPasswordKey),
      isFalse,
    );
    expect(
      prefs.getStringList(RememberedLoginUsersStorage.usersKey),
      <String>['usuario@example.test'],
    );
  });

  test('removeUser quita el usuario de este dispositivo', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.usersKey: <String>[
        'primero@example.test',
        'segundo@example.test',
      ],
    });

    final users = await storage.removeUser('PRIMERO@example.test');
    final prefs = await SharedPreferences.getInstance();

    expect(users, <String>['segundo@example.test']);
    expect(
      prefs.getStringList(RememberedLoginUsersStorage.usersKey),
      <String>['segundo@example.test'],
    );
  });

  test('la lista se normaliza, deduplica y limita al máximo', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.usersKey: <String>[
        '  ',
        'a@example.test',
        'B@example.test',
        'a@example.test',
        'c@example.test',
        'd@example.test',
        'e@example.test',
        'f@example.test',
      ],
    });

    final users = await storage.loadUsers();

    expect(users.length, RememberedLoginUsersStorage.maxUsers);
    expect(users.first, 'a@example.test');
    expect(users, contains('B@example.test'));
    expect(
      users.where((user) => user.toLowerCase() == 'a@example.test').length,
      1,
    );
  });

  test('quitar el último usuario borra la clave almacenada', () async {
    SharedPreferences.setMockInitialValues({
      RememberedLoginUsersStorage.usersKey: <String>['unico@example.test'],
    });

    await storage.removeUser('unico@example.test');
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.containsKey(RememberedLoginUsersStorage.usersKey),
      isFalse,
    );
  });
}
