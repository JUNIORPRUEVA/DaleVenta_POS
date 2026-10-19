import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await binding.runAsync(() async {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final bytes = await File(
          'assets/fonts/manrope/Manrope-$weight.ttf',
        ).readAsBytes();
        await (FontLoader(
          'Manrope',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  });
  for (final size in [const Size(1366, 768), const Size(390, 844)]) {
    testWidgets(
      'single warehouse stock entry preserves its increment at ${size.width}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final product = ProductModel(
          id: 'incremental-product',
          nombre: 'Mercancía UAT',
          precio: 100,
          costo: 40,
          stock: 5,
          categoria: 'UAT',
        );
        double? counted;
        double? baseline;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              companySettingsProvider.overrideWith(
                (ref) async => CompanySettings.empty(),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Manrope'),
              home: Scaffold(
                body: StockAdjustmentsPage(
                  products: [product],
                  onRefresh: () async {},
                  canAddStock: true,
                  onSetStock:
                      (
                        selected,
                        stock, {
                        warehouseId,
                        currentWarehouseStock,
                      }) async {
                        expect(selected.id, product.id);
                        expect(warehouseId, isNull);
                        counted = stock;
                        baseline = currentWarehouseStock;
                      },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Cantidad',
          ),
          '2',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Aplicar ajuste'));
        await tester.pumpAndSettle();
        expect(counted, 7);
        expect(baseline, 5);
        expect(counted! - baseline!, 2);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final view = TestWidgetsFlutterBinding.instance.renderViews.first;
          // ignore: invalid_use_of_protected_member
          final layer = view.layer! as OffsetLayer;
          final image = await layer.toImage(view.paintBounds);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('../../.uat/evidence')
            ..createSync(recursive: true);
          await File(
            '${dir.path}/phase11-stock-increment-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
