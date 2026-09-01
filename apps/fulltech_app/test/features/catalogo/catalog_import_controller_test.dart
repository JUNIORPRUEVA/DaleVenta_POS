import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/application/catalog_controller.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';

class _ImportFakeCatalogRepository extends CatalogRepository {
  _ImportFakeCatalogRepository(this.products) : super(Dio());

  List<ProductModel> products;
  int creates = 0;
  int updates = 0;
  int deletes = 0;
  int archives = 0;
  bool failDelete = false;
  bool requireArchiveOnDelete = false;
  String? lastTaxTreatment;
  double? lastTaxRate;
  String? lastTaxPriceMode;

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return products;
  }

  @override
  Future<ProductModel> createProduct({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    bool skipLoader = false,
  }) async {
    creates += 1;
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
    final product = ProductModel(
      id: 'created-$creates',
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: fotoUrl,
      taxTreatment: taxTreatment ?? 'INHERIT',
      taxRate: taxRate,
      taxPriceMode: taxPriceMode,
    );
    products = [product, ...products];
    return product;
  }

  @override
  Future<ProductModel> updateProduct({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    bool skipLoader = false,
  }) async {
    updates += 1;
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
    final product = ProductModel(
      id: id,
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: fotoUrl,
      taxTreatment: taxTreatment ?? 'INHERIT',
      taxRate: taxRate,
      taxPriceMode: taxPriceMode,
    );
    products = [
      for (final item in products)
        if (item.id == id) product else item,
    ];
    return product;
  }

  @override
  Future<void> deleteProduct(String id, {bool skipLoader = false}) async {
    deletes += 1;
    if (requireArchiveOnDelete) {
      throw ProductDeleteRequiresArchiveException(productId: id);
    }
    if (failDelete) {
      throw ApiException('No se pudo eliminar el producto');
    }
    products = [
      for (final item in products)
        if (item.id != id) item,
    ];
  }

  @override
  Future<ProductModel> archiveProduct(
    String id, {
    bool skipLoader = false,
  }) async {
    archives += 1;
    final product = products.firstWhere((item) => item.id == id);
    products = [
      for (final item in products)
        if (item.id != id) item,
    ];
    return product.copyWith(
      archivedAt: DateTime.utc(2026, 9, 1),
      activo: false,
    );
  }
}

