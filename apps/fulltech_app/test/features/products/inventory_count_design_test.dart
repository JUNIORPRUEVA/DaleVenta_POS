import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/provided_action_icon.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/platform_goldens.dart';

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
    const Size(1024, 600),
    const Size(1920, 1080),
  ]) {
    testWidgets('recuento compacto y filtro $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Recuento de inventario'),
              actions: [
                IconButton(
                  tooltip: 'Filtrar recuento',
                  onPressed: () =>
                      (key.currentState as dynamic).openMobileFilters(),
                  icon: const ProvidedActionIcon(ProvidedAction.filter),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const ProvidedActionIcon(ProvidedAction.reload),
                ),
              ],
            ),
            body: InventoryTab(
              key: key,
              canViewCosts: true,
              onRefresh: () async {},
              products: [
                ProductModel(
                  id: '1',
                  nombre: 'Equipo',
                  categoria: 'Equipos',
                  precio: 2500,
                  costo: 1300,
                  stock: 10,
                ),
                ProductModel(
                  id: '2',
                  nombre: 'Cable',
                  categoria: 'Accesorios',
                  precio: 500,
                  costo: 200,
                  stock: 0,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(InventoryTab));
        for (final name in ['filter', 'reload', 'close']) {
          await precacheImage(
            AssetImage('assets/image/action_$name.png'),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(KpiCard), findsNWidgets(7));
      if (size.width == 1024) {
        final cards = find.byType(KpiCard);
        expect(
          tester.getTopLeft(cards.at(4)).dy,
          tester.getTopLeft(cards.first).dy,
        );
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/inventory_count_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.byTooltip('Filtrar recuento'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/inventory_filter_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.text('Sin stock'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Filtros de inventario'), findsNothing);
      expect(find.text('Equipos'), findsNothing);
      expect(find.text('Accesorios'), findsOneWidget);
    });
  }
}
