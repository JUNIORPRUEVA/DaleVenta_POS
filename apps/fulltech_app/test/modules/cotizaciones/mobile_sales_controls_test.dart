import 'package:daleventa_pos/core/utils/native_phone_layout.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/mobile_sales_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone variant excludes web, desktop windows and tablet layouts', (tester) async {
    for (final size in [const Size(390, 844), const Size(800, 1100), const Size(1280, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? phone;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        phone = usesNativePhoneLayout(context);
        return const SizedBox();
      })));
      final expected = !kIsWeb && size.width == 390 &&
          (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
      expect(phone, expected, reason: '$defaultTargetPlatform, $size, web=$kIsWeb');
    }
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows}));

  testWidgets('compact product keeps long names, stock and add target within card', (tester) async {
    var additions = 0;
    for (final width in [148.0, 180.0]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: 144, child: MobileSalesProductCard(
          name: 'Adaptador y accesorio de nombre extenso para comprobar dos líneas',
          price: 'RD\$ 12,500.00', stock: 'Sin stock', image: const Icon(Icons.inventory_2_outlined),
          onTap: () => additions++, onImageTap: () {},
        )),
      ))));
      expect(tester.takeException(), isNull);
      expect(find.text('Sin stock'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('phone-product-image'))), const Size(60, 60));
      expect(tester.getSize(find.byIcon(Icons.add)).width, greaterThanOrEqualTo(20));
      await tester.tap(find.byIcon(Icons.add));
    }
    expect(additions, 2);
  });

  testWidgets('customer selector truncates long name without overflowing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 148, child: MobileSalesSelector(title: 'Cliente',
        label: 'Empresa de nombre muy largo con sucursales y representantes',
        icon: Icons.person_outline, onTap: () {})),
    ))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MobileSalesSelector)).height, 56);
  });
}
