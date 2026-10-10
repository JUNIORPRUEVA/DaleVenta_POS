import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String screenSource;
  late String repositorySource;

  setUpAll(() {
    screenSource = File(
      'lib/features/warehouses/ui/warehouse_settings_screen.dart',
    ).readAsStringSync();
    repositorySource = File(
      'lib/features/warehouses/data/warehouse_repository.dart',
    ).readAsStringSync();
  });

  test('Almacenes usa ProductSearchController en transferencias', () {
    expect(
      screenSource,
      contains('late final ProductSearchController _productSearch'),
    );
    expect(screenSource, contains('_productSearch.loadInitial()'));
    expect(screenSource, contains('_productSearch.loadMore()'));
    expect(
      screenSource,
      contains('_productSearch.setQuery(_productSearchCtrl.text)'),
    );
    expect(
      screenSource,
      contains("_productSearch.patchFilter('category', value)"),
    );
    expect(screenSource, contains('fetchProductCategories()'));
  });

  test(
    'Almacenes no mantiene carga completa de productos para transferencias',
    () {
      expect(repositorySource, isNot(contains('warehouseProductsProvider')));
      expect(repositorySource, isNot(contains('loadAllProductPages')));
      expect(screenSource, isNot(contains('warehouseProductsProvider')));
    },
  );
}
