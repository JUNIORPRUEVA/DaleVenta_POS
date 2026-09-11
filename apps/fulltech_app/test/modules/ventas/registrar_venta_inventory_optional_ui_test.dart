import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/registrar_venta_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'POS search resets on logout and login as another same-company user',
    (tester) async {
      final auth = await _pumpPos(
        tester,
        inventoryEnabled: true,
        products: _filterProducts,
        surfaceSize: const Size(390, 820),
      );

      await _enterMobileSearch(tester, 'coca');

      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('Galletas'), findsNothing);

      auth.logoutForTest();
      await tester.pumpAndSettle();
      auth.setAuthenticated(userId: 'user-2', companyId: 'company-1');
      await tester.pumpAndSettle();

      await _expectMobileSearchEmpty(tester);
      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('Galletas'), findsOneWidget);
    },
  );

  testWidgets(
    'POS category resets on logout and login as another same-company user',
    (tester) async {
      final auth = await _pumpPos(
        tester,
        inventoryEnabled: true,
        products: _filterProducts,
        surfaceSize: const Size(390, 820),
      );

      await _selectCategory(tester, 'Bebidas');

      expect(find.text('1 categoria(s) activa(s)'), findsOneWidget);
      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('Galletas'), findsNothing);

      auth.logoutForTest();
      await tester.pumpAndSettle();
      auth.setAuthenticated(userId: 'user-2', companyId: 'company-1');
      await tester.pumpAndSettle();

      expect(find.text('1 categoria(s) activa(s)'), findsNothing);
      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('Galletas'), findsOneWidget);
    },
  );

  testWidgets(
    'POS filters reset for same-company user switches without logout',
    (tester) async {
      final auth = await _pumpPos(
        tester,
        inventoryEnabled: true,
        products: _filterProducts,
        surfaceSize: const Size(390, 820),
      );

      await _enterMobileSearch(tester, 'coca');

      auth.setAuthenticated(userId: 'user-2', companyId: 'company-1');
      await tester.pumpAndSettle();

      await _expectMobileSearchEmpty(tester);
      expect(find.text('Coca Cola'), findsOneWidget);
      expect(find.text('Galletas'), findsOneWidget);
    },
  );

  testWidgets('POS filters reset when company changes', (tester) async {
    final auth = await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: _filterProducts,
      surfaceSize: const Size(390, 820),
    );

    await _enterMobileSearch(tester, 'coca');

    auth.setAuthenticated(userId: 'user-1', companyId: 'company-2');
    await tester.pumpAndSettle();

    await _expectMobileSearchEmpty(tester);
    expect(find.text('Coca Cola'), findsOneWidget);
    expect(find.text('Galletas'), findsOneWidget);
  });

  testWidgets('POS app restart does not restore another user search', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: _filterProducts,
      surfaceSize: const Size(390, 820),
    );

    await _enterMobileSearch(tester, 'coca');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: _filterProducts,
      userId: 'user-2',
      companyId: 'company-1',
      surfaceSize: const Size(390, 820),
    );

    await _expectMobileSearchEmpty(tester);
    expect(find.text('Coca Cola'), findsOneWidget);
    expect(find.text('Galletas'), findsOneWidget);
  });

  test('invalid POS category falls back to all categories', () {
    expect(
      sanitizePosSelectedCategories({'Bebidas'}, [_snackProduct]),
      isEmpty,
    );
    expect(sanitizePosSelectedCategories({'Bebidas'}, [_beverageProduct]), {
      'Bebidas',
    });
  });

  testWidgets('normal POS search and category filtering still work', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: _filterProducts,
      surfaceSize: const Size(390, 820),
    );

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'coca');
    await tester.pumpAndSettle();

    expect(find.text('Coca Cola'), findsOneWidget);
    expect(find.text('Galletas'), findsNothing);

    await tester.tap(find.byTooltip('Cerrar búsqueda'));
    await tester.pumpAndSettle();
    await _selectCategory(tester, 'Snacks');

    expect(find.text('Coca Cola'), findsNothing);
    expect(find.text('Galletas'), findsOneWidget);
  });

  testWidgets(
    'inventory ON shows stock only for tracked products and keeps sale action',
    (tester) async {
      await _pumpPos(tester, inventoryEnabled: true, products: _products);

      expect(find.text('DISP'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('SIN STOCK'), findsNothing);
      expect(find.textContaining('Agregar stock'), findsNothing);

      await tester.tap(find.text('Café').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('RD\$ 120.00'), findsWidgets);
    },
  );

  testWidgets(
    'inventory OFF hides stock badges, no-stock states and keeps products sellable',
    (tester) async {
      await _pumpPos(
        tester,
        inventoryEnabled: false,
        products: [_trackedOutOfStockProduct],
      );

      expect(find.text('DISP'), findsNothing);
      expect(find.text('SIN STOCK'), findsNothing);
      expect(find.textContaining('Sin stock'), findsNothing);
      expect(find.textContaining('Agregar stock'), findsNothing);

      await tester.tap(find.text('Café').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('RD\$ 120.00'), findsWidgets);
      expect(find.textContaining('agrega stock'), findsNothing);
    },
  );

  testWidgets('settings reload updates POS stock UI', (tester) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: [_trackedOutOfStockProduct],
    );

    expect(find.text('SIN STOCK'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpPos(
      tester,
      inventoryEnabled: false,
      products: [_trackedOutOfStockProduct],
    );

    expect(find.text('SIN STOCK'), findsNothing);
    expect(find.text('DISP'), findsNothing);
    expect(find.textContaining('Agregar stock'), findsNothing);
  });

  testWidgets('manual out-of-inventory sale keeps legacy UI when UoM is off', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      measurementUnitsEnabled: false,
      products: _products,
      surfaceSize: const Size(390, 820),
    );

    await tester.tap(find.byTooltip('Producto externo'));
    await tester.pumpAndSettle();

    expect(find.text('Vender fuera del inventario'), findsOneWidget);
    expect(find.text('Unidad de medida'), findsNothing);
  });

  testWidgets('manual out-of-inventory sale rejects fractional UNIT quantity', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      measurementUnitsEnabled: true,
      products: _products,
      unitOptions: _testUnits,
      surfaceSize: const Size(390, 820),
    );

    await _openManualSaleDialog(tester);
    await tester.enterText(_textFieldByLabel('Nombre del item'), 'Manual UNIT');
    await tester.enterText(_textFieldByLabel('Cantidad'), '1.5');
    await tester.enterText(_textFieldByLabel('Precio'), '10');
    await tester.enterText(_textFieldByLabel('Costo'), '0');
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(
      find.text('La cantidad debe ser entera para Unidad.'),
      findsOneWidget,
    );
  });

  testWidgets('manual out-of-inventory sale accepts decimal YARD quantity', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      measurementUnitsEnabled: true,
      products: _products,
      unitOptions: _testUnits,
      surfaceSize: const Size(390, 820),
    );

    await _openManualSaleDialog(tester);
    await tester.enterText(_textFieldByLabel('Nombre del item'), 'Tela');
    await tester.enterText(_textFieldByLabel('Cantidad'), '1.25');
    await tester.enterText(_textFieldByLabel('Precio'), '20');
    await tester.enterText(_textFieldByLabel('Costo'), '0');
    await _selectDialogUnit(tester, 'Yarda (yd)');
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.25 yd x'), findsOneWidget);
  });

  testWidgets(
    'manual out-of-inventory sale accepts decimal POUND with submit',
    (tester) async {
      await _pumpPos(
        tester,
        inventoryEnabled: true,
        measurementUnitsEnabled: true,
        products: _products,
        unitOptions: _testUnits,
        surfaceSize: const Size(390, 820),
      );

      await _openManualSaleDialog(tester);
      await tester.enterText(_textFieldByLabel('Nombre del item'), 'Harina');
      await tester.enterText(_textFieldByLabel('Cantidad'), '2.75');
      await tester.enterText(_textFieldByLabel('Precio'), '15');
      await tester.enterText(_textFieldByLabel('Costo'), '0');
      await _selectDialogUnit(tester, 'Libra (lb)');
      await tester.tap(_textFieldByLabel('Costo'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('2.75 lb x'), findsOneWidget);
    },
  );

  testWidgets('mobile POS shows resolved warehouse when multiple are active', (
    tester,
  ) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      multiWarehouseEnabled: true,
      products: _products,
      warehouses: _multipleWarehouses,
      terminals: _defaultTerminalA,
      surfaceSize: const Size(390, 820),
    );

    expect(find.textContaining('Almacén: Warehouse A'), findsOneWidget);
  });

  testWidgets(
    'mobile POS hides warehouse indicator with a single active warehouse',
    (tester) async {
      await _pumpPos(
        tester,
        inventoryEnabled: true,
        multiWarehouseEnabled: true,
        products: _products,
        warehouses: [_warehouseA],
        terminals: _defaultTerminalA,
        surfaceSize: const Size(390, 820),
      );

      expect(find.textContaining('Almacén:'), findsNothing);
    },
  );

  for (final viewport in _mobileViewports.entries) {
    testWidgets('mobile POS UoM and warehouse controls fit ${viewport.key}', (
      tester,
    ) async {
      await _pumpPos(
        tester,
        inventoryEnabled: true,
        measurementUnitsEnabled: true,
        multiWarehouseEnabled: true,
        products: _products,
        unitOptions: _testUnits,
        warehouses: _multipleWarehouses,
        terminals: _defaultTerminalA,
        surfaceSize: viewport.value,
      );

      expect(find.textContaining('Almacén: Warehouse A'), findsOneWidget);

      await _openManualSaleDialog(tester);

      expect(find.text('Unidad de medida'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
    });
  }
}

Future<_TestAuthController> _pumpPos(
  WidgetTester tester, {
  required bool inventoryEnabled,
  required List<ProductModel> products,
  bool measurementUnitsEnabled = false,
  bool multiWarehouseEnabled = false,
  List<UnitOfMeasureModel> unitOptions = const [UnitOfMeasureModel.unit],
  List<WarehouseModel> warehouses = const <WarehouseModel>[],
  List<TerminalWarehouseModel> terminals = const <TerminalWarehouseModel>[],
  String userId = 'user-1',
  String companyId = 'company-1',
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  final settings = CompanySettings.empty().copyWith(
    inventoryEnabled: inventoryEnabled,
    measurementUnitsEnabled: measurementUnitsEnabled,
    multiWarehouseEnabled: multiWarehouseEnabled,
    taxEnabled: false,
    ncfEnabled: false,
  );
  late _TestAuthController auth;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) {
          auth = _TestAuthController(ref, userId: userId, companyId: companyId);
          return auth;
        }),
        companySettingsProvider.overrideWith((ref) async => settings),
        productTaxUiConfigProvider.overrideWith(
          (ref) async =>
              ProductTaxUiConfig(settings: settings, activeTaxes: const []),
        ),
        catalogRepositoryProvider.overrideWithValue(
          _FakeCatalogRepository(products, unitOptions),
        ),
        warehousesProvider.overrideWith((ref) async => warehouses),
        warehouseTerminalsProvider.overrideWith((ref) async => terminals),
        posNcfSequencesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: RegistrarVentaScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return auth;
}