void main() {
  test(
    'importación actualiza producto existente sin código al confirmar',
    () async {
      final repo = _ImportFakeCatalogRepository([
        ProductModel(
          id: 'p-1',
          nombre: 'TECLADO CON PUERTO USB',
          precio: 800,
          costo: 400,
          stock: 2,
          categoria: 'COMPUTADORAS Y POS',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final controller = container.read(catalogControllerProvider.notifier);
      await controller.load();

      final result = await controller.importProducts(const [
        CatalogImportDraft(
          nombre: 'TECLADO CON PUERTO USB',
          codigo: '1016',
          precio: 800,
          costo: 400,
          stock: 2,
          categoria: 'COMPUTADORAS Y POS',
        ),
      ], updateExisting: true);

      expect(result.created, 0);
      expect(result.updated, 1);
      expect(repo.creates, 0);
      expect(repo.updates, 1);
      expect(repo.products.single.id, 'p-1');
      expect(repo.products.single.codigo, '1016');
    },
  );

  test(
    'importación omite repetidos del archivo y existentes sin confirmar',
    () async {
      final repo = _ImportFakeCatalogRepository([
        ProductModel(
          id: 'p-1',
          nombre: 'Mouse USB',
          codigo: 'M-001',
          precio: 250,
          costo: 100,
          stock: 3,
          categoria: 'COMPUTADORAS Y POS',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final controller = container.read(catalogControllerProvider.notifier);
      await controller.load();

      final result = await controller.importProducts(const [
        CatalogImportDraft(
          nombre: 'Mouse USB',
          codigo: 'M-001',
          precio: 250,
          costo: 100,
          stock: 3,
          categoria: 'COMPUTADORAS Y POS',
        ),
        CatalogImportDraft(
          nombre: 'Cable HDMI',
          codigo: 'C-001',
          precio: 300,
          costo: 150,
          stock: 5,
          categoria: 'COMPUTADORAS Y POS',
        ),
        CatalogImportDraft(
          nombre: 'Cable HDMI',
          codigo: 'C-001',
          precio: 300,
          costo: 150,
          stock: 5,
          categoria: 'COMPUTADORAS Y POS',
        ),
      ]);

      expect(result.created, 1);
      expect(result.updated, 0);
      expect(result.skippedExisting, 1);
      expect(result.skippedFileDuplicates, 1);
      expect(repo.creates, 1);
      expect(repo.updates, 0);
    },
  );

  test(
    'importación legacy sin columnas fiscales conserva predeterminado',
    () async {
      final repo = _ImportFakeCatalogRepository([]);
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final controller = container.read(catalogControllerProvider.notifier);
      await controller.load();

      final result = await controller.importProducts(const [
        CatalogImportDraft(
          nombre: 'Producto legacy',
          codigo: 'LEG-001',
          precio: 100,
          costo: 50,
          stock: 2,
          categoria: 'General',
        ),
      ]);

      expect(result.created, 1);
      expect(repo.lastTaxTreatment, isNull);
      expect(repo.products.single.taxTreatment, 'INHERIT');
    },
  );

  test(
    'importación fiscal pasa tratamiento tasa y modo al repository',
    () async {
      final repo = _ImportFakeCatalogRepository([]);
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final controller = container.read(catalogControllerProvider.notifier);
      await controller.load();

      final result = await controller.importProducts(const [
        CatalogImportDraft(
          nombre: 'Producto gravado',
          codigo: 'FIS-001',
          precio: 1180,
          costo: 600,
          stock: 1,
          categoria: 'Fiscal',
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_INCLUDED',
        ),
      ]);

      expect(result.created, 1);
      expect(repo.lastTaxTreatment, 'TAXABLE');
      expect(repo.lastTaxRate, 0.18);
      expect(repo.lastTaxPriceMode, 'TAX_INCLUDED');
      expect(repo.products.single.taxTreatment, 'TAXABLE');
    },
  );

  test('eliminación optimista quita producto al instante', () async {
    final repo = _ImportFakeCatalogRepository([
      ProductModel(
        id: 'p-1',
        nombre: 'Mouse USB',
        precio: 250,
        costo: 100,
        stock: 3,
        categoria: 'COMPUTADORAS Y POS',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    unawaited(controller.remove('p-1'));
    expect(container.read(catalogControllerProvider).items, isEmpty);
    await Future<void>.delayed(Duration.zero);

    expect(repo.deletes, 1);
    expect(container.read(catalogControllerProvider).items, isEmpty);
  });

  test('eliminación optimista restaura producto si falla servidor', () async {
    final product = ProductModel(
      id: 'p-1',
      nombre: 'Mouse USB',
      precio: 250,
      costo: 100,
      stock: 3,
      categoria: 'COMPUTADORAS Y POS',
    );
    final repo = _ImportFakeCatalogRepository([product])..failDelete = true;
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await expectLater(controller.remove('p-1'), throwsA(isA<ApiException>()));

    expect(repo.deletes, 1);
    expect(container.read(catalogControllerProvider).items.single.id, 'p-1');
    expect(container.read(catalogControllerProvider).actionError, isNotNull);
  });

  test('delete con historial restaura y permite archivar producto', () async {
    final product = ProductModel(
      id: 'p-1',
      nombre: 'Mouse USB',
      precio: 250,
      costo: 100,
      stock: 3,
      categoria: 'COMPUTADORAS Y POS',
    );
    final repo = _ImportFakeCatalogRepository([product])
      ..requireArchiveOnDelete = true;
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await expectLater(
      controller.remove('p-1'),
      throwsA(isA<ProductDeleteRequiresArchiveException>()),
    );
    expect(container.read(catalogControllerProvider).items.single.id, 'p-1');

    await controller.archive('p-1');
    expect(repo.archives, 1);
    expect(container.read(catalogControllerProvider).items, isEmpty);
  });
}
