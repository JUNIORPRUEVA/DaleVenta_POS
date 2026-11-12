import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_auxiliary_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showPane(
  WidgetTester tester,
  Widget pane, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(title: const Text('FullPOS')),
        bottomNavigationBar: const SizedBox(height: 46),
        body: Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  SalesAuxiliaryDock(visible: true, width: 360, child: pane),
                ],
              ),
            ),
            const SizedBox(key: ValueKey('invoice'), width: 400),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('calculadora junto a la factura, teclas y teclado físico', (
    tester,
  ) async {
    var closed = false;
    await showPane(tester, DesktopCalculatorPane(onClose: () => closed = true));
    final calculator = find.byType(DesktopCalculatorPane);
    expect(
      tester.getRect(calculator).right,
      tester.getRect(find.byKey(const ValueKey('invoice'))).left,
    );
    for (final label in ['7', '×', '(', '2', '+', '3', ')', '=']) {
      await tester.tap(find.text(label).last);
      await tester.pump();
    }
    expect(find.text('35'), findsNWidgets(2));
    await tester.tap(find.text('C'));
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpadDivide,
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(find.text('Revisa la operación'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar calculadora'));
    await tester.pump();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 800), const Size(960, 540)]) {
    testWidgets(
      'venta rápida ocupa el alto y permite acceder a campos y acciones en $size',
      (tester) async {
        double? amount;
        await showPane(
          tester,
          DesktopManualItemPanel(
            item: null,
            money: (value) => value.toStringAsFixed(2),
            parseAmount: double.tryParse,
            formatAmount: (value) => value.toString(),
            isAdmin: true,
            measurementUnitsEnabled: false,
            unitOptions: const [UnitOfMeasureModel.unit],
            onCancel: () {},
            onSubmit:
                ({
                  required name,
                  required qty,
                  required unit,
                  required unitPrice,
                  required externalCost,
                }) => amount = qty * unitPrice,
          ),
          size: size,
        );
        final form = tester.getRect(find.byType(DesktopManualItemPanel));
        expect(form.top, 56);
        expect(form.bottom, size.height - 46);
        expect(form.right, size.width - 400);
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Servicio de ejemplo');
        await tester.enterText(fields.at(1), '2');
        await tester.enterText(fields.at(2), '10');
        await tester.ensureVisible(fields.at(3));
        await tester.enterText(fields.at(3), '20');
        await tester.ensureVisible(find.text('Agregar'));
        await tester.tap(find.text('Agregar'));
        await tester.pumpAndSettle();
        expect(amount, 40);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
