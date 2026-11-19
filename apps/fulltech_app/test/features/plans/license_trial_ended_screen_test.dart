import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/plans/presentation/screens/license_trial_ended_screen.dart';

Widget _subject({
  DateTime? endedAt,
  int trialDays = 7,
  VoidCallback? onSeePlans,
  VoidCallback? onSupport,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LicenseTrialEndedScreen(
        companyName: 'Comercial Demo SRL',
        endedAt: endedAt,
        trialDays: trialDays,
        onSeePlans: onSeePlans ?? () {},
        onSupport: onSupport,
      ),
    ),
  );
}

void main() {
  testWidgets('la demo terminada dice la fecha y ofrece ver los planes',
      (tester) async {
    var vistos = 0;
    await tester.pumpWidget(
      _subject(
        endedAt: DateTime(2026, 11, 15),
        onSeePlans: () => vistos++,
        onSupport: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEMO FINALIZADA'), findsOneWidget);
    expect(find.text('Tu demo de 7 días terminó'), findsOneWidget);
    expect(find.textContaining('El 15/11/2026'), findsOneWidget);
    expect(find.text('VER PLANES'), findsOneWidget);
    expect(find.text('¿Necesitas ayuda? Habla con soporte'), findsOneWidget);

    await tester.tap(find.text('VER PLANES'));
    expect(vistos, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no inventa un importe: la demo no tiene plan ni deuda',
      (tester) async {
    await tester.pumpWidget(_subject(endedAt: DateTime(2026, 11, 15)));
    await tester.pumpAndSettle();

    expect(find.textContaining('IMPORTE'), findsNothing);
    expect(find.textContaining('RD\$'), findsNothing);
    expect(find.text('REALIZAR PAGO'), findsNothing);
  });

  testWidgets('sin fecha del servidor no se inventa una fecha', (tester) async {
    await tester.pumpWidget(_subject());
    await tester.pumpAndSettle();

    expect(find.textContaining('periodo de prueba ya terminó'), findsOneWidget);
    expect(find.textContaining('/2026'), findsNothing);
  });

  testWidgets('sin canal de soporte configurado no se ofrece el enlace',
      (tester) async {
    await tester.pumpWidget(_subject(endedAt: DateTime(2026, 11, 15)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Habla con soporte'), findsNothing);
    expect(find.text('VER PLANES'), findsOneWidget);
  });

  testWidgets('no desborda en un telefono de 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _subject(endedAt: DateTime(2026, 11, 15), onSupport: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu demo de 7 días terminó'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
