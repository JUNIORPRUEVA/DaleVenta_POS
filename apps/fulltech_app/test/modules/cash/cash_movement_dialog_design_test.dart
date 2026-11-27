import 'package:daleventa_pos/modules/cash/cash_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in ['IN', 'OUT']) {
    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      testWidgets('$type movement form stays usable at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        CashMovementInput? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showCashMovementDialog(context, type: type);
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        expect(fields, findsNWidgets(2));
        for (final field in fields.evaluate()) {
          expect(
            tester.getSize(find.byWidget(field.widget)).height,
            closeTo(44, .1),
          );
        }
        final submit = find.widgetWithText(
          FilledButton,
          type == 'IN' ? 'Registrar ingreso' : 'Registrar salida',
        );
        expect(tester.getSize(submit).height, 44);
        await tester.enterText(fields.first, '0');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          find.text('Ingresa un monto válido mayor que cero'),
          findsOneWidget,
        );
        expect(result, isNull);
        await tester.enterText(fields.first, '125.50');
        await tester.enterText(fields.last, 'Prueba local de formulario');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(result?.amount, 125.50);
        expect(result?.reason, 'Prueba local de formulario');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
