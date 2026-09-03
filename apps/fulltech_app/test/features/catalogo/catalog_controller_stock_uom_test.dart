import 'dart:convert';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/application/catalog_controller.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _unit = UnitOfMeasureModel.unit;
const _pound = UnitOfMeasureModel(
  id: 'POUND',
  code: 'POUND',
  name: 'Libra',
  symbol: 'lb',
  category: 'WEIGHT',
  allowDecimals: true,
  precision: 3,
);
const _yard = UnitOfMeasureModel(
  id: 'YARD',
  code: 'YARD',
  name: 'Yarda',
  symbol: 'yd',
  category: 'LENGTH',
  allowDecimals: true,
  precision: 3,
);

ProductModel _product({
  required String id,
  double stock = 0,
  UnitOfMeasureModel unit = _unit,
}) {
  return ProductModel(
    id: id,
    nombre: 'Producto $id',
    precio: 100,
    costo: 60,
    stock: stock,
    categoria: 'General',
    unitOfMeasureId: unit.id,
    unitOfMeasure: unit,
  );
}

class _StockFakeCatalogRepository extends CatalogRepository {
  _StockFakeCatalogRepository(this.products) : super(Dio());

  List<ProductModel> products;
  double? lastStock;
  double? lastDelta;
  String? lastWarehouseId;

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return products;
  }

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return products;
  }

  @override
  Future<void> saveProductsSnapshot(List<ProductModel> items) async {
    // No-op: se valida el envío al backend, no la persistencia local.
  }

  @override
  Future<ProductModel> adjustProductStock({
    required String id,
    double? stock,
    double? delta,
    String? warehouseId,
    String? reason,
    bool skipLoader = false,
  }) async {
    lastStock = stock;
    lastDelta = delta;
    lastWarehouseId = warehouseId;
    final current = products.firstWhere((product) => product.id == id);
    final nextStock = stock ?? ((current.stock ?? 0) + (delta ?? 0));
    final updated = current.copyWith(stock: nextStock);
    products = [
      for (final product in products)
        if (product.id == id) updated else product,
    ];
    return updated;
  }
}

ProviderContainer _containerWith(_StockFakeCatalogRepository repo) {
  final container = ProviderContainer(
    overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<CatalogController> _loadedController(
  _StockFakeCatalogRepository repo,
) async {
  final container = _containerWith(repo);
  final controller = container.read(catalogControllerProvider.notifier);
  await controller.load();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ajuste contado UNIT envía entero y sin delta', () async {
    final repo = _StockFakeCatalogRepository([
      _product(id: 'unit-1', stock: 10, unit: _unit),
    ]);
    final controller = await _loadedController(repo);

    await controller.adjustStock(product: repo.products.single, stock: 15);

    expect(repo.lastDelta, isNull);
    expect(repo.lastStock, 15);
  });

  test('ajuste contado POUND envía decimal 10 + 5.5 = 15.5', () async {
    final repo = _StockFakeCatalogRepository([
      _product(id: 'lb-1', stock: 10, unit: _pound),
    ]);
    final controller = await _loadedController(repo);

    await controller.adjustStock(product: repo.products.single, stock: 15.5);

    expect(repo.lastDelta, isNull);
    expect(repo.lastStock, 15.5);
    expect(jsonEncode(repo.lastStock), '15.5');
  });

  test(
    'ajuste multi-almacén POUND envía delta sin artefacto flotante',
    () async {
      final repo = _StockFakeCatalogRepository([
        _product(id: 'lb-2', stock: 3.15, unit: _pound),
      ]);
      final controller = await _loadedController(repo);

      // El usuario pidió +2.35 sobre un almacén con 3.15 lb (objetivo 5.5).
      await controller.adjustStock(
        product: repo.products.single,
        stock: 5.5,
        warehouseId: 'w-1',
        currentWarehouseStock: 3.15,
      );

      expect(repo.lastStock, isNull);
      expect(repo.lastDelta, 2.35);
      expect(jsonEncode(repo.lastDelta), '2.35');
      expect(repo.lastWarehouseId, 'w-1');
    },
  );

  test('ajuste multi-almacén YARD envía delta 20 -> 25.5 = 5.5', () async {
    final repo = _StockFakeCatalogRepository([
      _product(id: 'yd-1', stock: 20, unit: _yard),
    ]);
    final controller = await _loadedController(repo);

    await controller.adjustStock(
      product: repo.products.single,
      stock: 25.5,
      warehouseId: 'w-1',
      currentWarehouseStock: 20,
    );

    expect(repo.lastStock, isNull);
    expect(repo.lastDelta, 5.5);
    expect(jsonEncode(repo.lastDelta), '5.5');
  });

  test('ajuste contado YARD 20 + 2.375 = 22.375 preserva decimales', () async {
    final repo = _StockFakeCatalogRepository([
      _product(id: 'yd-2', stock: 20, unit: _yard),
    ]);
    final controller = await _loadedController(repo);

    await controller.adjustStock(product: repo.products.single, stock: 22.375);

    expect(repo.lastDelta, isNull);
    expect(repo.lastStock, 22.375);
    expect(jsonEncode(repo.lastStock), '22.375');
  });

  test(
    'ajuste contado POUND con artefacto 10.1 + 2.3 se envía limpio',
    () async {
      final repo = _StockFakeCatalogRepository([
        _product(id: 'lb-3', stock: 10.1, unit: _pound),
      ]);
      final controller = await _loadedController(repo);

      final target = 10.1 + 2.3; // ~12.399999999999999 en punto flotante
      await controller.adjustStock(
        product: repo.products.single,
        stock: target,
      );

      expect(repo.lastDelta, isNull);
      expect(repo.lastStock, 12.4);
      expect(jsonEncode(repo.lastStock), '12.4');
    },
  );
}