final _trackedProduct = ProductModel(
  id: '11111111-1111-4111-8111-111111111111',
  nombre: 'Café',
  precio: 120,
  costo: 60,
  stock: 5,
);

final _trackedOutOfStockProduct = _trackedProduct.copyWith(stock: 0);

final _nonInventoryProduct = ProductModel(
  id: '22222222-2222-4222-8222-222222222222',
  nombre: 'Tarjeta regalo',
  precio: 500,
  costo: 0,
  stock: 0,
  trackInventory: false,
);

final _service = ProductModel(
  id: '33333333-3333-4333-8333-333333333333',
  nombre: 'Instalación',
  precio: 1500,
  costo: 0,
  stock: 0,
  itemType: 'SERVICE',
  trackInventory: false,
);

final _products = [_trackedProduct, _nonInventoryProduct, _service];

final _beverageProduct = ProductModel(
  id: '44444444-4444-4444-8444-444444444444',
  nombre: 'Coca Cola',
  precio: 75,
  costo: 40,
  stock: 10,
  categoria: 'Bebidas',
);

final _snackProduct = ProductModel(
  id: '55555555-5555-4555-8555-555555555555',
  nombre: 'Galletas',
  precio: 35,
  costo: 15,
  stock: 12,
  categoria: 'Snacks',
);

