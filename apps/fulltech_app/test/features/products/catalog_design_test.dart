import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import '../../support/platform_goldens.dart';

final _products = [
  ProductModel(
    id: 'one',
    nombre:
        'Auriculares profesionales con nombre largo para verificar el catálogo',
    codigo: 'A-001',
    precio: 1250,
    costo: 750,
    stock: 10,
    categoria: 'Accesorios',
  ),
  ProductModel(
    id: 'two',
    nombre: 'Cable USB',
    codigo: 'B-002',
    precio: 500,
    costo: 250,
    stock: 2,
    categoria: 'Cables',
  ),
  ProductModel(
    id: 'three',
    nombre: 'Adaptador HDMI',
    precio: 800,
    costo: 400,
    stock: 0,
    categoria: 'Accesorios',
  ),
];

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  bool editable = true,
  ValueChanged<String>? onSearch,
  ValueChanged<ProductModel>? onEdit,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: CatalogTab(
            products: _products,
            loading: false,
            error: null,
            onRefresh: () async {},
            onRemoteSearchChanged: onSearch,
            onCreate: () {},
            onImport: () async {},
            onExport: () async {},
            onExportSelection: (_) async {},
            onPdfSelection: (_) async {},
            onBulkDelete: (_) async {},
            onBulkChangeCategory: (_, __) async {},
            onEdit: onEdit ?? (_) {},
            onSetStock: (_, __, {warehouseId, currentWarehouseStock}) async {},
            canEditProducts: editable,
            canAddStock: editable,
            onDelete: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold));
    for (final name in ['search', 'edit', 'delete']) {
      await precacheImage(AssetImage('assets/image/action_$name.png'), context);
    }
    for (final name in ['back', 'search', 'filter', 'refresh']) {
      await precacheImage(AssetImage('assets/image/mobile_navigation/$name.png'), context);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(768, 800),
    const Size(1024, 600),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    testWidgets('catálogo adaptable en $size', (tester) async {
      await _pump(tester, size, scale: size.width == 1024 ? 1.15 : 1);
      expect(find.text('Cable USB'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      if (size.width >= 640) {
        expect(
          tester.getSize(find.byType(TextField).first).width,
          lessThanOrEqualTo(760),
        );
      }
      if (size.width >= 1024) {
        expect(
          tester.widget<DataTable>(find.byType(DataTable)).dataRowMinHeight,
          48,
        );
        expect(
          tester.getSize(find.byType(DataTable)).width,
          lessThanOrEqualTo(1440),
        );
        if (size.width >= 1920) {
          expect(
            tester.getCenter(find.byType(DataTable)).dx,
            closeTo(size.width / 2, 1),
          );
        }
      }
      if (size.width >= 640) expect(find.text('Filtro'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          platformGolden('goldens/catalog_${size.width.toInt()}.png'),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('búsqueda, selección y edición conservan sus callbacks', (
    tester,
  ) async {
    String? query;
    String? edited;
    await _pump(
      tester,
      const Size(1920, 1080),
      onSearch: (value) => query = value,
      onEdit: (product) => edited = product.id,
    );
    await tester.enterText(find.byType(TextField).first, 'B-002');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(query, 'B-002');
    expect(find.text('Cable USB'), findsOneWidget);
    expect(find.text('Adaptador HDMI'), findsNothing);
    await tester.tap(find.byTooltip('Editar'));
    expect(edited, 'two');
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Acciones (3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('permisos de edición y eliminación siguen deshabilitados', (
    tester,
  ) async {
    await _pump(tester, const Size(1920, 1080), editable: false);
    for (final label in ['Editar', 'Eliminar']) {
      for (final button in tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == label,
        ),
      )) {
        expect(button.onPressed, isNull);
      }
    }
    expect(find.byTooltip('Ajustar stock'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
