import '../../support/platform_goldens.dart';

import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_catalog_command_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showBar(
  WidgetTester tester, {
  required double width,
  required TextEditingController controller,
  required FocusNode focus,
  bool inventory = true,
  double scale = 1,
  VoidCallback? changed,
  VoidCallback? submitted,
  VoidCallback? stock,
  VoidCallback? product,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const ValueKey('command-bar'),
              child: SizedBox(
                width: width,
                child: SalesCatalogCommandBar(
                  controller: controller,
                  focusNode: focus,
                  inventoryEnabled: inventory,
                  onSearchChanged: changed ?? () {},
                  onSearchSubmitted: submitted ?? () {},
                  onStock: stock ?? () {},
                  onNewProduct: product ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage(SalesCatalogCommandBar.searchAsset),
      tester.element(find.byType(SalesCatalogCommandBar)),
    );
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

  for (final width in [1100.0, 560.0, 420.0, 340.0]) {
    testWidgets('buscador conserva espacio y acciones alineadas en $width', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await showBar(tester, width: width, controller: controller, focus: focus);
      expect(
        tester.getSize(find.byType(TextField)).width,
        greaterThanOrEqualTo(200),
      );
      final input = tester.getRect(find.byType(TextField));
      for (final label in ['Agregar o ajustar stock', 'Nuevo producto']) {
        final action = tester.getRect(find.byTooltip(label));
        expect(action.top, input.top);
        expect(action.height, 40);
        expect(action.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('command-bar')),
        matchesGoldenFile(
          platformGolden('goldens/sales_catalog_bar_${width.toInt()}.png'),
        ),
      );
    });
  }

  testWidgets('buscar, enviar, limpiar y acciones conservan sus callbacks', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var changes = 0, submits = 0, stocks = 0, products = 0;
    await showBar(
      tester,
      width: 560,
      controller: controller,
      focus: focus,
      changed: () => changes++,
      submitted: () => submits++,
      stock: () => stocks++,
      product: () => products++,
    );
    await tester.enterText(find.byType(TextField), 'ABC-123');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(submits, 1);
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(changes, 2);
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Agregar o ajustar stock'));
    await tester.tap(find.byTooltip('Nuevo producto'));
    expect(stocks, 1);
    expect(products, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('texto ampliado y stock deshabilitado no desbordan', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'Producto con nombre muy largo',
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await showBar(
      tester,
      width: 340,
      controller: controller,
      focus: focus,
      scale: 1.4,
      inventory: false,
    );
    expect(find.byTooltip('Agregar o ajustar stock'), findsNothing);
    expect(find.byTooltip('Nuevo producto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
