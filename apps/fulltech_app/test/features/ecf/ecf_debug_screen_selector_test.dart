import 'package:daleventa_pos/features/ecf/ui/debug/ecf_debug_screen_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPreview(
    WidgetTester tester,
    EcfDebugScreen screen, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: EcfDebugPreview(screen: screen),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('las tres vistas reales se dibujan a 390 px sin desbordar', (
    tester,
  ) async {
    expect(EcfDebugScreen.values.length, 3);
    for (final screen in EcfDebugScreen.values) {
      await pumpPreview(tester, screen);
      expect(tester.takeException(), isNull, reason: screen.label);
      expect(find.text('Vista de revisión · ${screen.label}'), findsOneWidget);
    }
  });

  testWidgets('las tres vistas reales se dibujan en escritorio sin desbordar', (
    tester,
  ) async {
    for (final screen in EcfDebugScreen.values) {
      await pumpPreview(
        tester,
        screen,
        size: const Size(1280, 900),
      );
      expect(tester.takeException(), isNull, reason: screen.label);
      expect(find.text('Vista de revisión · ${screen.label}'), findsOneWidget);
    }
  });

  testWidgets('Preparación completa vive dentro de Preparación', (
    tester,
  ) async {
    await pumpPreview(tester, EcfDebugScreen.preparation);

    expect(find.text('Preparación'), findsOneWidget);
    expect(find.text('Preparación completa'), findsNothing);
    expect(find.text('Iniciar postulación'), findsOneWidget);
    expect(find.text('Certificado digital'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tu postulación usa un indicador compacto y abre DOSA', (
    tester,
  ) async {
    await pumpPreview(tester, EcfDebugScreen.postulation);

    expect(find.text('Solicitud'), findsOneWidget);
    expect(find.text('Pruebas'), findsOneWidget);
    expect(find.text('Certificación'), findsOneWidget);
    expect(find.text('Etapas'), findsNothing);
    expect(find.text('Continuar en DOSA'), findsOneWidget);
    expect(find.textContaining('FullPOS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
