import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/core/utils/money_formatters.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository() : super(Dio());

  int creates = 0;
  int updates = 0;
  int uploads = 0;
  String? lastTaxTreatment;
  double? lastTaxRate;
  String? lastTaxPriceMode;
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
    bool skipLoader = false,
  }) async {
    creates += 1;
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
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
    bool skipLoader = false,
  }) async {
    updates += 1;
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProductModel(
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
  }

  @override
  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) async {
    uploads += 1;
    final completer = uploadCompleter;
    if (completer != null) return completer.future;
    return '/uploads/$filename';
  }
}

ProductModel _product({
  required String id,
  required String name,
  required String category,
}) {
  return ProductModel(
    id: id,
    nombre: name,
    precio: 100,
    costo: 60,
    stock: 1,
    categoria: category,
  );
}

Future<ProductFormResult?> _pumpEditor(
  WidgetTester tester, {
  required _FakeCatalogRepository repo,
  ProductModel? product,
  ProductTaxUiConfig? taxConfig,
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
            settings: CompanySettings.empty(),
            activeTaxes: const [],
          ),
        ),
      ],
      child: MaterialApp(
        home: InventoryModulePages(initialMobileTab: initialMobileTab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('inventario móvil no muestra selector superior de tabs', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpMobileInventory(tester, repo: repo);

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Catálogo'), findsOneWidget);
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
      MaterialApp(
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
                      onSetStock: (_, _) async {},
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
      MaterialApp(
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
              onSetStock: (_, _) async {},
              canEditProducts: true,
              canAddStock: true,
              showTaxBadges: true,
              taxConfig: taxConfig,
              onDelete: (_) async {},
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
        MaterialApp(
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
                onSetStock: (_, _) async {},
                canEditProducts: true,
                canAddStock: true,
                showTaxBadges: true,
                taxConfig: taxConfig,
                onDelete: (_) async {},
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
        MaterialApp(
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
                          onSetStock: (_, _) async {},
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
        MaterialApp(
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
                        onSetStock: (_, _) async {},
                        canAddStock: true,
                      ),
                    ),
                  ],
                ),
              );
            },
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
