import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/utils/cotizacion_pdf_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('Cotizacion PDF pagination', () {
    test('uses full first-page header and compact continuation header', () {
      final source = File(
        'lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart',
      ).readAsStringSync();

      expect(source, contains('if (pageNumber > 1)'));
      expect(source, contains('_continuationHeader('));
      expect(source, contains('Cotización · Continuación'));
      expect(source, contains('_customerPanel(customer)'));
      expect(source, isNot(contains('Continuación de la cotización')));
    });

    test('one product generates a valid one-page quote PDF', () async {
      final bytes = await buildCotizacionPdf(
        cotizacion: _quoteWithItems(1),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_countPdfPages(bytes), 1);
    });

    test(
      'many products generate continuation pages without layout failure',
      () async {
        final bytes = await buildCotizacionPdf(
          cotizacion: _quoteWithItems(55),
          company: _company(),
        );

        expect(bytes.length, greaterThan(1000));
        expect(_countPdfPages(bytes), greaterThanOrEqualTo(2));
      },
    );

    test('large quote supports three or more pages', () async {
      final bytes = await buildCotizacionPdf(
        cotizacion: _quoteWithItems(120),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_countPdfPages(bytes), greaterThanOrEqualTo(3));
    });

    test('bottom summary remains a single unbroken section in source', () {
      final source = File(
        'lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart',
      ).readAsStringSync();
      final bottomStart = source.indexOf('pw.Widget _bottomSection');
      final totalsStart = source.indexOf('pw.Widget _totalsPanel');

      expect(bottomStart, isNonNegative);
      expect(totalsStart, greaterThan(bottomStart));
      expect(source.substring(bottomStart, totalsStart), contains('pw.Row('));
      expect(source.substring(bottomStart, totalsStart), contains('_panel('));
      final totalsSource = source.substring(totalsStart).replaceAll('\r\n', '\n');
      expect(totalsSource, contains("pw.Text(\n          'Resumen'"));
    });

    test('footer keeps page X of Y text', () {
      final source = File(
        'lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart',
      ).readAsStringSync();

      expect(source, contains("'Página \$pageNumber de \$totalPages'"));
      expect(source, contains("'FullPOS Cloud'"));
    });
  });
}

CompanySettings _company() {
  return CompanySettings.empty().copyWith(
    companyName: 'FULLTECH, SRL',
    rnc: '133080206',
    address: 'Santo Domingo, República Dominicana',
    phone: '809-000-0000',
  );
}

CotizacionModel _quoteWithItems(int count) {
  final items = [
    for (var index = 0; index < count; index++)
      CotizacionItem(
        productId:
            '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
        nombre: 'Producto de prueba ${index + 1}',
        imageUrl: null,
        originalUnitPrice: 1000,
        unitPrice: 1000,
        qty: 1,
        taxTreatment: 'TAXABLE',
        taxRate: 0.18,
        taxPriceMode: 'TAX_ADDED',
        grossAmount: 1000,
        taxableBase: 1000,
        taxAmount: 180,
        lineTotalSnapshot: 1180,
      ),
  ];
  return CotizacionModel(
    id: '22222222-2222-4222-8222-222222222222',
    createdAt: DateTime(2026, 8, 20, 18, 47),
    customerId: null,
    customerName: 'Consumidor final',
    customerPhone: '',
    note: '',
    includeItbis: true,
    itbisRate: 0.18,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 1000.0 * count,
    taxAmount: 180.0 * count,
    exemptAmount: 0,
    fiscalDiscountAmount: 0,
    totalSnapshot: 1180.0 * count,
    items: items,
  );
}

int _countPdfPages(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page\b').allMatches(text).length;
}
