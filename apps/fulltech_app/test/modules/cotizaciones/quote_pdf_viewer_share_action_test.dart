import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Visor de PDF de cotización', () {
    test('el POS abre el panel con acciones de compartir y descargar', () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
      ).readAsStringSync();

      expect(source, contains('showPdfPreviewPanel<void>'));
      expect(source, contains('PdfPreviewPanelHeader'));
      expect(source, contains('PdfPreviewStage'));
      expect(source, contains('PdfPanelIcons.share'));
      expect(source, contains('PdfPanelIcons.download'));
      // El panel se abre antes de tener el PDF: se construye en segundo plano.
      expect(source, contains('_buildQuotePdfBytes'));
      expect(source, contains('FutureBuilder'));
      // Nada de visores incrustados en la pantalla ni de hojas del sistema.
      expect(source, isNot(contains('SfPdfViewer.memory')));
      expect(source, isNot(contains('Printing.sharePdf')));
    });

    test('el historial de cotizaciones abre el panel con las mismas acciones', () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_historial_screen.dart',
      ).readAsStringSync();

      expect(source, contains('showPdfPreviewPanel<void>'));
      expect(source, contains('PdfPreviewPanelHeader'));
      expect(source, contains('PdfPreviewStage'));
      expect(source, contains('PdfPanelIcons.share'));
      expect(source, contains('PdfPanelIcons.download'));
      expect(source, isNot(contains('SfPdfViewer.memory')));
      expect(source, isNot(contains('Printing.sharePdf')));
    });

    test('las vistas previas de factura usan el mismo panel', () {
      // `mis_ventas_screen.dart` ya no existe: producción la sustituyó por el
      // historial del TPV y el panel de ventas recientes.
      for (final path in <String>[
        'lib/modules/ventas/sales_credit_screen.dart',
        'lib/modules/ventas/tpv_sales_history_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('PdfPreviewPanelHeader'), reason: path);
        expect(source, contains('PdfPreviewStage'), reason: path);
        expect(source, contains('PdfPanelIcons.download'), reason: path);
      }
    });
  });
}