final _filterProducts = [_beverageProduct, _snackProduct];

const _testUnits = [
  UnitOfMeasureModel.unit,
  UnitOfMeasureModel(
    id: 'uom-yard',
    code: 'YARD',
    name: 'Yarda',
    symbol: 'yd',
    category: 'LENGTH',
    allowDecimals: true,
    precision: 2,
  ),
  UnitOfMeasureModel(
    id: 'uom-pound',
    code: 'POUND',
    name: 'Libra',
    symbol: 'lb',
    category: 'MASS',
    allowDecimals: true,
    precision: 2,
  ),
];

const _warehouseA = WarehouseModel(
  id: 'w-a',
  name: 'Warehouse A',
  code: 'A',
  isDefault: true,
  isActive: true,
  terminalCount: 1,
  stockRowCount: 1,
);

const _warehouseB = WarehouseModel(
  id: 'w-b',
  name: 'Warehouse B',
  code: 'B',
  isDefault: false,
  isActive: true,
  terminalCount: 1,
  stockRowCount: 1,
);

const _multipleWarehouses = [_warehouseA, _warehouseB];

const _defaultTerminalA = [
  TerminalWarehouseModel(
    id: 'term-a',
    name: 'Caja A',
    code: 'A',
    isActive: true,
    isDefault: true,
    defaultWarehouseId: 'w-a',
    defaultWarehouseName: 'Warehouse A',
    defaultWarehouseCode: 'A',
    deviceBound: false,
  ),
];

