import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/plans/presentation/screens/license_suspended_screen.dart';

Widget _subject({
  required bool owesMoney,
  num? amount,
  DateTime? blockedAt,
  String? reasonLabel,
  VoidCallback? onPay,
  VoidCallback? onSupport,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LicenseSuspendedScreen(
        companyName: 'Comercial Demo SRL',
        owesMoney: owesMoney,
        amount: amount,
        blockedAt: blockedAt,
        reasonLabel: reasonLabel,
        onPay: onPay ?? () {},
        onSupport: onSupport ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('suspendida por falta de pago ofrece pagar y avisa del importe',
      (tester) async {
    var pagos = 0;
    var soportes = 0;
    await tester.pumpWidget(
      _subject(
        owesMoney: true,
        amount: 5000,
        blockedAt: DateTime(2026, 11, 16),
        onPay: () => pagos++,
        onSupport: () => soportes++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);
    expect(find.text('Tu cuenta está suspendida'), findsOneWidget);
    expect(find.text('Falta de pago de tu plan.'), findsOneWidget);
    expect(find.textContaining('Desde el 16/11/2026'), findsOneWidget);
    expect(find.text('IMPORTE A PAGAR'), findsOneWidget);
    expect(find.text('RD\$5,000.00'), findsOneWidget);
    expect(find.text('REALIZAR PAGO'), findsOneWidget);
    expect(find.text('HABLAR CON SOPORTE'), findsOneWidget);

    await tester.tap(find.text('REALIZAR PAGO'));
    await tester.tap(find.text('HABLAR CON SOPORTE'));
    expect(pagos, 1);
    expect(soportes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspendida por otra causa solo ofrece soporte y muestra el motivo',
      (tester) async {
    await tester.pumpWidget(
      _subject(owesMoney: false, reasonLabel: 'Empresa suspendida'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Empresa suspendida'), findsOneWidget);
    expect(find.text('HABLAR CON SOPORTE'), findsOneWidget);
    expect(find.text('REALIZAR PAGO'), findsNothing);
    expect(find.text('IMPORTE A PAGAR'), findsNothing);
  });

  testWidgets('sin motivo del servidor no se inventa una causa', (tester) async {
    await tester.pumpWidget(_subject(owesMoney: false));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('revision de tu cuenta'),
      findsOneWidget,
    );
    expect(find.text('REALIZAR PAGO'), findsNothing);
  });

  testWidgets('no desborda en un telefono de 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _subject(owesMoney: true, amount: 5000, blockedAt: DateTime(2026, 11, 16)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu cuenta está suspendida'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
