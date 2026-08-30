import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
  });

  test('persists category image after saving and reloading', () async {
    final controller = InventoryCategoriesController();
    await controller.load();

    await controller.upsert(
      name: 'Computadoras y POS',
      imageBase64: 'category-image-base64',
    );

    final reloaded = InventoryCategoriesController();
    await reloaded.load();

    expect(reloaded.state.items, hasLength(1));
    expect(reloaded.state.items.single.name, 'Computadoras y POS');
    expect(reloaded.state.items.single.imageBase64, 'category-image-base64');

    controller.dispose();
    reloaded.dispose();
  });
}