const _mobileViewports = {
  'Android 360x800': Size(360, 800),
  'Android 412x915': Size(412, 915),
  'iPhone 375x812': Size(375, 812),
  'iPhone 390x844': Size(390, 844),
  'iPhone 430x932': Size(430, 932),
};

Future<void> _selectCategory(WidgetTester tester, String category) async {
  await tester.tap(find.byIcon(Icons.filter_alt_outlined));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text(category).last,
      matching: find.byType(CheckboxListTile),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aplicar filtros'));
  await tester.pumpAndSettle();
}

Future<void> _enterMobileSearch(WidgetTester tester, String value) async {
  await tester.tap(find.byTooltip('Buscar'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, value);
  await tester.pumpAndSettle();
}

Future<void> _expectMobileSearchEmpty(WidgetTester tester) async {
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
  }
  final search = tester.widget<TextField>(find.byType(TextField).first);
  expect(search.controller?.text, isEmpty);
  await tester.tap(find.byTooltip('Cerrar búsqueda'));
  await tester.pumpAndSettle();
}

Finder _textFieldByLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _openManualSaleDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Producto externo'));
  await tester.pumpAndSettle();
}

Future<void> _selectDialogUnit(WidgetTester tester, String label) async {
  await tester.tap(find.text('Unidad (u)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository(this.products, this.unitOptions) : super(Dio());

  final List<ProductModel> products;
  final List<UnitOfMeasureModel> unitOptions;

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return const [];
  }

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return products;
  }

  @override
  Future<List<UnitOfMeasureModel>> fetchUnitOfMeasures() async {
    return unitOptions;
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(
    super.ref, {
    required String userId,
    required String companyId,
  }) {
    setAuthenticated(userId: userId, companyId: companyId);
  }

  void setAuthenticated({required String userId, required String companyId}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: _testUser(userId: userId, companyId: companyId),
    );
  }

  void logoutForTest() {
    state = AuthState(initialized: true, isAuthenticated: false, user: null);
  }
}

UserModel _testUser({required String userId, required String companyId}) {
  return UserModel(
    id: userId,
    email: '$userId@example.test',
    nombreCompleto: 'Usuario $userId',
    telefono: '',
    role: 'ADMIN',
    companyId: companyId,
  );
}
