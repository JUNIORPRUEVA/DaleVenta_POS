import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/features/warehouses/ui/warehouse_settings_screen.dart';

void main() {
  Widget buildSubject({
    required List<WarehouseModel> warehouses,
    List<TerminalWarehouseModel> terminals = const [],
    List<WarehouseTransferModel> transfers = const [],
    List<ProductModel> products = const [],
    Map<String, ProductWarehouseStockBreakdown> stockBreakdowns = const {},
    Size size = const Size(1100, 780),
  }) {
    return ProviderScope(
      overrides: [
        warehousesProvider.overrideWith((ref) async => warehouses),
        warehouseTerminalsProvider.overrideWith((ref) async => terminals),
        warehouseTransfersProvider.overrideWith((ref) async => transfers),
        warehouseProductsProvider.overrideWith((ref) async => products),
        productWarehouseStockProvider.overrideWith((ref, productId) async {
          return stockBreakdowns[productId] ??
              ProductWarehouseStockBreakdown(
                productId: productId,
                source: 'LOCAL',
                readOnly: false,
                reconciled: true,
                total: 0,
                warehouseTotal: 0,
                warehouses: const [],
              );
        }),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const WarehouseSettingsScreen(),
        ),
      ),
    );
  }

  const mainWarehouse = WarehouseModel(
    id: 'w-main',
    name: 'Main Warehouse',
    code: 'MAIN',
    isDefault: true,
    isActive: true,
    terminalCount: 1,
    stockRowCount: 10,
  );

  const branchWarehouse = WarehouseModel(
    id: 'w-bavaro',
    name: 'Bávaro',
    code: 'BAV',
    isDefault: false,
    isActive: true,
    terminalCount: 0,
    stockRowCount: 0,
  );

  final yardProduct = ProductModel(
    id: 'p-yard',
    nombre: 'Tela Azul W10',
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

  testWidgets('one warehouse keeps simple automatic state', (tester) async {
    await tester.pumpWidget(buildSubject(warehouses: const [mainWarehouse]));
    await tester.pumpAndSettle();

    expect(find.text('Operación simple: un almacén activo'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);
    expect(find.text('Predeterminado'), findsOneWidget);
    expect(find.text('Transferencias automáticas'), findsOneWidget);
  });

  testWidgets(
    'multi warehouse shows compact breakdown and create form on mobile',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          warehouses: const [mainWarehouse, branchWarehouse],
          size: const Size(390, 820),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 almacenes activos'), findsOneWidget);
      expect(find.text('Multi-almacén'), findsOneWidget);
      expect(find.text('Bávaro'), findsOneWidget);

      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(find.text('Crear almacén'), findsOneWidget);
      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Código'), findsOneWidget);
    },
  );

  testWidgets('multi warehouse exposes transfer form and source stock', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        warehouses: const [mainWarehouse, branchWarehouse],
        products: [yardProduct],
        stockBreakdowns: {
          yardProduct.id: ProductWarehouseStockBreakdown(
            productId: yardProduct.id,
            source: 'LOCAL',
            readOnly: false,
            reconciled: true,
            total: 20.5,
            warehouseTotal: 20.5,
            warehouses: const [
              WarehouseStockLine(
                warehouseId: 'w-main',
                warehouseName: 'Main Warehouse',
                warehouseCode: 'MAIN',
                isDefault: true,
                isActive: true,
                quantity: 20.5,
                quantityDecimal: '20.5',
              ),
              WarehouseStockLine(
                warehouseId: 'w-bavaro',
                warehouseName: 'Bávaro',
                warehouseCode: 'BAV',
                isDefault: false,
                isActive: true,
                quantity: 0,
                quantityDecimal: '0',
              ),
            ],
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();

    expect(find.text('Transferencias'), findsOneWidget);
    expect(find.text('Origen'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(find.text('Producto'), findsOneWidget);

    await tester.tap(find.text('Producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tela Azul W10').last);
    await tester.pumpAndSettle();

    expect(find.text('Disponible en origen: 20.5 yd'), findsOneWidget);
    expect(find.text('Confirmar transferencia'), findsOneWidget);
  });

  testWidgets('terminal assignment shows warehouse relationship', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        warehouses: const [mainWarehouse, branchWarehouse],
        terminals: const [
          TerminalWarehouseModel(
            id: 't-main',
            name: 'Caja Principal',
            code: 'MAIN-POS',
            isActive: true,
            isDefault: true,
            defaultWarehouseId: 'w-main',
            defaultWarehouseName: 'Main Warehouse',
            defaultWarehouseCode: 'MAIN',
            deviceBound: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();

    expect(find.text('Terminales'), findsOneWidget);
    expect(find.text('Caja Principal → Main Warehouse'), findsOneWidget);
    expect(find.textContaining('Bávaro'), findsWidgets);
  });
}
