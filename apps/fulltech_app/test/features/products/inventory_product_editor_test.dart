import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/core/uom/uom_formatters.dart';
import 'package:daleventa_pos/core/utils/money_formatters.dart';
import 'package:daleventa_pos/core/widgets/fulltech_dialog.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository() : super(Dio());

  int creates = 0;
  int updates = 0;
  int uploads = 0;
  String? lastTaxTreatment;
  double? lastTaxRate;
  String? lastTaxPriceMode;
  String? lastFotoUrl;
  String? lastCategory;
  String? lastUnitOfMeasureId;
  UnitOfMeasureModel? lastUnitOfMeasure;
  double? lastAdjustedStock;
  bool dropImageOnUpdateResponse = false;
  Completer<String>? uploadCompleter;
  List<ProductModel> products = [
    _product(id: 'p-1', name: 'Auriculares Pro', category: 'Audio'),
    _product(id: 'p-2', name: 'Adaptador HDMI', category: 'Cables'),
  ];

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
    // No-op: widget tests validate inventory UI, not secure persistence.
  }

  @override
  Future<List<UnitOfMeasureModel>> fetchUnitOfMeasures() async {
    return const [
      UnitOfMeasureModel.unit,
      UnitOfMeasureModel(
        id: 'YARD',
        code: 'YARD',
        name: 'Yarda',
        symbol: 'yd',
        category: 'LENGTH',
        allowDecimals: true,
        precision: 3,
      ),
    ];
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
    lastFotoUrl = fotoUrl;
    lastCategory = categoria;
    lastUnitOfMeasureId = unitOfMeasureId;
    lastUnitOfMeasure = unitOfMeasure;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProductModel(
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
      unitOfMeasureId: unitOfMeasureId,
      unitOfMeasure: unitOfMeasure,
    );
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
    lastFotoUrl = fotoUrl;
    lastCategory = categoria;
    lastUnitOfMeasureId = unitOfMeasureId;
    lastUnitOfMeasure = unitOfMeasure;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProductModel(
      id: id,
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: dropImageOnUpdateResponse ? null : fotoUrl,
      taxTreatment: taxTreatment ?? 'INHERIT',
      taxRate: taxRate,
      taxPriceMode: taxPriceMode,
      unitOfMeasureId: unitOfMeasureId,
      unitOfMeasure: unitOfMeasure,
    );
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
    final current = products.firstWhere((product) => product.id == id);
    final nextStock = stock ?? ((current.stock ?? 0) + (delta ?? 0));
    lastAdjustedStock = nextStock;
    products = products
        .map(
          (product) =>
              product.id == id ? product.copyWith(stock: nextStock) : product,
        )
        .toList(growable: false);
    return products.firstWhere((product) => product.id == id);
  }

  @override
  Future<String> uploadImage({
    List<int>? bytes,
    String? filePath,
    required String filename,
  }) async {
    uploads += 1;
    final completer = uploadCompleter;
    if (completer != null) return completer.future;
    return '/uploads/$filename';
  }
}

List<Override> _singleWarehouseOverrides({
  ProductModel? product,
  CompanySettings? companySettings,
}) => [
  companySettingsProvider.overrideWith(
    (ref) async => companySettings ?? CompanySettings.empty(),
  ),
  warehouseInventoryOverviewProvider.overrideWith(
    (ref) async => const WarehouseInventoryOverview(
      warehouses: [
        WarehouseModel(
          id: 'w-default',
          name: 'Principal',
          code: 'MAIN',
          isDefault: true,
          isActive: true,
          terminalCount: 0,
          stockRowCount: 0,
        ),
      ],
      terminals: [],
    ),
  ),
  productWarehouseStockProvider.overrideWith(
    (ref, productId) async => ProductWarehouseStockBreakdown(
      productId: productId,
      source: 'LOCAL',
      readOnly: false,
      reconciled: true,
      total: product?.stock,
      warehouseTotal: product?.stock,
      warehouses: [
        WarehouseStockLine(
          warehouseId: 'w-default',
          warehouseName: 'Principal',
          warehouseCode: 'MAIN',
          isDefault: true,
          isActive: true,
          quantity: product?.stock ?? 0,
          quantityDecimal: (product?.stock ?? 0).toString(),
        ),
      ],
    ),
  ),
];

List<Override> _multiWarehouseOverrides({
  required Map<String, Map<String, double>> stockByProductAndWarehouse,
  CompanySettings? companySettings,
}) => [
  companySettingsProvider.overrideWith(
    (ref) async =>
        companySettings ??
        CompanySettings.empty().copyWith(multiWarehouseEnabled: true),
  ),
  warehouseInventoryOverviewProvider.overrideWith(
    (ref) async => const WarehouseInventoryOverview(
      warehouses: [
        WarehouseModel(
          id: 'w-default',
          name: 'Almacén Principal',
          code: 'MAIN',
          isDefault: true,
          isActive: true,
          terminalCount: 0,
          stockRowCount: 0,
        ),
        WarehouseModel(
          id: 'w-secondary',
          name: 'Sucursal Norte',
          code: 'NORTE',
          isDefault: false,
          isActive: true,
          terminalCount: 0,
          stockRowCount: 0,
        ),
      ],
      terminals: [],
    ),
  ),
  productWarehouseStockProvider.overrideWith((ref, productId) async {
    final values = stockByProductAndWarehouse[productId] ?? const {};
    final total = values.values.fold<double>(0, (sum, value) => sum + value);
    return ProductWarehouseStockBreakdown(
      productId: productId,
      source: 'LOCAL',
      readOnly: false,
      reconciled: true,
      total: total,
      warehouseTotal: total,
      warehouses: [
        WarehouseStockLine(
          warehouseId: 'w-default',
          warehouseName: 'Almacén Principal',
          warehouseCode: 'MAIN',
          isDefault: true,
          isActive: true,
          quantity: values['w-default'] ?? 0,
          quantityDecimal: (values['w-default'] ?? 0).toString(),
        ),
        WarehouseStockLine(
          warehouseId: 'w-secondary',
          warehouseName: 'Sucursal Norte',
          warehouseCode: 'NORTE',
          isDefault: false,
          isActive: true,
          quantity: values['w-secondary'] ?? 0,
          quantityDecimal: (values['w-secondary'] ?? 0).toString(),
        ),
      ],
    );
  }),
];

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return result;
  }
}

class _HangingFilePicker extends FilePicker {
  final Completer<FilePickerResult?> _pending = Completer<FilePickerResult?>();

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    return _pending.future;
  }
}

