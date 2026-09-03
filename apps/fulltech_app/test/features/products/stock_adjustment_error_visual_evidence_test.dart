// GLOBAL ERROR UX HARDENING — Stock adjustment rejection visual evidence.
//
// Renders the REAL StockAdjustmentsPage and drives the exact rejection the
// backend returns (DioException 409 from a product source that does not allow
// manual stock adjustments). The page shows the error through the shared
// top-right persistent notification with customer-friendly copy (never raw
// DioException / status / transport text).
//
// No network / database: the stock save callback throws locally; providers
// are overridden. Captures PNGs under docs/stock-adjustment-error-visual-evidence.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _outDir = '../../docs/stock-adjustment-error-visual-evidence';

Future<void> _loadFonts() async {
  Future<void> loadFile(String path, String family) async {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.view(bytes.buffer);
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load();
  }

  await loadFile('assets/fonts/manrope/Manrope-Regular.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-Medium.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-SemiBold.ttf', 'Manrope');
  await loadFile('assets/fonts/manrope/Manrope-Bold.ttf', 'Manrope');
}

ProductModel _product({required String id, required String name}) {
  return ProductModel(
    id: id,
    nombre: name,
    precio: 100,
    costo: 60,
    stock: 5,
    codigo: null,
    categoria: 'General',
  );
}

List<Override> _singleWarehouseOverrides(ProductModel product) => [
  companySettingsProvider.overrideWith(
    (ref) async => CompanySettings.empty().copyWith(
      measurementUnitsEnabled: true,
    ),
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
      total: product.stock,
      warehouseTotal: product.stock,
      warehouses: [
        WarehouseStockLine(
          warehouseId: 'w-default',
          warehouseName: 'Principal',
          warehouseCode: 'MAIN',
          isDefault: true,
          isActive: true,
          quantity: product.stock ?? 0,
          quantityDecimal: (product.stock ?? 0).toString(),
        ),
      ],
    ),
  ),
];

DioException _sourceBlocked409() {
  final requestOptions = RequestOptions(path: '/products/x/adjust-stock');
  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<Object>(
      requestOptions: requestOptions,
      statusCode: 409,
      data: {
        'statusCode': 409,
        'message': 'La fuente de productos actual no permite ajustes de stock.',
        'error': 'Conflict',
      },
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.runAsync(() async {
    final binding = TestWidgetsFlutterBinding.instance;
    final renderView = binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _pumpAndReject(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final product = _product(id: 'p-reject', name: 'Producto externo');
  await tester.pumpWidget(
    ProviderScope(
      overrides: _singleWarehouseOverrides(product),
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Manrope'),
        home: Scaffold(
          body: StockAdjustmentsPage(
            products: [product],
            onRefresh: () async {},
            onSetStock: (selected, stock, {warehouseId, currentWarehouseStock}) {
              throw _sourceBlocked409();
            },
            canAddStock: true,
            showMeasurementUnits: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

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

  // La tarjeta está en la zona superior derecha.
  final rect = tester.getRect(
    find.byKey(const ValueKey('persistent_feedback_card')),
  );
  expect(rect.right, greaterThanOrEqualTo(size.width - 30));
  expect(rect.top, lessThanOrEqualTo(size.height * 0.35));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await binding.runAsync(() => _loadFonts());
  });

  testWidgets('stock rejection shows top-right friendly card (desktop)', (
    tester,
  ) async {
    await _pumpAndReject(tester, size: const Size(1366, 768));
    await _shot(tester, 'stock-adjustment-rejected-desktop-1366');
    // X cierra.
    await tester.tap(find.byTooltip('Cerrar notificación'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsNothing,
    );
  });

  testWidgets('stock rejection shows top-right friendly card (mobile)', (
    tester,
  ) async {
    await _pumpAndReject(tester, size: const Size(390, 844));
    await _shot(tester, 'stock-adjustment-rejected-mobile-390');
    await tester.tap(find.byTooltip('Cerrar notificación'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsNothing,
    );
  });
}
