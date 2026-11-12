import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/widgets/pdf_preview_panel.dart';

void main() {
  group('pdfPreviewPanelWidthFor', () {
    test('en escritorio ocupa la mitad del ancho', () {
      expect(pdfPreviewPanelWidthFor(const Size(1600, 900)), 800);
      expect(pdfPreviewPanelWidthFor(const Size(1936, 1048)), 968);
    });

    test('respeta el ancho mínimo legible en ventanas medianas', () {
      expect(pdfPreviewPanelWidthFor(const Size(1000, 700)), 520);
    });

    test('en ventanas estrechas ocupa todo el ancho', () {
      expect(pdfPreviewPanelWidthFor(const Size(600, 900)), 600);
      expect(pdfPreviewPanelWidthFor(const Size(390, 844)), 390);
    });

    test('nunca supera el ancho de la ventana', () {
      for (final width in <double>[320, 719, 720, 1080, 2560]) {
        expect(
          pdfPreviewPanelWidthFor(Size(width, 800)),
          lessThanOrEqualTo(width),
        );
      }
    });
  });

  group('showPdfPreviewPanel', () {
    testWidgets('sitúa el panel pegado al borde izquierdo y a todo el alto', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPdfPreviewPanel<void>(
                  context: context,
                  builder: (panelContext) => const Center(
                    child: Text('Contenido del PDF'),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Contenido del PDF'), findsOneWidget);

      final surface = find.byType(PdfPreviewPanelSurface);
      expect(surface, findsOneWidget);
      final rect = tester.getRect(surface);
      expect(rect.left, 0);
      expect(rect.width, 800);
      expect(rect.top, 0);
      expect(rect.height, 900);
    });

    testWidgets('en ventana estrecha ocupa todo el ancho', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPdfPreviewPanel<void>(
                  context: context,
                  builder: (panelContext) => const Text('Contenido'),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byType(PdfPreviewPanelSurface));
      expect(rect.left, 0);
      expect(rect.width, 600);
      expect(rect.height, 900);
    });
  });
}
