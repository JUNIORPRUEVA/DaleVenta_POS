import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'product summary preserves actions and full cost at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: CompactProductCard(
                product: ProductModel(
                  id: 'p',
                  nombre: 'Adaptador profesional de nombre largo',
                  precio: 2500,
                  costo: 1300,
                  stock: 10,
                  categoria: 'Accesorios',
                ),
                onSelected: (_) {},
                onTap: () => opened++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final native = defaultTargetPlatform != TargetPlatform.windows;
        expect(
          find.textContaining('Costo:'),
          native ? findsOneWidget : findsNothing,
        );
        expect(find.text('Accesorios'), native ? findsNothing : findsOneWidget);
        await tester.tap(find.text('Adaptador profesional de nombre largo'));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }),
    );
  }
}
