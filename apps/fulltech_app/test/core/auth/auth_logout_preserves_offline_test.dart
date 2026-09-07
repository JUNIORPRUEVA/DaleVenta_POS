import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'logout clears auth identity without deleting offline business cache',
    () async {
      final store = OfflineStore.forTesting(
        'auth_logout_preserves_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      await store.writeCacheEntry('products.company-a', {'count': 2});

      final tokenStorage = _FakeTokenStorage();
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          offlineStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final auth = container.read(authStateProvider.notifier);
      auth.setUser(_user(id: 'user-a', companyId: 'company-a'));

      await auth.logout();

      expect(tokenStorage.clearedTokens, isTrue);
      expect(container.read(authStateProvider).isAuthenticated, isFalse);
      expect(await store.readCacheEntry('products.company-a'), {'count': 2});
    },
  );
}

UserModel _user({required String id, required String companyId}) {
  return UserModel(
    id: id,
    email: '$id@example.test',
    nombreCompleto: 'Test User',
    telefono: '',
    role: 'ADMIN',
    companyId: companyId,
  );
}

class _FakeTokenStorage extends TokenStorage {
  bool clearedTokens = false;

  @override
  Future<void> saveUserSnapshot(UserModel user) async {}

  @override
  Future<void> clearTokens() async {
    clearedTokens = true;
  }
}
