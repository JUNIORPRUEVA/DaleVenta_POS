import 'package:daleventa_pos/features/ecf/ui/flow/ecf_completed_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pantalla de cierre del trámite.
///
/// Lo que se prueba es que el final se lea como una confirmación y que lleve a
/// donde se factura: si el cliente no encuentra el camino, toda la postulación
/// se queda sin uso.

Widget _harness({VoidCallback? onGoToSales, VoidCallback? onViewDocuments}) {
  return MaterialApp(
    home: Scaffold(
      body: EcfCompletedView(
        onGoToSales: onGoToSales ?? () {},
        onViewDocuments: onViewDocuments ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('confirma el final y ofrece ir a facturar', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('¡Felicidades!'), findsOneWidget);
    expect(
      find.textContaining('ya puede facturar electrónicamente'),
      findsOneWidget,
    );
    expect(find.text('Ir a ventas'), findsOneWidget);
    expect(find.text('Ver comprobantes electrónicos'), findsOneWidget);
  });

  testWidgets('ir a ventas y ver comprobantes llevan a cada destino', (
    tester,
  ) async {
    var sales = 0;
    var documents = 0;
    await tester.pumpWidget(
      _harness(
        onGoToSales: () => sales++,
        onViewDocuments: () => documents++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ecf_completed_go_sales')));
    await tester.pumpAndSettle();
    expect(sales, 1);
    expect(documents, 0);

    await tester.tap(
      find.byKey(const ValueKey('ecf_completed_view_documents')),
    );
    await tester.pumpAndSettle();
    expect(documents, 1);
  });

  testWidgets('a 360 px no desborda', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('¡Felicidades!'), findsOneWidget);
  });
}
