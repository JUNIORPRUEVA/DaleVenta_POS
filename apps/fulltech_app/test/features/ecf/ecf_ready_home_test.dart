import 'package:daleventa_pos/features/ecf/ui/ecf_ready_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> pump(
    WidgetTester tester, {
    String company = 'a',
    String user = 'u',
    bool manage = true,
    VoidCallback? documents,
    VoidCallback? numbering,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EcfReadyHome(
            key: ValueKey('$company:$user'),
            companyId: company,
            userId: user,
            canManageNumbering: manage,
            onSales: () {},
            onDocuments: documents ?? () {},
            onNumbering: numbering ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'acknowledgement appears once per company/user, never as a repeated completion screen',
    (tester) async {
      await pump(tester);
      expect(find.text('Tu empresa está lista para facturar'), findsOneWidget);
      expect(find.text('¡Felicidades!'), findsNothing);
      expect(find.text('Consulta tus facturas o administra la numeración de tu empresa.'), findsNothing);
      expect(find.text('Consulta las facturas generadas y su estado fiscal.'), findsNothing);
      expect(find.text('Revisa tus rangos autorizados y la configuración.'), findsNothing);
      await tester.tap(find.byTooltip('Cerrar confirmación'));
      await tester.pump();
      expect(find.text('Tu empresa está lista para facturar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(find.text('Tu empresa está lista para facturar'), findsNothing);
      await pump(tester, company: 'b');
      expect(find.text('Tu empresa está lista para facturar'), findsOneWidget);
      await pump(tester, company: 'b', user: 'v');
      expect(find.text('Tu empresa está lista para facturar'), findsOneWidget);
    },
  );
  testWidgets('direct actions respect numbering permission and fit mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var documents = 0, numbering = 0;
    await pump(
      tester,
      documents: () => documents++,
      numbering: () => numbering++,
    );
    await tester.tap(find.text('Facturas electrónicas'));
    await tester.tap(find.text('Numeración fiscal'));
    expect(documents, 1);
    expect(numbering, 1);
    expect(find.byType(BottomSheet), findsNothing);
    await pump(tester, company: 'c', manage: false);
    expect(find.text('Numeración fiscal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