ProductModel _product({
  required String id,
  required String name,
  required String category,
  String? code,
  double stock = 1,
  UnitOfMeasureModel? unitOfMeasure,
}) {
  return ProductModel(
    id: id,
    nombre: name,
    precio: 100,
    costo: 60,
    stock: stock,
    codigo: code,
    categoria: category,
    unitOfMeasureId: unitOfMeasure?.id,
    unitOfMeasure: unitOfMeasure,
  );
}

Future<ProductFormResult?> _pumpEditor(
  WidgetTester tester, {
  required _FakeCatalogRepository repo,
  ProductModel? product,
  ProductTaxUiConfig? taxConfig,
  CompanySettings? companySettings,
}) async {
  ProductFormResult? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        productTaxUiConfigProvider.overrideWith(
          (ref) async =>
              taxConfig ??
              ProductTaxUiConfig(
                settings: CompanySettings.empty(),
                activeTaxes: const [],
              ),
        ),
        ..._singleWarehouseOverrides(
          product: product,
          companySettings: companySettings,
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ProductFormResult>(
                          MaterialPageRoute<ProductFormResult>(
                            builder: (_) => InventoryProductEditorPage(
                              product: product,
                              categories: const ['General', 'Herramientas'],
                            ),
                          ),
                        );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _pumpMobileInventory(
  WidgetTester tester, {
  required _FakeCatalogRepository repo,
  String? initialMobileTab,
  CompanySettings? companySettings,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        productTaxUiConfigProvider.overrideWith(
          (ref) async => ProductTaxUiConfig(
            settings: companySettings ?? CompanySettings.empty(),
            activeTaxes: const [],
          ),
        ),
        ..._singleWarehouseOverrides(companySettings: companySettings),
      ],
      child: MaterialApp(
        home: InventoryModulePages(initialMobileTab: initialMobileTab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Simula un producto con historial: el backend rechaza el cambio de unidad.
class _UomProtectedCatalogRepository extends _FakeCatalogRepository {
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
    throw ApiException(
      'No se puede cambiar la unidad de medida de un producto con stock o historial.',
      400,
    );
  }
}

Future<void> _pumpStockAdjustments(
  WidgetTester tester, {
  required ProductModel product,
  required void Function(ProductModel product, double stock) onApplied,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _singleWarehouseOverrides(
        product: product,
        companySettings: CompanySettings.empty().copyWith(
          measurementUnitsEnabled: true,
        ),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: StockAdjustmentsPage(
              products: [product],
              onRefresh: () async {},
              onSetStock:
                  (
                    selected,
                    stock, {
                    warehouseId,
                    currentWarehouseStock,
                  }) async {
                    onApplied(selected, stock);
                  },
              canAddStock: true,
              showMeasurementUnits: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpStockAdjustmentsHarness(
  WidgetTester tester, {
  required ProductModel product,
  required SetProductStockCallback onSetStock,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _singleWarehouseOverrides(
        product: product,
        companySettings: CompanySettings.empty().copyWith(
          measurementUnitsEnabled: true,
        ),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: StockAdjustmentsPage(
              products: [product],
              onRefresh: () async {},
              onSetStock: onSetStock,
              canAddStock: true,
              showMeasurementUnits: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _poundUom = UnitOfMeasureModel(
  id: 'POUND',
  code: 'POUND',
  name: 'Libra',
  symbol: 'lb',
  category: 'WEIGHT',
  allowDecimals: true,
  precision: 3,
);

ProductModel _poundProduct({double stock = 10}) {
  return ProductModel(
    id: 'lb-1',
    nombre: 'Carne al peso',
    precio: 200,
    costo: 120,
    stock: stock,
    categoria: 'Carnes',
    unitOfMeasureId: _poundUom.id,
    unitOfMeasure: _poundUom,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.clearAll();
  });

  test('formatea cantidades UoM sin ceros sobrantes', () {
    const yard = UnitOfMeasureModel(
      id: 'YARD',
      code: 'YARD',
      name: 'Yarda',
      symbol: 'yd',
      category: 'LENGTH',
      allowDecimals: true,
      precision: 3,
    );

    expect(formatQuantityWithUnit(14.5, unit: yard), '14.5 yd');
    expect(formatQuantityWithUnit(7.625, unit: yard), '7.625 yd');
    expect(
      formatQuantityWithUnit(
        25,
        unit: UnitOfMeasureModel.unit,
        includeUnitForUnit: true,
      ),
      '25 u',
    );
  });

  testWidgets('ajuste de stock POUND acepta decimal 10 + 2.375 = 12.375 lb', (
    tester,
  ) async {
    ProductModel? appliedProduct;
    double? appliedStock;
    await _pumpStockAdjustments(
      tester,
      product: _poundProduct(stock: 10),
      onApplied: (product, stock) {
        appliedProduct = product;
        appliedStock = stock;
      },
    );

    expect(find.textContaining('Stock actual: 10 lb'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '2.375');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nuevo stock: 12.375 lb'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aplicar ajuste'),
    );
    expect(apply.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar ajuste'));
    await tester.pumpAndSettle();

    expect(appliedProduct?.id, 'lb-1');
    expect(appliedStock, 12.375);
  });

  testWidgets(
    'ajuste rechazado (409) muestra notificacion amigable y no filtra DioException',
    (tester) async {
      final product = _product(
        id: 'p-reject',
        name: 'Producto externo',
        category: 'General',
        stock: 4,
      );
      await _pumpStockAdjustmentsHarness(
        tester,
        product: product,
        onSetStock: (selected, stock, {warehouseId, currentWarehouseStock}) {
          throw DioException(
            requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
            type: DioExceptionType.badResponse,
            response: Response<Object>(
              requestOptions:
                  RequestOptions(path: '/products/x/adjust-stock'),
              statusCode: 409,
              data: {
                'statusCode': 409,
                'message':
                    'La fuente de productos actual no permite ajustes de stock.',
                'error': 'Conflict',
              },
            ),
          );
        },
      );

      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar ajuste'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo ajustar el stock'), findsOneWidget);
      expect(find.textContaining('no permite modificar el stock'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('409'), findsNothing);
      expect(find.textContaining('RequestOptions'), findsNothing);
      expect(
        find.byKey(const ValueKey('persistent_feedback_card')),
        findsOneWidget,
      );
      expect(find.byTooltip('Cerrar notificación'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // La X cierra la notificación.
      await tester.tap(find.byTooltip('Cerrar notificación'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('persistent_feedback_card')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ajuste con error desconocido usa respaldo amigable', (
    tester,
  ) async {
    final product = _product(
      id: 'p-unknown',
      name: 'Producto falla',
      category: 'General',
      stock: 4,
    );
    await _pumpStockAdjustmentsHarness(
      tester,
      product: product,
      onSetStock: (selected, stock, {warehouseId, currentWarehouseStock}) {
        throw DioException(
          requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
          type: DioExceptionType.badResponse,
          response: Response<Object>(
            requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
            statusCode: 500,
            data: {'message': 'Internal server error details'},
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar ajuste'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo ajustar el stock'), findsOneWidget);
    expect(
      find.text(
        'Ocurrió un problema al actualizar el inventario. Inténtalo nuevamente.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('500'), findsNothing);
    expect(find.textContaining('Internal server'), findsNothing);
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsOneWidget,
    );
  });

  testWidgets('editar producto con stock no permite cambiar la unidad', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository()
      ..products = [
        _product(
          id: 'p-stock',
          name: 'Carne',
          category: 'Carnes',
          stock: 5,
          unitOfMeasure: UnitOfMeasureModel.unit,
        ),
      ];
    await _pumpEditor(
      tester,
      repo: repo,
      product: repo.products.single,
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yarda (yd)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.updates, 0);
    expect(repo.products.single.unitOfMeasure, UnitOfMeasureModel.unit);
    expect(
      find.text('No se puede cambiar la unidad de medida'),
      findsOneWidget,
    );
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('400'), findsNothing);
  });

  testWidgets(
    'editar producto sin stock pero con historial muestra mensaje amigable',
    (tester) async {
      final repo = _UomProtectedCatalogRepository()
        ..products = [
          _product(
            id: 'p-history',
            name: 'Tela',
            category: 'Textil',
            stock: 0,
            unitOfMeasure: UnitOfMeasureModel.unit,
          ),
        ];
      await _pumpEditor(
        tester,
        repo: repo,
        product: repo.products.single,
        companySettings: CompanySettings.empty().copyWith(
          measurementUnitsEnabled: true,
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yarda (yd)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(repo.updates, 1);
      expect(
        find.text('No se puede cambiar la unidad de medida'),
        findsOneWidget,
      );
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('400'), findsNothing);
    },
  );

  testWidgets('formulario permite seleccionar unidad de medida decimal', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(
      tester,
      repo: repo,
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    expect(find.text('Unidad de medida'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Tela azul');
    await tester.enterText(find.byType(TextField).at(2), '150');
    await tester.enterText(find.byType(TextField).at(3), '90');
    await tester.enterText(find.byType(TextField).at(4), '20.5');
    await tester.tap(find.text('Unidad (u)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yarda (yd)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.tap(find.text('Crear producto'));
    await tester.pumpAndSettle();

    expect(repo.creates, 1);
    expect(repo.lastUnitOfMeasureId, 'YARD');
    expect(repo.lastUnitOfMeasure?.symbol, 'yd');
  });

  testWidgets(
    'formulario crea categoria con el dialogo existente y conserva datos',
    (tester) async {
      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(find.byType(TextField).at(0), 'Teclado Slim');
      await tester.enterText(find.byType(TextField).at(1), 'SKU-77');
      await tester.enterText(find.byType(TextField).at(2), '1250');
      await tester.enterText(find.byType(TextField).at(3), '700');
      await tester.enterText(find.byType(TextField).at(4), '8');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Crear'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva categoría'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Nombre de la categoría',
        ),
        'Accesorios',
      );
      await tester.tap(find.widgetWithText(DialogPrimaryButton, 'Crear'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Nueva categoría'), findsNothing);

      String textFieldValue(int index) => tester
          .widget<TextField>(find.byType(TextField).at(index))
          .controller!
          .text;
      expect(textFieldValue(0), 'Teclado Slim');
      expect(textFieldValue(1), 'SKU-77');
      expect(textFieldValue(2), '1250');
      expect(textFieldValue(3), '700');
      expect(textFieldValue(4), '8');
      final categoryField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Categoría',
        ),
      );
      expect(categoryField.controller!.text, 'Accesorios');

      await tester.tap(find.text('Crear producto'));
      await tester.pumpAndSettle();

      expect(repo.creates, 1);
      expect(repo.lastCategory, 'Accesorios');
    },
  );

  testWidgets(
    'formulario oculta unidad de medida cuando el flag esta apagado',
    (tester) async {
      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      expect(find.text('Unidad de medida'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), 'Caja simple');
      await tester.enterText(find.byType(TextField).at(2), '150');
      await tester.enterText(find.byType(TextField).at(3), '90');
      await tester.enterText(find.byType(TextField).at(4), '20');
      await tester.tap(find.text('General'));
      await tester.tap(find.text('Crear producto'));
      await tester.pumpAndSettle();

      expect(repo.creates, 1);
      expect(repo.lastUnitOfMeasureId, UnitOfMeasureModel.unit.id);
      expect(repo.lastUnitOfMeasure, UnitOfMeasureModel.unit);
    },
  );

  testWidgets('formulario rechaza stock decimal para Unidad', (tester) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(
      tester,
      repo: repo,
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Caja');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '50');
    await tester.enterText(find.byType(TextField).at(4), '1.5');
    await tester.tap(find.text('General'));
    await tester.tap(find.text('Crear producto'));
    await tester.pumpAndSettle();

    expect(repo.creates, 0);
    expect(find.textContaining('debe ser entera'), findsOneWidget);
  });

  testWidgets(
    'editar producto medido muestra stock con unidad en solo lectura',
    (tester) async {
      final repo = _FakeCatalogRepository();
      const yard = UnitOfMeasureModel(
        id: 'YARD',
        code: 'YARD',
        name: 'Yarda',
        symbol: 'yd',
        category: 'LENGTH',
        allowDecimals: true,
        precision: 3,
      );
      final product = ProductModel(
        id: 'fabric-1',
        nombre: 'Tela azul',
        precio: 150,
        costo: 90,
        stock: 14.5,
        categoria: 'General',
        unitOfMeasureId: yard.id,
        unitOfMeasure: yard,
      );

      await _pumpEditor(
        tester,
        repo: repo,
        product: product,
        companySettings: CompanySettings.empty().copyWith(
          measurementUnitsEnabled: true,
        ),
      );

      expect(find.text('Yarda (yd)'), findsWidgets);
      expect(find.text('Stock actual'), findsOneWidget);
      expect(find.text('14.5 yd'), findsOneWidget);
      expect(find.text('Ajustar stock'), findsOneWidget);
      expect(find.widgetWithText(TextField, '14.5'), findsNothing);
    },
  );

  testWidgets('editar producto no envia stock como ajuste accidental', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    final product = _product(
      id: 'fabric-1',
      name: 'Tela azul',
      category: 'General',
      stock: 14.5,
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

    await _pumpEditor(
      tester,
      repo: repo,
      product: product,
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Tela azul fina');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.updates, 1);
    expect(repo.lastAdjustedStock, isNull);
  });

  testWidgets('inventario móvil no muestra selector superior de tabs', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpMobileInventory(tester, repo: repo);

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.text('Auriculares Pro'), findsOneWidget);
  });

  testWidgets('inventario móvil abre Stock como pantalla independiente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpMobileInventory(tester, repo: repo, initialMobileTab: 'stock');

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Stock'), findsWidgets);
    expect(find.text('Aplicar ajuste'), findsOneWidget);
  });

  testWidgets('catálogo muestra stock decimal con unidad por producto', (
    tester,
  ) async {
    const yard = UnitOfMeasureModel(
      id: 'YARD',
      code: 'YARD',
      name: 'Yarda',
      symbol: 'yd',
      category: 'LENGTH',
      allowDecimals: true,
      precision: 3,
    );
    const pound = UnitOfMeasureModel(
      id: 'POUND',
      code: 'POUND',
      name: 'Libra',
      symbol: 'lb',
      category: 'WEIGHT',
      allowDecimals: true,
      precision: 3,
    );
    final repo = _FakeCatalogRepository()
      ..products = [
        _product(
          id: 'unit-1',
          name: 'Audifonos Visual UAT',
          category: 'Unidad',
          stock: 8,
          unitOfMeasure: UnitOfMeasureModel.unit,
        ),
        _product(
          id: 'lb-1',
          name: 'Carne Visual UAT',
          category: 'Peso',
          stock: 7.625,
          unitOfMeasure: pound,
        ),
        _product(
          id: 'yd-1',
          name: 'Tela Azul Visual UAT',
          category: 'Tela',
          stock: 14.5,
          unitOfMeasure: yard,
        ),
      ];

    await _pumpMobileInventory(
      tester,
      repo: repo,
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    expect(find.text('8 u'), findsOneWidget);
    expect(find.text('7.625 lb'), findsOneWidget);
    expect(find.text('14.5 yd'), findsOneWidget);
    expect(find.text('8'), findsNothing);
    expect(find.text('15'), findsNothing);
  });

  testWidgets(
    'catálogo con un almacén muestra almacén principal sin selector',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = _product(
        id: 'unit-1',
        name: 'Audifonos Visual UAT',
        category: 'Unidad',
        stock: 5,
        unitOfMeasure: UnitOfMeasureModel.unit,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _singleWarehouseOverrides(
            product: product,
            companySettings: CompanySettings.empty().copyWith(
              multiWarehouseEnabled: true,
            ),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1100,
                child: CatalogTab(
                  products: [product],
                  loading: false,
                  error: null,
                  onRefresh: () async {},
                  onCreate: () {},
                  onImport: () async {},
                  onExport: () async {},
                  onExportSelection: (_) async {},
                  onPdfSelection: (_) async {},
                  onBulkDelete: (_) async {},
                  onBulkChangeCategory: (_, _) async {},
                  onEdit: (_) {},
                  onSetStock:
                      (_, _, {warehouseId, currentWarehouseStock}) async {},
                  canEditProducts: true,
                  canAddStock: true,
                  onDelete: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Almacén: Principal'), findsOneWidget);
      expect(find.text('Todos los almacenes'), findsNothing);
      expect(find.text('Almacén por defecto'), findsNothing);
      expect(find.text('5'), findsOneWidget);
    },
  );

  testWidgets('catálogo oculta Referencia cuando no hay referencias visibles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = [
      _product(
        id: 'unit-1',
        name: 'Producto sin referencia',
        category: 'Unidad',
        stock: 5,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
      _product(
        id: 'uuid-1',
        name: 'Producto con id interno',
        category: 'Unidad',
        code: 'cmf9o7qx0000cb3lkd0vkt6a7',
        stock: 3,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
      _product(
        id: 'uuid-2',
        name: 'Producto con uuid interno',
        category: 'Unidad',
        code: '923581af-6cc7-4fc3-881d-636c50d585fe',
        stock: 4,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(product: products.first),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: products,
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock:
                    (_, _, {warehouseId, currentWarehouseStock}) async {},
                canEditProducts: true,
                canAddStock: true,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Referencia'), findsNothing);
    expect(find.text('Sin ref.'), findsNothing);
    expect(find.text('Producto sin referencia'), findsOneWidget);
    expect(find.text('Producto con id interno'), findsOneWidget);
    expect(find.text('Producto con uuid interno'), findsOneWidget);
  });

  testWidgets('catálogo muestra Referencia cuando al menos una es real', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = [
      _product(
        id: 'unit-1',
        name: 'Producto sin referencia',
        category: 'Unidad',
        stock: 5,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
      _product(
        id: 'ref-1',
        name: 'Producto con referencia',
        category: 'Unidad',
        code: 'REF-001',
        stock: 3,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(product: products.first),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: products,
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock:
                    (_, _, {warehouseId, currentWarehouseStock}) async {},
                canEditProducts: true,
                canAddStock: true,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Referencia'), findsOneWidget);
    expect(find.text('REF-001'), findsOneWidget);
    expect(find.text('Sin ref.'), findsNothing);
  });

  testWidgets('catálogo permite selección múltiple y muestra acciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = [
      _product(
        id: 'unit-1',
        name: 'Producto seleccionable A',
        category: 'Unidad',
        stock: 5,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
      _product(
        id: 'unit-2',
        name: 'Producto seleccionable B',
        category: 'Unidad',
        stock: 6,
        unitOfMeasure: UnitOfMeasureModel.unit,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(
          product: products.first,
          companySettings: CompanySettings.empty().copyWith(
            multiWarehouseEnabled: true,
          ),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: products,
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock:
                    (_, _, {warehouseId, currentWarehouseStock}) async {},
                canEditProducts: true,
                canAddStock: true,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acciones (2)'), findsNothing);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Acciones (2)'), findsNothing);

    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Acciones (2)'), findsOneWidget);

    await tester.tap(find.text('Acciones (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Exportar selección'), findsOneWidget);
    expect(find.text('PDF selección'), findsOneWidget);
    expect(find.text('Cambiar categoría'), findsOneWidget);
    expect(find.text('Eliminar productos'), findsOneWidget);
    expect(find.text('Transferir a otro almacén'), findsOneWidget);
  });

  testWidgets('catálogo filtra stock por almacén sin escrituras', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var stockWrites = 0;
    const yard = UnitOfMeasureModel(
      id: 'YARD',
      code: 'YARD',
      name: 'Yarda',
      symbol: 'yd',
      category: 'LENGTH',
      allowDecimals: true,
      precision: 3,
    );
    final product = _product(
      id: 'yd-1',
      name: 'Tela Azul Visual UAT',
      category: 'Tela',
      stock: 14.5,
      unitOfMeasure: yard,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _multiWarehouseOverrides(
          stockByProductAndWarehouse: {
            'yd-1': {'w-default': 12.25, 'w-secondary': 2.25},
          },
          companySettings: CompanySettings.empty().copyWith(
            multiWarehouseEnabled: true,
            measurementUnitsEnabled: true,
          ),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: [product],
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock: (_, _, {warehouseId, currentWarehouseStock}) async {
                  stockWrites += 1;
                },
                canEditProducts: true,
                canAddStock: true,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todos los almacenes'), findsOneWidget);
    expect(find.text('14.5 yd'), findsOneWidget);
    expect(find.text('Almacén por defecto'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Principal').last);
    await tester.pumpAndSettle();
    expect(find.text('12.25 yd'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sucursal Norte').last);
    await tester.pumpAndSettle();
    expect(find.text('2.25 yd'), findsOneWidget);
    expect(find.text('Tela Azul Visual UAT'), findsOneWidget);
    expect(stockWrites, 0);
  });

  testWidgets('icono de fila abre ajuste de stock del producto correcto', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = _product(
      id: 'unit-1',
      name: 'Audifonos Visual UAT',
      category: 'Unidad',
      stock: 5,
      unitOfMeasure: UnitOfMeasureModel.unit,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(product: product),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: [product],
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock:
                    (_, _, {warehouseId, currentWarehouseStock}) async {},
                canEditProducts: true,
                canAddStock: true,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ajustar stock'));
    await tester.pumpAndSettle();

    expect(find.text('Audifonos Visual UAT'), findsWidgets);
    expect(find.text('Agregar stock'), findsOneWidget);
    expect(find.text('Disminuir stock'), findsOneWidget);
    expect(find.text('Cantidad'), findsOneWidget);
    expect(find.textContaining('Stock actual: 5'), findsOneWidget);
    expect(find.textContaining('Nuevo stock: 6'), findsOneWidget);
  });

  testWidgets('ajuste de stock muestra unidad y bloquea decimal para Unidad', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository()
      ..products = [
        _product(
          id: 'unit-1',
          name: 'Audifonos Visual UAT',
          category: 'Unidad',
          stock: 8,
          unitOfMeasure: UnitOfMeasureModel.unit,
        ),
      ];

    await _pumpMobileInventory(
      tester,
      repo: repo,
      initialMobileTab: 'stock',
      companySettings: CompanySettings.empty().copyWith(
        measurementUnitsEnabled: true,
      ),
    );

    expect(find.textContaining('8 u'), findsWidgets);
    expect(find.text('u'), findsWidgets);
    await tester.enterText(find.byType(TextField).at(1), '1.5');

    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aplicar ajuste'),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets('inventario móvil abre Categorías como pantalla independiente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpMobileInventory(
      tester,
      repo: repo,
      initialMobileTab: 'categories',
    );

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Categorías'), findsWidgets);
  });

  testWidgets('catálogo resetea filtro cuando desaparece la categoría', (
    tester,
  ) async {
    var products = [
      _product(id: 'p-1', name: 'Producto humo', category: 'Smoke'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setHostState) {
              return Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => setHostState(() => products = []),
                      child: const Text('Vaciar categoría'),
                    ),
                    Expanded(
                      child: CatalogTab(
                        products: products,
                        loading: false,
                        error: null,
                        onRefresh: () async {},
                        onCreate: () {},
                        onImport: () async {},
                        onExport: () async {},
                        onExportSelection: (_) async {},
                        onPdfSelection: (_) async {},
                        onBulkDelete: (_) async {},
                        onBulkChangeCategory: (_, _) async {},
                        onEdit: (_) {},
                        onSetStock:
                            (
                              _,
                              _, {
                              warehouseId,
                              currentWarehouseStock,
                            }) async {},
                        canEditProducts: true,
                        canAddStock: true,
                        onDelete: (_) async {},
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filtro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Smoke').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vaciar categoría'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Producto humo'), findsNothing);
  });

  testWidgets('catálogo muestra badges fiscales comprensibles', (tester) async {
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxId: 'tax-18',
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );
    final products = [
      ProductModel(
        id: 'p-included',
        nombre: 'Incluido',
        precio: 1180,
        costo: 700,
        stock: 1,
        categoria: 'Fiscal',
        taxTreatment: 'TAXABLE',
        taxRate: 0.18,
        taxPriceMode: 'TAX_INCLUDED',
      ),
      ProductModel(
        id: 'p-added',
        nombre: 'Agregado',
        precio: 1000,
        costo: 600,
        stock: 1,
        categoria: 'Fiscal',
        taxTreatment: 'TAXABLE',
        taxRate: 0.18,
        taxPriceMode: 'TAX_ADDED',
      ),
      ProductModel(
        id: 'p-exempt',
        nombre: 'Exento',
        precio: 500,
        costo: 300,
        stock: 1,
        categoria: 'Fiscal',
        taxTreatment: 'EXEMPT',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _singleWarehouseOverrides(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: CatalogTab(
                products: products,
                loading: false,
                error: null,
                onRefresh: () async {},
                onCreate: () {},
                onImport: () async {},
                onExport: () async {},
                onExportSelection: (_) async {},
                onPdfSelection: (_) async {},
                onBulkDelete: (_) async {},
                onBulkChangeCategory: (_, _) async {},
                onEdit: (_) {},
                onSetStock:
                    (_, _, {warehouseId, currentWarehouseStock}) async {},
                canEditProducts: true,
                canAddStock: true,
                showTaxBadges: true,
                taxConfig: taxConfig,
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Incl. 18%'), findsOneWidget);
    expect(find.text('+ 18%'), findsOneWidget);
    expect(find.text('Exento'), findsWidgets);
  });

  testWidgets(
    'catálogo oculta badges fiscales cuando impuestos de empresa están apagados',
    (tester) async {
      final taxConfig = ProductTaxUiConfig(
        settings: CompanySettings.empty().copyWith(
          taxEnabled: false,
          defaultTaxRate: 0.18,
          pricesIncludeTax: true,
        ),
        activeTaxes: const [],
      );
      final products = [
        ProductModel(
          id: 'p-tax-off',
          nombre: 'Producto fiscal guardado',
          precio: 1180,
          costo: 700,
          stock: 1,
          categoria: 'Fiscal',
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_INCLUDED',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: _singleWarehouseOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1100,
                child: CatalogTab(
                  products: products,
                  loading: false,
                  error: null,
                  onRefresh: () async {},
                  onCreate: () {},
                  onImport: () async {},
                  onExport: () async {},
                  onExportSelection: (_) async {},
                  onPdfSelection: (_) async {},
                  onBulkDelete: (_) async {},
                  onBulkChangeCategory: (_, _) async {},
                  onEdit: (_) {},
                  onSetStock:
                      (_, _, {warehouseId, currentWarehouseStock}) async {},
                  canEditProducts: true,
                  canAddStock: true,
                  showTaxBadges: true,
                  taxConfig: taxConfig,
                  onDelete: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Incl. 18%'), findsNothing);
      expect(find.text('+ 18%'), findsNothing);
      expect(find.text('Exento'), findsNothing);
      expect(find.text(formatRdCurrencyAccounting(1180)), findsOneWidget);
    },
  );

  testWidgets(
    'catálogo refresca badges al cambiar de empresa fiscal a normal',
    (tester) async {
      var taxEnabled = true;
      final products = [
        ProductModel(
          id: 'p-switch',
          nombre: 'Producto cambio empresa',
          precio: 1180,
          costo: 700,
          stock: 1,
          categoria: 'Fiscal',
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_INCLUDED',
        ),
      ];

      ProductTaxUiConfig config() => ProductTaxUiConfig(
        settings: CompanySettings.empty().copyWith(
          taxEnabled: taxEnabled,
          defaultTaxRate: 0.18,
          pricesIncludeTax: true,
        ),
        activeTaxes: taxEnabled
            ? const [
                ProductTaxOption(
                  id: 'tax-18',
                  name: 'ITBIS',
                  rate: 0.18,
                  isDefault: true,
                ),
              ]
            : const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _singleWarehouseOverrides(),
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setHostState) {
                return Scaffold(
                  body: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => setHostState(() => taxEnabled = false),
                        child: const Text('Empresa normal'),
                      ),
                      ElevatedButton(
                        onPressed: () => setHostState(() => taxEnabled = true),
                        child: const Text('Empresa fiscal'),
                      ),
                      Expanded(
                        child: SizedBox(
                          width: 1100,
                          child: CatalogTab(
                            products: products,
                            loading: false,
                            error: null,
                            onRefresh: () async {},
                            onCreate: () {},
                            onImport: () async {},
                            onExport: () async {},
                            onExportSelection: (_) async {},
                            onPdfSelection: (_) async {},
                            onBulkDelete: (_) async {},
                            onBulkChangeCategory: (_, _) async {},
                            onEdit: (_) {},
                            onSetStock:
                                (
                                  _,
                                  _, {
                                  warehouseId,
                                  currentWarehouseStock,
                                }) async {},
                            canEditProducts: true,
                            canAddStock: true,
                            showTaxBadges: taxEnabled,
                            taxConfig: config(),
                            onDelete: (_) async {},
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Incl. 18%'), findsOneWidget);

      await tester.tap(find.text('Empresa normal'));
      await tester.pumpAndSettle();
      expect(find.text('Incl. 18%'), findsNothing);
      expect(find.text('Exento'), findsNothing);

      await tester.tap(find.text('Empresa fiscal'));
      await tester.pumpAndSettle();
      expect(find.text('Incl. 18%'), findsOneWidget);
    },
  );

  testWidgets(
    'ajustes de stock resetea filtro cuando desaparece la categoría',
    (tester) async {
      var products = [
        _product(id: 'p-1', name: 'Producto humo', category: 'Smoke'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: _singleWarehouseOverrides(),
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setHostState) {
                return Scaffold(
                  body: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => setHostState(() => products = []),
                        child: const Text('Vaciar categoría'),
                      ),
                      Expanded(
                        child: StockAdjustmentsPage(
                          products: products,
                          onRefresh: () async {},
                          onSetStock:
                              (
                                _,
                                _, {
                                warehouseId,
                                currentWarehouseStock,
                              }) async {},
                          canAddStock: true,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smoke').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vaciar categoría'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Todas las categorías'), findsWidgets);
    },
  );

  testWidgets(
    'crear producto cierra el formulario sin errores de EditableText',
    (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(find.byType(TextField).at(0), 'Producto prueba');
      await tester.enterText(find.byType(TextField).at(1), 'ABC-001');
      await tester.enterText(find.byType(TextField).at(2), '100');
      await tester.enterText(find.byType(TextField).at(3), '60');
      await tester.enterText(find.byType(TextField).at(4), '5');
      await tester.enterText(find.byType(TextField).at(5), 'General');
      await tester.tap(find.text('Crear producto'));
      await tester.pumpAndSettle();

      expect(repo.creates, 1);
      expect(find.text('Nuevo producto'), findsNothing);
      expect(
        errors.map((e) => e.exceptionAsString()).join('\n'),
        isNot(contains('EditableText')),
      );
      expect(
        errors.map((e) => e.exceptionAsString()).join('\n'),
        isNot(contains('wrong build scope')),
      );
    },
  );

  testWidgets('formulario guarda producto gravado con tasa activa', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxId: 'tax-18',
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );
    await _pumpEditor(tester, repo: repo, taxConfig: taxConfig);

    await tester.enterText(find.byType(TextField).at(0), 'Producto fiscal');
    await tester.enterText(find.byType(TextField).at(1), 'FISC-001');
    await tester.enterText(find.byType(TextField).at(2), '1180');
    await tester.enterText(find.byType(TextField).at(3), '700');
    await tester.enterText(find.byType(TextField).at(4), '3');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    await tester.ensureVisible(find.text('Predeterminado').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Predeterminado').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gravado').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('ITBIS'), findsWidgets);
    await tester.tap(find.text('Crear producto'));
    await tester.pumpAndSettle();

    expect(repo.creates, 1);
    expect(repo.lastTaxTreatment, 'TAXABLE');
    expect(repo.lastTaxRate, 0.18);
    expect(repo.lastTaxPriceMode, isNull);
  });

  testWidgets('editar producto INHERIT a EXEMPT envia EXEMPT al guardar', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    ProductFormResult? result;
    final product = ProductModel(
      id: 'p-tax-edit',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'INHERIT',
    );
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxRate: 0.18,
        pricesIncludeTax: false,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          productTaxUiConfigProvider.overrideWith((ref) async => taxConfig),
          ..._singleWarehouseOverrides(product: product),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ProductFormResult>(
                    MaterialPageRoute<ProductFormResult>(
                      builder: (_) => InventoryProductEditorPage(
                        product: product,
                        categories: const ['General'],
                      ),
                    ),
                  );
                },
                child: const Text('Abrir editor fiscal'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir editor fiscal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Predeterminado').last);
    await tester.tap(find.text('Predeterminado').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Exento').last);
    await tester.tap(find.text('Exento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.lastTaxTreatment, 'EXEMPT');
    expect(repo.lastTaxRate, isNull);
    expect(repo.lastTaxPriceMode, isNull);
    expect(result?.product?.taxTreatment, 'EXEMPT');
  });

  testWidgets('editar producto EXEMPT a INHERIT envia INHERIT al guardar', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    ProductFormResult? result;
    final product = ProductModel(
      id: 'p-tax-edit',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'EXEMPT',
    );
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxRate: 0.18,
        pricesIncludeTax: false,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          productTaxUiConfigProvider.overrideWith((ref) async => taxConfig),
          ..._singleWarehouseOverrides(product: product),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ProductFormResult>(
                    MaterialPageRoute<ProductFormResult>(
                      builder: (_) => InventoryProductEditorPage(
                        product: product,
                        categories: const ['General'],
                      ),
                    ),
                  );
                },
                child: const Text('Abrir editor fiscal'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir editor fiscal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Exento').last);
    await tester.tap(find.text('Exento').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Predeterminado').last);
    await tester.tap(find.text('Predeterminado').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.lastTaxTreatment, 'INHERIT');
    expect(repo.lastTaxRate, isNull);
    expect(repo.lastTaxPriceMode, isNull);
    expect(result?.product?.taxTreatment, 'INHERIT');
  });

  testWidgets(
    'formulario oculta sección fiscal cuando impuestos están apagados',
    (tester) async {
      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      expect(find.text('Fiscal'), findsNothing);
      expect(find.text('Tratamiento'), findsNothing);
    },
  );

  testWidgets('predeterminado muestra ayuda de herencia de empresa', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxId: 'tax-18',
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );
    await _pumpEditor(tester, repo: repo, taxConfig: taxConfig);

    expect(
      find.text('Usa ITBIS 18% incluido según la empresa.'),
      findsOneWidget,
    );
  });

  testWidgets('editar conserva imagen si no se selecciona una nueva', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    final product = ProductModel(
      id: 'p-1',
      nombre: 'Taladro',
      precio: 500,
      costo: 300,
      stock: 2,
      categoria: 'Herramientas',
      fotoUrl: '/uploads/existing.png',
    );
    await _pumpEditor(tester, repo: repo, product: product);

    await tester.enterText(find.byType(TextField).at(0), 'Taladro Pro');
    await tester.enterText(find.byType(TextField).at(2), '650');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.updates, 1);
    expect(repo.creates, 0);
    expect(find.text('Editar producto'), findsNothing);
  });

  testWidgets(
    'editar conserva fuente original de imagen aunque la vista use URL versionada',
    (tester) async {
      final repo = _FakeCatalogRepository();
      final product = ProductModel(
        id: 'p-versioned-image',
        nombre: 'Camara',
        precio: 1200,
        costo: 700,
        stock: 4,
        categoria: 'Seguridad',
        fotoUrl:
            '/media/object?key=uploads%2Fcompanies%2Fc1%2Fproducts%2Fcamara.png&v=123',
        originalFotoUrl: 'uploads/companies/c1/products/camara.png',
      );
      await _pumpEditor(tester, repo: repo, product: product);

      await tester.enterText(find.byType(TextField).at(0), 'Camara Pro');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(repo.updates, 1);
      expect(repo.lastFotoUrl, 'uploads/companies/c1/products/camara.png');
    },
  );

  testWidgets('editar EXEMPT reenvia la imagen actual al guardar', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    ProductFormResult? result;
    final product = ProductModel(
      id: 'p-image-tax',
      nombre: 'Escaner',
      precio: 2500,
      costo: 1300,
      stock: 1,
      categoria: 'General',
      fotoUrl: '/uploads/existing.png',
    );
    final taxConfig = ProductTaxUiConfig(
      settings: CompanySettings.empty().copyWith(
        taxEnabled: true,
        defaultTaxRate: 0.18,
        pricesIncludeTax: false,
      ),
      activeTaxes: const [
        ProductTaxOption(
          id: 'tax-18',
          name: 'ITBIS',
          rate: 0.18,
          isDefault: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          productTaxUiConfigProvider.overrideWith((ref) async => taxConfig),
          companySettingsProvider.overrideWith(
            (ref) async => CompanySettings.empty(),
          ),
          ..._singleWarehouseOverrides(product: product),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ProductFormResult>(
                    MaterialPageRoute<ProductFormResult>(
                      builder: (_) => InventoryProductEditorPage(
                        product: product,
                        categories: const ['General'],
                      ),
                    ),
                  );
                },
                child: const Text('Abrir editor con imagen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir editor con imagen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Predeterminado').last);
    await tester.tap(find.text('Predeterminado').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Exento').last);
    await tester.tap(find.text('Exento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.lastTaxTreatment, 'EXEMPT');
    expect(repo.lastFotoUrl, '/uploads/existing.png');
    expect(result?.product?.taxTreatment, 'EXEMPT');
    expect(result?.product?.displayFotoUrl, isNotNull);
  });

  testWidgets(
    'crear EXEMPT espera imagen y guarda foto sin perder fiscalidad',
    (tester) async {
      FilePicker? previousPicker;
      try {
        previousPicker = FilePicker.platform;
      } catch (_) {
        previousPicker = null;
      }
      FilePicker.platform = _FakeFilePicker(
        FilePickerResult([
          PlatformFile(
            name: 'scanner.png',
            size: 68,
            bytes: Uint8List.fromList([
              0x89,
              0x50,
              0x4E,
              0x47,
              0x0D,
              0x0A,
              0x1A,
              0x0A,
              0x00,
              0x00,
              0x00,
              0x0D,
              0x49,
              0x48,
              0x44,
              0x52,
              0x00,
              0x00,
              0x00,
              0x01,
              0x00,
              0x00,
              0x00,
              0x01,
              0x08,
              0x06,
              0x00,
              0x00,
              0x00,
              0x1F,
              0x15,
              0xC4,
              0x89,
              0x00,
              0x00,
              0x00,
              0x0B,
              0x49,
              0x44,
              0x41,
              0x54,
              0x78,
              0x9C,
              0x63,
              0x00,
              0x01,
              0x00,
              0x00,
              0x05,
              0x00,
              0x01,
              0x0D,
              0x0A,
              0x2D,
              0xB4,
              0x00,
              0x00,
              0x00,
              0x00,
              0x49,
              0x45,
              0x4E,
              0x44,
              0xAE,
              0x42,
              0x60,
              0x82,
            ]),
          ),
        ]),
      );
      if (previousPicker != null) {
        addTearDown(() => FilePicker.platform = previousPicker!);
      }

      final repo = _FakeCatalogRepository()
        ..uploadCompleter = Completer<String>();
      ProductFormResult? result;
      final taxConfig = ProductTaxUiConfig(
        settings: CompanySettings.empty().copyWith(
          taxEnabled: true,
          defaultTaxRate: 0.18,
          pricesIncludeTax: false,
        ),
        activeTaxes: const [
          ProductTaxOption(
            id: 'tax-18',
            name: 'ITBIS',
            rate: 0.18,
            isDefault: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(repo),
            productTaxUiConfigProvider.overrideWith((ref) async => taxConfig),
            companySettingsProvider.overrideWith(
              (ref) async => CompanySettings.empty(),
            ),
            ..._singleWarehouseOverrides(),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ProductFormResult>(
                          MaterialPageRoute<ProductFormResult>(
                            builder: (_) => const InventoryProductEditorPage(
                              product: null,
                              categories: ['General'],
                            ),
                          ),
                        );
                  },
                  child: const Text('Abrir crear'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir crear'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Scanner nuevo');
      await tester.enterText(find.byType(TextField).at(2), '2500');
      await tester.enterText(find.byType(TextField).at(3), '1300');
      await tester.enterText(find.byType(TextField).at(4), '5');
      await tester.enterText(find.byType(TextField).at(5), 'General');
      await tester.ensureVisible(find.text('Predeterminado').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Predeterminado').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exento').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Subir imagen desde el ordenador'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subir imagen desde el ordenador'));
      await tester.pump();
      expect(repo.uploads, 1);

      await tester.ensureVisible(find.text('Crear producto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear producto'));
      await tester.pump();
      expect(repo.creates, 0);
      expect(repo.updates, 0);

      repo.uploadCompleter!.complete('/uploads/scanner.png');
      await tester.pumpAndSettle();

      expect(repo.creates, 1);
      expect(repo.updates, 0);
      expect(repo.lastFotoUrl, '/uploads/scanner.png');
      expect(repo.lastTaxTreatment, 'EXEMPT');
      expect(repo.lastTaxRate, isNull);
      expect(repo.lastTaxPriceMode, isNull);
      expect(result?.product?.taxTreatment, 'EXEMPT');
    },
  );

  testWidgets(
    'selector de imagen de escritorio con timeout libera el formulario',
    (tester) async {
      FilePicker? previousPicker;
      try {
        previousPicker = FilePicker.platform;
      } catch (_) {
        previousPicker = null;
      }
      FilePicker.platform = _HangingFilePicker();
      if (previousPicker != null) {
        addTearDown(() => FilePicker.platform = previousPicker!);
      }

      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.ensureVisible(find.text('Subir imagen desde el ordenador'));
      await tester.tap(find.text('Subir imagen desde el ordenador'));
      await tester.pump();

      expect(find.text('Seleccionando imagen...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(find.text('Seleccionando imagen...'), findsNothing);
      expect(find.text('Subir imagen desde el ordenador'), findsOneWidget);
      expect(
        find.textContaining('El selector de imagen no respondió'),
        findsOneWidget,
      );
      expect(find.text('Crear producto'), findsOneWidget);
      expect(repo.creates, 0);
      expect(repo.updates, 0);
    },
  );

  testWidgets('escribir letras en código no guarda automáticamente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(1), 'ABC');
    await tester.pump();

    expect(repo.creates, 0);
    expect(repo.updates, 0);
  });

  testWidgets('escribir números en código no guarda automáticamente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(1), '1234567890');
    await tester.pump();

    expect(repo.creates, 0);
    expect(repo.updates, 0);
  });

  testWidgets('Enter en el campo código avanza sin crear producto', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(0), 'Producto scanner');
    await tester.enterText(find.byType(TextField).at(1), 'SCN-001');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '5');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 80));

    expect(repo.creates, 0);
    expect(repo.updates, 0);
    final priceField = tester.widget<TextField>(find.byType(TextField).at(2));
    expect(priceField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Enter en el último campo guarda el producto', (tester) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(0), 'Producto enter');
    await tester.enterText(find.byType(TextField).at(1), 'ENT-001');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '5');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    await tester.tap(find.byType(TextField).at(5));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(repo.creates, 1);
    expect(repo.updates, 0);
  });

  testWidgets('doble click en guardar crea una sola vez', (tester) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(0), 'Producto doble');
    await tester.enterText(find.byType(TextField).at(1), 'DBL-001');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '5');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    final save = find.text('Crear producto');
    await tester.tap(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.creates, 1);
    expect(repo.updates, 0);
  });

  testWidgets('abrir y cerrar repetidamente no deja EditableText activo', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    final repo = _FakeCatalogRepository();
    for (var i = 0; i < 10; i++) {
      await _pumpEditor(tester, repo: repo);
      await tester.enterText(find.byType(TextField).first, 'Producto $i');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    }

    final messages = errors.map((e) => e.exceptionAsString()).join('\n');
    expect(messages, isNot(contains('EditableText')));
    expect(messages, isNot(contains('Duplicate GlobalKeys')));
    expect(messages, isNot(contains('deactivated widget')));
  });
}
