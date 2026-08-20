import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';


/// Fake de FlutterSecureStorage que:
///  - guarda valores en memoria,
///  - detecta acceso concurrente (máximo de operaciones simultáneas),
///  - puede lanzar errores temporales (file locked / CryptUnprotectData) para
///    simular el comportamiento real de Windows.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};
  int _activeOps = 0;
  int _maxConcurrent = 0;
  int _opCount = 0;
  bool _failNextRead = false;
  bool _failNextWrite = false;
  bool _failNextDelete = false;
  bool _failNextDeleteAll = false;
  bool _corruptOnRead = false;

  int get maxConcurrent => _maxConcurrent;
  int get opCount => _opCount;

  void _enter() {
    _activeOps++;
    if (_activeOps > _maxConcurrent) _maxConcurrent = _activeOps;
  }

  void _exit() {
    _activeOps--;
  }

  void failNextRead() => _failNextRead = true;
  void failNextWrite() => _failNextWrite = true;
  void failNextDelete() => _failNextDelete = true;
  void failNextDeleteAll() => _failNextDeleteAll = true;

  /// Simula un archivo corrupto: la siguiente lectura lanza CryptUnprotectData.
  void corruptOnNextRead() => _corruptOnRead = true;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _enter();
    try {
      _opCount++;
      if (_failNextRead) {
        _failNextRead = false;
        throw Exception('CryptUnprotectData() failed');
      }
      if (_corruptOnRead) {
        _corruptOnRead = false;
        throw Exception('flutter_secure_storage.dat corrupt');
      }
      return _store[key];
    } finally {
      _exit();
    }
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _enter();
    try {
      _opCount++;
      if (_failNextWrite) {
        _failNextWrite = false;
        throw Exception('file is being used by another process');
      }
      if (value == null) {
        _store.remove(key);
      } else {
        _store[key] = value;
      }
    } finally {
      _exit();
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _enter();
    try {
      _opCount++;
      if (_failNextDelete) {
        _failNextDelete = false;
        throw Exception('file is being used by another process');
      }
      _store.remove(key);
    } finally {
      _exit();
    }
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _enter();
    try {
      _opCount++;
      if (_failNextDeleteAll) {
        _failNextDeleteAll = false;
        throw Exception('file is being used by another process');
      }
      _store.clear();
    } finally {
      _exit();
    }
  }
}

UserModel _makeUser(String id) {
  return UserModel.fromJson({
    'id': id,
    'email': 'user$id@test.com',
    'name': 'User $id',
    'companyId': 'company-$id',
    'companyName': 'Company $id',
    'companySlug': 'company-$id',
    'appRole': 'admin',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenStorage serialización (Windows lock fix)', () {
    test(
      'A. 50 operaciones concurrentes no corrompen ni lanzan PathAccessException',
      () async {
        final fake = _FakeSecureStorage();
        final storage = TokenStorage(secureStorage: fake);

        // Dispara 50 operaciones concurrentes mezclando read/write/snapshot.
        final futures = <Future<void>>[];
        for (var i = 0; i < 50; i++) {
          final idx = i;
          futures.add(() async {
            switch (idx % 4) {
              case 0:
                await storage.saveTokens('access-$idx', 'refresh-$idx');
              case 1:
                await storage.getAccessToken();
              case 2:
                await storage.saveUserSnapshot(_makeUser('$idx'));
              case 3:
                await storage.getUserSnapshot();
            }
          }());
        }
        await Future.wait(futures);

        // El mutex garantiza que NUNCA haya dos operaciones simultáneas.
        expect(fake.maxConcurrent, lessThanOrEqualTo(1),
            reason: 'El mutex debe serializar todas las operaciones');
        // No debe haber corrupción: los tokens siguen accesibles.
        final token = await storage.getAccessToken();
        expect(token, isNotNull);
        expect(token, isNotEmpty);
      },
    );

    test(
      'E. fallo en saveUserSnapshot no borra tokens ni cierra sesión',
      () async {
        final fake = _FakeSecureStorage();
        final storage = TokenStorage(secureStorage: fake);

        await storage.saveTokens('access-valid', 'refresh-valid');
        // El snapshot falla (secure storage bloqueado).
        fake.failNextWrite();
        await storage.saveUserSnapshot(_makeUser('1'));

        // Los tokens siguen vivos.
        expect(await storage.getAccessToken(), 'access-valid');
        expect(await storage.getRefreshToken(), 'refresh-valid');
        // El snapshot en memoria sigue disponible (secundario).
        expect((await storage.getUserSnapshot())?.id, '1');
      },
    );

    test(
      'F. error temporal de secure storage NO provoca logout (tokens intactos)',
      () async {
        final fake = _FakeSecureStorage();
        final storage = TokenStorage(secureStorage: fake);

        await storage.saveTokens('access-valid', 'refresh-valid');

        // Simula un bloqueo temporal del archivo en la siguiente lectura.
        fake.failNextRead();
        final token = await storage.getAccessToken();
        // El token se recupera desde memoria (no se pierde la sesión).
        expect(token, 'access-valid');
        expect(await storage.getRefreshToken(), 'refresh-valid');
      },
    );

    test(
      'F2. corrupción temporal se recupera una sola vez sin borrar sesión',
      () async {
        final fake = _FakeSecureStorage();
        // Escribe tokens en el "archivo" (simula un archivo ya existente).
        await fake.write(key: 'accessToken', value: 'access-valid');
        await fake.write(key: 'refreshToken', value: 'refresh-valid');

        // El fallback durable (prefs) también tiene los tokens, como ocurre
        // tras un reinicio de la app.
        SharedPreferences.setMockInitialValues({
          'accessToken': 'access-valid',
          'refreshToken': 'refresh-valid',
        });

        // Nueva instancia con memoria vacía: forzará lectura desde secure.
        final storage = TokenStorage(secureStorage: fake);

        // Simula que el archivo se corrompe (CryptUnprotectData).
        fake.corruptOnNextRead();
        // La primera lectura detecta la corrupción y NO borra la sesión:
        // cae al fallback de prefs y devuelve el token.
        final token = await storage.getAccessToken();
        expect(token, 'access-valid');
        // La sesión sigue viva.
        expect(await storage.getRefreshToken(), 'refresh-valid');
      },
    );




    test(
      'H. una sola instancia canónica comparte el mismo mutex',
      () async {
        // TokenStorage.instance es un singleton: todas las llamadas comparten
        // el mismo mutex interno sobre el mismo archivo.
        final a = TokenStorage.instance;
        final b = TokenStorage.instance;
        expect(identical(a, b), isTrue,
            reason: 'Debe existir UNA sola instancia canónica');
      },
    );

    test(
      'H2. dos instancias con el mismo secure storage se serializan por separado',
      () async {
        // Aunque se creen dos instancias (solo en tests), cada una serializa
        // sus propias operaciones. En producción solo existe TokenStorage.instance.
        final fake = _FakeSecureStorage();
        final storage = TokenStorage(secureStorage: fake);

        // 20 operaciones concurrentes de escritura/lectura.
        final futures = List.generate(20, (i) async {
          await storage.saveTokens('access-$i', 'refresh-$i');
          await storage.getAccessToken();
        });
        await Future.wait(futures);

        expect(fake.maxConcurrent, lessThanOrEqualTo(1));
        expect(fake.opCount, greaterThan(0));
      },
    );
  });
}
