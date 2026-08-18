import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';

void main() {
  group('CotizacionModel fiscal snapshots', () {
    test('keeps FULLTECH included-tax fixture total from API snapshot', () {
      final quote = CotizacionModel.fromApi({
        'id': 'quote-1',
        'createdAt': '2026-08-18T12:00:00.000Z',
        'customerName': 'FULLTECH',
        'customerPhone': '8090000000',
        'includeItbis': true,
        'itbisRate': 0.18,
        'fiscalTaxEnabled': true,
        'fiscalPriceMode': 'TAX_INCLUDED',
        'taxableBase': 21779.66,
        'taxAmount': 3920.34,
        'exemptAmount': 0,
        'discountAmount': 0,
        'total': 25700,
        'items': [
          {
            'productId': '00000000-0000-4000-8000-000000000001',
            'productNameSnapshot': 'FOTOCELDA',
            'unitPrice': 1200,
            'qty': 1,
            'lineTotal': 1200,
            'taxTreatment': 'INHERIT',
            'taxPriceMode': 'TAX_INCLUDED',
            'taxRate': 0.18,
            'taxableBase': 1016.95,
            'taxAmount': 183.05,
            'exemptAmount': 0,
            'taxIncluded': true,
            'taxExempt': false,
          },
          {
            'productId': '00000000-0000-4000-8000-000000000002',
            'productNameSnapshot': 'MOTOR WIFI',
            'unitPrice': 13000,
            'qty': 1,
            'lineTotal': 13000,
            'taxTreatment': 'INHERIT',
            'taxPriceMode': 'TAX_INCLUDED',
            'taxRate': 0.18,
            'taxableBase': 11016.95,
            'taxAmount': 1983.05,
            'exemptAmount': 0,
            'taxIncluded': true,
            'taxExempt': false,
          },
          {
            'productId': 'manual-service-extra',
            'productNameSnapshot': 'SERVICIO EXTRA',
            'unitPrice': 4000,
            'qty': 1,
            'lineTotal': 4000,
            'taxTreatment': 'INHERIT',
            'taxPriceMode': 'TAX_INCLUDED',
            'taxRate': 0.18,
            'taxableBase': 3389.83,
            'taxAmount': 610.17,
            'exemptAmount': 0,
            'taxIncluded': true,
            'taxExempt': false,
          },
          {
            'productId': 'manual-service-replacement',
            'productNameSnapshot': 'SERVICIO REEMPLAZO',
            'unitPrice': 6000,
            'qty': 1,
            'lineTotal': 6000,
            'taxTreatment': 'INHERIT',
            'taxPriceMode': 'TAX_INCLUDED',
            'taxRate': 0.18,
            'taxableBase': 5084.75,
            'taxAmount': 915.25,
            'exemptAmount': 0,
            'taxIncluded': true,
            'taxExempt': false,
          },
          {
            'productId': '00000000-0000-4000-8000-000000000005',
            'productNameSnapshot': 'LAMPARA',
            'unitPrice': 1500,
            'qty': 1,
            'lineTotal': 1500,
            'taxTreatment': 'INHERIT',
            'taxPriceMode': 'TAX_INCLUDED',
            'taxRate': 0.18,
            'taxableBase': 1271.18,
            'taxAmount': 228.82,
            'exemptAmount': 0,
            'taxIncluded': true,
            'taxExempt': false,
          },
        ],
      });

      expect(quote.total, 25700);
      expect(quote.subtotal, 21779.66);
      expect(quote.itbisAmount, 3920.34);
      expect(
        quote.items.fold<double>(0, (sum, item) => sum + item.total),
        25700,
      );
    });

    test(
      'added tax snapshot keeps final total separate from configured price',
      () {
        final quote = CotizacionModel.fromApi({
          'id': 'quote-2',
          'createdAt': '2026-08-18T12:00:00.000Z',
          'customerName': 'Cliente',
          'customerPhone': '8090000000',
          'fiscalTaxEnabled': true,
          'fiscalPriceMode': 'TAX_ADDED',
          'taxableBase': 1000,
          'taxAmount': 180,
          'exemptAmount': 0,
          'total': 1180,
          'items': [
            {
              'productId': 'manual',
              'productNameSnapshot': 'Servicio',
              'unitPrice': 1000,
              'qty': 1,
              'lineTotal': 1180,
              'taxableBase': 1000,
              'taxAmount': 180,
              'taxPriceMode': 'TAX_ADDED',
            },
          ],
        });

        expect(quote.items.single.unitPrice, 1000);
        expect(quote.items.single.total, 1180);
        expect(quote.total, 1180);
      },
    );
  });
}
