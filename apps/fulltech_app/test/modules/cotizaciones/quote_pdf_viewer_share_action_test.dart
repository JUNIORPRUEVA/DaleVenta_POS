import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quote PDF viewer share action', () {
    test('current quote viewer uses direct PDF share without dropdown', () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
      ).readAsStringSync();
      final viewer = _extractViewerSource(source);

      expect(viewer, contains("'PDF de cotización'"));
      expect(viewer, contains('TextButton.icon'));
      expect(viewer, contains('runShareAction'));
      expect(viewer, contains('_QuotePdfShareAction.sharePdf'));
      expect(viewer, isNot(contains('_QuotePdfShareAction.shareClient,')));
      expect(viewer, isNot(contains('PopupMenuButton<_QuotePdfShareAction>')));
      expect(viewer, isNot(contains('PopupMenuItem<_QuotePdfShareAction>')));
      expect(viewer, isNot(contains('for (final action')));
      expect(viewer, contains('Navigator.pop(context)'));
    });

    test('quote history viewer uses direct PDF share without dropdown', () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_historial_screen.dart',
      ).readAsStringSync();
      final viewer = _extractViewerSource(source);

      expect(viewer, contains("'PDF de cotización'"));
      expect(viewer, contains('TextButton.icon'));
      expect(viewer, contains('runShareAction'));
      expect(viewer, contains('_QuotePdfShareAction.sharePdf'));
      expect(viewer, isNot(contains('_QuotePdfShareAction.shareClient,')));
      expect(viewer, isNot(contains('PopupMenuButton<_QuotePdfShareAction>')));
      expect(viewer, isNot(contains('PopupMenuItem<_QuotePdfShareAction>')));
      expect(viewer, isNot(contains('for (final action')));
      expect(viewer, contains('Navigator.pop(context)'));
    });

    test('shared document menu remains available for other PDF viewers', () {
      final source = File(
        'lib/core/widgets/pdf_action_menu.dart',
      ).readAsStringSync();

      expect(source, contains('PopupMenuButton<PdfDocumentAction>'));
      expect(source, contains('Compartir PDF'));
      expect(source, contains('Compartir con cliente'));
      expect(source, contains('Guardar en descargas'));
    });
  });
}

String _extractViewerSource(String source) {
  final start = source.indexOf("'PDF de cotización'");
  expect(start, isNonNegative);
  final end = source.indexOf('SfPdfViewer.memory', start);
  expect(end, isNonNegative);
  return source.substring(start, end);
}
