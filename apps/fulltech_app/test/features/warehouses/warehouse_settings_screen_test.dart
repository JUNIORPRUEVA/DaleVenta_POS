import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
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
    final productServer = _FakeProductServer(products);
    final dio = productServer.dio();
    return ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        catalogRepositoryProvider.overrideWithValue(CatalogRepository(dio)),
        warehousesProvider.overrideWith((ref) async => warehouses),
        warehouseTerminalsProvider.overrideWith((ref) async => terminals),
        warehouseTransfersProvider.overrideWith((ref) async => transfers),
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

  final pagedProducts = List<ProductModel>.generate(56, (index) {
    final number = index + 1;
    return ProductModel(
      id: 'p-$number',
      nombre: 'Producto $number',
      codigo: 'SKU-$number',
      categoria: number.isEven ? 'Accesorios' : 'Ferretería',
      precio: 10,
      costo: 5,
      stock: 12,
      stockDecimal: '12',
    );
  });

  testWidgets('one warehouse keeps simple automatic state', (tester) async {
    await tester.pumpWidget(buildSubject(warehouses: const [mainWarehouse]));
    await tester.pumpAndSettle();

    expect(find.text('Operación simple: un almacén activo'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('Almacén Principal'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();

    expect(find.text('Transferencias'), findsOneWidget);
    expect(find.text('Origen'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(
      find.text('Buscar producto por nombre, código o categoría'),
      findsOneWidget,
    );
    expect(find.text('Producto para transferir'), findsOneWidget);
    expect(find.text('Categoría'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);

    await tester.tap(find.text('Tela Azul W10'));
    await tester.pumpAndSettle();

    expect(find.text('Disponible en origen: 20.5 yd'), findsOneWidget);
    expect(find.text('Confirmar transferencia'), findsOneWidget);
  });

  testWidgets('transfer picker loads page 1 without exposing deep products', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        warehouses: const [mainWarehouse, branchWarehouse],
        products: pagedProducts,
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();

    expect(find.text('Producto 1'), findsOneWidget);
    expect(find.text('Producto 55'), findsNothing);
    expect(find.text('Mostrando 50 de 56'), findsOneWidget);
    expect(find.text('Cargar más productos'), findsOneWidget);
  });

  testWidgets('transfer picker searches remote deep products', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        warehouses: const [mainWarehouse, branchWarehouse],
        products: pagedProducts,
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Buscar producto por nombre, código o categoría',
      ),
      'Producto 55',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Mostrando 1 de 1'), findsOneWidget);
    expect(find.text('Producto 55'), findsWidgets);
  });

  testWidgets('transfer picker loadMore appends without duplicates', (
    tester,
  ) async {
    final productsWithDuplicatePageItem = [
      ...pagedProducts.take(50),
      pagedProducts.first,
      ...pagedProducts.skip(50),
    ];
    await tester.pumpWidget(
      buildSubject(
        warehouses: const [mainWarehouse, branchWarehouse],
        products: productsWithDuplicatePageItem,
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cargar más productos'));
    await tester.tap(find.text('Cargar más productos'));
    await tester.pumpAndSettle();

    expect(find.text('Mostrando 56 de 57'), findsOneWidget);
    expect(find.text('Producto 1'), findsOneWidget);
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
    expect(find.text('Caja Principal → Almacén Principal'), findsOneWidget);
    expect(find.textContaining('Bávaro'), findsWidgets);
  });
}

class _FakeProductServer {
  _FakeProductServer(this.products);

  final List<ProductModel> products;

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == ApiRoutes.productCategories) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'items': [
                    for (final entry in _categoryCounts().entries)
                      {'name': entry.key, 'count': entry.value},
                  ],
                },
              ),
            );
            return;
          }
          if (options.path == ApiRoutes.catalogProducts) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _productsPage(options.queryParameters),
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
            ),
          );
        },
      ),
    );
    return dio;
  }

  Map<String, int> _categoryCounts() {
    final counts = <String, int>{};
    for (final product in products) {
      final category = product.categoriaLabel;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, dynamic> _productsPage(Map<String, dynamic> query) {
    final search = '${query['search'] ?? ''}'.trim().toLowerCase();
    final category = '${query['category'] ?? ''}'.trim();
    final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
    final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
    final filtered = products.where((product) {
      if (category.isNotEmpty && product.categoriaLabel != category) {
        return false;
      }
      if (search.isEmpty) return true;
      return product.nombre.toLowerCase().contains(search) ||
          (product.codigo ?? '').toLowerCase().contains(search) ||
          product.categoriaLabel.toLowerCase().contains(search);
    }).toList();
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, filtered.length);
    final items = start >= filtered.length
        ? const <ProductModel>[]
        : filtered.sublist(start, end);
    return {
      'items': items.map((product) => product.toJson()).toList(),
      'page': page,
      'limit': limit,
      'total': filtered.length,
      'hasMore': end < filtered.length,
      'nextPage': end < filtered.length ? page + 1 : null,
    };
  }
}
