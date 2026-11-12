import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/utils/pdf_share.dart';

void main() {
  group('sharePdfWithSystem', () {
    test('no propaga errores cuando la plataforma no puede compartir', () async {
      // En el entorno de pruebas no hay complementos de plataforma: tanto
      // compartir como guardar fallan. Lo que se comprueba es que el fallo no
      // se propaga a la pantalla.
      final outcome = await sharePdfWithSystem(
        bytes: Uint8List.fromList(const <int>[37, 80, 68, 70]),
        fileName: 'cotizacion.pdf',
      );

      expect(outcome, isIn(PdfShareOutcome.values));
      expect(outcome, isNot(PdfShareOutcome.shared));
    });
  });

  group('Compartir PDF no abre el visor del sistema', () {
    test('el servicio de cotizaciones no usa Printing.sharePdf', () {
      final source = File(
        'lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('Printing.sharePdf')));
      expect(source, contains('sharePdfWithSystem'));
    });

    test('el menú de acciones del PDF no usa Printing.sharePdf', () {
      final source = File(
        'lib/core/widgets/pdf_action_menu.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('Printing.sharePdf')));
      expect(source, contains('sharePdfWithSystem'));
    });

    test('las vistas previas de cotización usan el panel lateral', () {
      for (final path in <String>[
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
        'lib/modules/cotizaciones/cotizaciones_historial_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('showPdfPreviewPanel<void>'), reason: path);
      }
    });

    test('las vistas previas de factura usan el panel lateral', () {
      // `mis_ventas_screen.dart` ya no existe: producción la sustituyó por el
      // historial del TPV y el panel de ventas recientes.
      for (final path in <String>[
        'lib/modules/ventas/sales_credit_screen.dart',
        'lib/modules/ventas/tpv_sales_history_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('showPdfPreviewPanel<void>'), reason: path);
      }
    });
  });
}
