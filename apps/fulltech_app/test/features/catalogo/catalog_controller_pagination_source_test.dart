import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CatalogController.load usa page 1 y no loadAll por defecto', () {
    final controllerSource = File(
      'lib/features/catalogo/application/catalog_controller.dart',
    ).readAsStringSync();
    final repositorySource = File(
      'lib/features/catalogo/data/catalog_repository.dart',
    ).readAsStringSync();

    final loadStart = controllerSource.indexOf('Future<void> load({');
    final loadEnd = controllerSource.indexOf(
      'Future<ProductModel?> create',
      loadStart,
    );
    final loadBody = controllerSource.substring(loadStart, loadEnd);

    expect(loadBody, contains('fetchProductsFirstPage'));
    expect(loadBody, isNot(contains('repo.fetchProducts(')));
    expect(loadBody, isNot(contains('loadAllProductPages')));

    final firstPageStart = repositorySource.indexOf(
      'Future<List<ProductModel>> fetchProductsFirstPage',
    );
    final firstPageEnd = repositorySource.indexOf(
      'Future<List<ProductModel>> _fetchProductsRemote',
      firstPageStart,
    );
    final firstPageBody = repositorySource.substring(
      firstPageStart,
      firstPageEnd,
    );

    expect(firstPageBody, contains('fetchProductsPage'));
    expect(firstPageBody, isNot(contains('loadAllProductPages')));
  });
}
