import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/application/catalog_controller.dart';
import 'package:daleventa_pos/features/warehouses/data/inventory_reporting_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/features/warehouses/ui/inventory_kardex_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCatalogController extends CatalogController {
  _FakeCatalogController(super.ref, CatalogState state) {
    this.state = state;
  }

  @override
  Future<void> load({bool silent = false, bool forceRemote = false}) async {}
}

void main() {
  const mainWarehouse = WarehouseModel(
    id: 'w-main',
    name: 'Principal',
    code: 'PRI',
    isDefault: true,
    isActive: true,
    terminalCount: 1,
    stockRowCount: 1,
  );

  const branchWarehouse = WarehouseModel(
    id: 'w-bavaro',
    name: 'Bávaro',
    code: 'BAV',
    isDefault: false,
    isActive: true,
    terminalCount: 0,
    stockRowCount: 1,
  );

  final product = ProductModel(
    id: 'p-yard',
    nombre: 'Tela Azul',
    codigo: 'YD-1',
    precio: 2,
    costo: 1,
    stock: 20.5,
    stockDecimal: '20.5',
    unitOfMeasure: const UnitOfMeasureModel(
      id: 'YARD',
      code: 'YARD',
      name: 'Yarda',
      symbol: 'yd',
      category: 'LENGTH',
      allowDecimals: true,
      precision: 3,
    ),
  );

  InventoryMovementModel movement({
    String type = 'TRANSFER_OUT',
    String direction = 'OUT',
    String delta = '-0.5',
  }) {
    return InventoryMovementModel(
      id: 'm-1',
      createdAt: DateTime.utc(2026, 8, 31, 10),
      type: type,
      label: type == 'SALE' ? 'Venta' : 'Transferencia enviada',
      direction: direction,
      productName: 'Tela Azul',
      productSku: 'YD-1',
      warehouseName: 'Principal',
      warehouseCode: 'PRI',
      warehouseActive: true,
      quantityDeltaDecimal: delta,
      previousQuantityDecimal: '20.5',
      resultingQuantityDecimal: '20',
      unitSymbol: 'yd',
      referenceLabel: 'Transferencia Principal -> Bávaro',
      sourceWarehouseName: 'Principal',
      destinationWarehouseName: 'Bávaro',
      createdByName: 'Admin UAT',
    );
  }

  Widget buildSubject({
    Size size = const Size(390, 844),
    InventoryMovementsPage? movements,
    InventoryStockReport? stockReport,
    InventoryReconciliation? reconciliation,
  }) {
    final movementsPage =
        movements ??
        InventoryMovementsPage(
          source: 'LOCAL',
          readOnly: true,
          total: 1,
          take: 25,
          skip: 0,
          hasMore: false,
          items: [movement()],
        );
    final report =
        stockReport ??
        InventoryStockReport(
          source: 'LOCAL',
          readOnly: true,
          warehouseCount: 2,
          productCount: 1,
          incompatibleUnitsSummed: false,
          warehouses: const [
            InventoryReportWarehouse(
              id: 'w-main',
              name: 'Principal',
              code: 'PRI',
              isDefault: true,
              isActive: true,
            ),
            InventoryReportWarehouse(
              id: 'w-bavaro',
              name: 'Bávaro',
              code: 'BAV',
              isDefault: false,
              isActive: false,
            ),
          ],
          quantityBuckets: const [
            InventoryQuantityBucket(unitSymbol: 'yd', productCount: 1),
          ],
          rows: const [
            InventoryStockReportRow(
              productId: 'p-yard',
              productName: 'Tela Azul',
              sku: 'YD-1',
              unitSymbol: 'yd',
              companyTotalDecimal: '20.5',
              compatibilityStockDecimal: '20.5',
              reconciled: true,
              warehouses: [
                InventoryStockByWarehouse(
                  warehouseId: 'w-main',
                  warehouseName: 'Principal',
                  warehouseCode: 'PRI',
                  isActive: true,
                  quantityDecimal: '20.5',
                ),
                InventoryStockByWarehouse(
                  warehouseId: 'w-bavaro',
                  warehouseName: 'Bávaro',
                  warehouseCode: 'BAV',
                  isActive: false,
                  quantityDecimal: '0',
                ),
              ],
            ),
          ],
        );
    final reconcile =
        reconciliation ??
        const InventoryReconciliation(
          source: 'LOCAL',
          readOnly: true,
          totalProducts: 1,
          driftCount: 0,
          items: [],
        );
    return ProviderScope(
      overrides: [
        catalogControllerProvider.overrideWith(
          (ref) => _FakeCatalogController(ref, CatalogState(items: [product])),
        ),
        warehousesProvider.overrideWith(
          (ref) async => const [mainWarehouse, branchWarehouse],
        ),
        inventoryMovementsProvider.overrideWith(
          (ref, filters) async => movementsPage,
        ),
        inventoryStockReportProvider.overrideWith((ref) async => report),
        inventoryReconciliationProvider.overrideWith((ref) async => reconcile),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const InventoryKardexScreen(),
        ),
      ),
    );
  }

  test('compactDecimal preserves useful decimal precision', () {
    expect(compactDecimal('7.625000'), '7.625');
    expect(compactDecimal('0.125000'), '0.125');
    expect(compactDecimal('2.000000'), '2');
  });

  testWidgets(
    'mobile movement card shows transfer, delta, warehouse and balance',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Transferencia enviada'), findsOneWidget);
      expect(find.text('-0.5 yd'), findsOneWidget);
      expect(find.text('Tela Azul'), findsOneWidget);
      expect(find.text('20.5 -> 20 yd'), findsOneWidget);
      expect(find.textContaining('Principal'), findsWidgets);
    },
  );

  testWidgets('movement detail is read-only and uses friendly reference', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transferencia enviada'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle de movimiento'), findsOneWidget);
    expect(find.text('Transferencia Principal -> Bávaro'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.textContaining('Eliminar'), findsNothing);
  });

  testWidgets('desktop filters expose product warehouse and movement type', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(size: const Size(1200, 800)));
    await tester.pumpAndSettle();

    expect(find.text('Producto'), findsWidgets);
    expect(find.text('Almacén'), findsWidgets);
    expect(find.text('Tipo'), findsWidgets);
    expect(find.text('Aplicar'), findsOneWidget);
  });

  testWidgets(
    'stock report keeps inactive warehouse visible and grouped by UoM',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stock por almacén'));
      await tester.pumpAndSettle();

      expect(find.text('1 productos yd'), findsOneWidget);
      expect(find.textContaining('Bávaro · Inactivo'), findsOneWidget);
      expect(find.text('20.5 yd'), findsWidgets);
      expect(find.textContaining('17.5 total units'), findsNothing);
    },
  );

  testWidgets('reconciliation shows simple no-drift state', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conciliación'));
    await tester.pumpAndSettle();

    expect(find.text('0 diferencias'), findsOneWidget);
    expect(find.text('Inventario conciliado'), findsOneWidget);
  });
}
