import 'package:daleventa_pos/modules/ventas/ecf_pos_fiscal.dart';
import 'package:daleventa_pos/modules/ventas/ecf_pos_fiscal_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El selector de comprobante vive en la franja superior del carrito, que en
/// escritorio mide ~365 px de ancho útil. Estas pruebas fijan ese ancho para que
/// un cambio de texto, padding o tipografía no lo rompa en silencio, y fijan
/// también que una venta «Normal» no muestre ningún aviso.
void main() {
  Future<void> pumpSelectorAt(
    WidgetTester tester,
    double width, {
    EcfPosFiscalMode? selected = EcfPosFiscalMode.e32,
    bool missingBuyer = false,
    List<EcfPosFiscalMode> modes = const [
      EcfPosFiscalMode.e31,
      EcfPosFiscalMode.e32,
    ],
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: EcfPosFiscalSelector(
              modes: modes,
              selected: selected,
              missingBuyer: missingBuyer,
              compact: true,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no desborda al ancho real del carrito', (tester) async {
    for (final width in <double>[320, 365, 390, 420]) {
      await pumpSelectorAt(tester, width);
      expect(
        tester.takeException(),
        isNull,
        reason: 'el selector desborda a $width px de ancho',
      );
    }
  });

  testWidgets('la ficha muestra etiqueta y comprobante elegido', (tester) async {
    await pumpSelectorAt(tester, 365);
    expect(find.text('COMPROBANTE ELECTRÓNICO'), findsOneWidget);
    expect(find.text('E32 - Consumo'), findsOneWidget);
  });

  testWidgets('avisa cuando falta el receptor del E31', (tester) async {
    await pumpSelectorAt(
      tester,
      365,
      selected: EcfPosFiscalMode.e31,
      missingBuyer: true,
    );
    expect(
      find.text('E31 exige un cliente con RNC/Cédula y nombre.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('la venta normal no muestra ningún aviso ni pide motivo', (
    tester,
  ) async {
    await pumpSelectorAt(
      tester,
      365,
      selected: EcfPosFiscalMode.normal,
      modes: const [
        EcfPosFiscalMode.e31,
        EcfPosFiscalMode.e32,
        EcfPosFiscalMode.normal,
      ],
    );

    expect(find.text('Normal - sin comprobante electrónico'), findsOneWidget);
    // Nada de advertencias: es una venta interna que no se declara.
    expect(find.textContaining('excepción'), findsNothing);
    expect(find.textContaining('auditoría'), findsNothing);
    expect(find.textContaining('motivo'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('el desplegable se abre enumerado desde el propio selector', (
    tester,
  ) async {
    await pumpSelectorAt(
      tester,
      365,
      modes: const [
        EcfPosFiscalMode.e31,
        EcfPosFiscalMode.e32,
        EcfPosFiscalMode.normal,
      ],
    );

    await tester.tap(find.text('E32 - Consumo'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('E31 - Crédito fiscal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin tipos disponibles no dibuja nada', (tester) async {
    await pumpSelectorAt(tester, 365, modes: const [], selected: null);

    expect(find.text('COMPROBANTE ELECTRÓNICO'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
