import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/utils/pdf_document_file_name.dart';

void main() {
  group('buildPdfDocumentFileName', () {
    test('usa el nombre del cliente bien escrito', () {
      expect(
        buildPdfDocumentFileName(
          documentKind: 'Cotización',
          customerName: 'juan pérez',
          fallbackCode: 'COT-1234',
        ),
        'Cotización de Juan Pérez.pdf',
      );
      expect(
        buildPdfDocumentFileName(
          documentKind: 'Factura',
          customerName: 'MARIA DE LA CRUZ',
          fallbackCode: 'F-1',
        ),
        'Factura de Maria de la Cruz.pdf',
      );
    });

    test('conserva siglas y recorta espacios', () {
      expect(
        buildPdfDocumentFileName(
          documentKind: 'Cotización',
          customerName: '  ferreteria   el sol srl ',
          fallbackCode: 'COT-9',
        ),
        'Cotización de Ferreteria el Sol SRL.pdf',
      );
    });

    test('sin cliente real usa el código del documento', () {
      for (final empty in <String?>[null, '', '   ', 'Consumidor final']) {
        expect(
          buildPdfDocumentFileName(
            documentKind: 'Factura',
            customerName: empty,
            fallbackCode: 'FAC-000123',
          ),
          'Factura FAC-000123.pdf',
          reason: 'nombre: $empty',
        );
      }
    });

    test('sin nombre ni código deja un archivo identificable', () {
      expect(
        buildPdfDocumentFileName(documentKind: 'Cotización'),
        'Cotización.pdf',
      );
    });

    test('no deja caracteres inválidos en el nombre', () {
      final name = buildPdfDocumentFileName(
        documentKind: 'Factura',
        customerName: 'A/B:C*D?E',
        fallbackCode: 'F-1',
      );

      expect(name, contains('Factura de'));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('*')));
      expect(name, isNot(contains('?')));
      expect(name.endsWith('.pdf'), isTrue);
    });
  });
}
