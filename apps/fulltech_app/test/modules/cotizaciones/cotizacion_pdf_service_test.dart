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

  group('Cotizacion PDF fiscal data', () {
    test(
      'producto exento conserva base exenta, ITBIS cero y total snapshot',
      () {
        final data = buildCotizacionPdfViewData(
          cotizacion: _quote(
            taxableBase: 0,
            taxAmount: 0,
            exemptAmount: 900,
            total: 900,
            items: [_line(name: 'Servicio exento', exempt: true, price: 900)],
          ),
          company: _company(),
        );

        expect(data.lines.single.taxLabel, 'Exento');
        expect(data.lines.single.baseAmount, 900);
        expect(data.lines.single.taxAmount, 0);
        expect(data.totals.exemptAmount, 900);
        expect(data.totals.taxAmount, 0);
        expect(data.totals.total, 900);
      },
    );

    test('producto gravado usa snapshots fiscales finales', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          taxableBase: 2500,
          taxAmount: 450,
          total: 2950,
          items: [_line(name: 'Producto gravado', price: 2500, tax: 450)],
        ),
        company: _company(),
      );

      expect(data.lines.single.taxableBase, 2500);
      expect(data.lines.single.taxAmount, 450);
      expect(data.lines.single.total, 2950);
      expect(data.totals.taxableBase, 2500);
      expect(data.totals.taxAmount, 450);
    });

    test('TAX_ADDED muestra precio base y total con ITBIS agregado', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          priceMode: 'TAX_ADDED',
          taxableBase: 2500,
          taxAmount: 450,
          total: 2950,
          items: [
            _line(
              name: 'Producto TAX_ADDED',
              price: 2500,
              tax: 450,
              priceMode: 'TAX_ADDED',
            ),
          ],
        ),
        company: _company(),
      );

      expect(data.quote.fiscalCondition, 'ITBIS agregado al precio');
      expect(data.lines.single.unitPrice, 2500);
      expect(data.lines.single.baseAmount, 2500);
      expect(data.lines.single.total, 2950);
    });

    test('TAX_INCLUDED muestra base e ITBIS desde snapshots', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          priceMode: 'TAX_INCLUDED',
          taxableBase: 1000,
          taxAmount: 180,
          total: 1180,
          items: [
            _line(
              name: 'Producto TAX_INCLUDED',
              price: 1180,
              taxableBase: 1000,
              tax: 180,
              total: 1180,
              priceMode: 'TAX_INCLUDED',
              taxIncluded: true,
            ),
          ],
        ),
        company: _company(),
      );

      expect(data.quote.fiscalCondition, 'Precios con ITBIS incluido');
      expect(data.lines.single.unitPrice, 1180);
      expect(data.lines.single.baseAmount, 1000);
      expect(data.lines.single.taxAmount, 180);
      expect(data.lines.single.total, 1180);
    });

    test('descuento individual se separa del resumen general', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          taxableBase: 2000,
          taxAmount: 360,
          discountAmount: 500,
          total: 2360,
          items: [
            _line(
              name: 'Producto con descuento',
              price: 2000,
              originalUnitPrice: 2500,
              taxableBase: 2000,
              tax: 360,
              total: 2360,
            ),
          ],
        ),
        company: _company(),
      );

      expect(data.lines.single.lineDiscountAmount, 500);
      expect(data.totals.productDiscount, 500);
      expect(data.totals.generalDiscount, 0);
      expect(data.totals.taxAmount, 360);
    });

    test('descuento general se infiere desde descuento fiscal total', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          taxableBase: 2300,
          taxAmount: 414,
          discountAmount: 200,
          globalDiscountAmount: 200,
          total: 2714,
          items: [
            _line(
              name: 'Producto con descuento general',
              price: 2500,
              taxableBase: 2300,
              tax: 414,
              total: 2714,
            ),
          ],
        ),
        company: _company(),
      );

      expect(data.totals.productDiscount, 0);
      expect(data.totals.generalDiscount, 200);
      expect(data.totals.taxableBase, 2300);
      expect(data.totals.taxAmount, 414);
    });

    test(
      'ambos descuentos simultaneamente no duplican el descuento general',
      () {
        final data = buildCotizacionPdfViewData(
          cotizacion: _quote(
            taxableBase: 1800,
            taxAmount: 324,
            discountAmount: 700,
            globalDiscountAmount: 700,
            total: 2124,
            items: [
              _line(
                name: 'Producto ambos descuentos',
                price: 2000,
                originalUnitPrice: 2500,
                taxableBase: 1800,
                tax: 324,
                total: 2124,
              ),
            ],
          ),
          company: _company(),
        );

        expect(data.totals.productDiscount, 500);
        expect(data.totals.generalDiscount, 200);
        expect(data.totals.productDiscount + data.totals.generalDiscount, 700);
        expect(data.totals.taxAmount, 324);
      },
    );

    test('mezcla exento y gravado conserva cada snapshot de linea', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          taxableBase: 2500,
          taxAmount: 450,
          exemptAmount: 900,
          total: 3850,
          items: [
            _line(name: 'Exento', exempt: true, price: 900),
            _line(name: 'Gravado', price: 2500, tax: 450),
          ],
        ),
        company: _company(),
      );

      expect(data.lines.first.taxLabel, 'Exento');
      expect(data.lines.first.taxAmount, 0);
      expect(data.lines.last.taxLabel, 'Gravado + ITBIS');
      expect(data.lines.last.taxAmount, 450);
      expect(data.totals.exemptAmount, 900);
      expect(data.totals.taxableBase, 2500);
      expect(data.totals.total, 3850);
    });

    test(
      'vista previa completa ITBIS por linea cuando el draft no trae snapshots',
      () {
        final data = buildCotizacionPdfViewData(
          cotizacion: _quote(
            taxableBase: 1652.57,
            taxAmount: 297.47,
            exemptAmount: 2203.43,
            discountAmount: 0,
            globalDiscountAmount: 344,
            total: 4153.47,
            items: [
              _line(
                name: '2CONNET LECTOR',
                price: 2400,
                originalUnitPrice: 2500,
                taxTreatment: 'EXEMPT',
                priceMode: 'NO_TAX',
                fiscalSnapshot: false,
              ),
              _line(
                name: 'AURICULARES INPODS 12',
                price: 800,
                taxTreatment: 'TAXABLE',
                priceMode: 'TAX_ADDED',
                fiscalSnapshot: false,
              ),
              _line(
                name: 'AURICULARES G11',
                price: 1000,
                taxTreatment: 'TAXABLE',
                priceMode: 'TAX_ADDED',
                fiscalSnapshot: false,
              ),
            ],
          ),
          company: _company(),
        );

        expect(data.totals.subtotal, 4300);
        expect(data.totals.productDiscount, 100);
        expect(data.totals.generalDiscount, 344);
        expect(data.lines.first.taxAmount, 0);
        expect(data.lines[1].taxAmount, greaterThan(0));
        expect(data.lines[2].taxAmount, greaterThan(0));
        expect(
          data.lines
              .fold<double>(0, (sum, line) => sum + line.taxAmount)
              .toStringAsFixed(2),
          '297.47',
        );
      },
    );

    test('impuestos desactivados mantiene documento limpio', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          fiscalTaxEnabled: false,
          includeItbis: false,
          taxableBase: 0,
          taxAmount: 0,
          exemptAmount: 0,
          total: 900,
          items: [
            _line(
              name: 'Producto normal',
              price: 900,
              taxTreatment: 'INHERIT',
              priceMode: 'NO_TAX',
              fiscalSnapshot: false,
            ),
          ],
        ),
        company: _company(),
      );

      expect(data.quote.fiscalCondition, 'Impuestos desactivados');
      expect(data.lines.single.taxLabel, 'Sin impuesto');
      expect(data.totals.fiscalEnabled, isFalse);
      expect(data.totals.taxAmount, 0);
    });

    test('cliente vacio se presenta como consumidor final', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote(
          taxableBase: 0,
          taxAmount: 0,
          exemptAmount: 900,
          total: 900,
          customerName: 'Sin cliente',
          customerPhone: '',
          items: [_line(name: 'Servicio', exempt: true, price: 900)],
        ),
        company: _company(),
      );

      expect(data.customer.name, 'Consumidor final');
      expect(data.customer.phone, isEmpty);
    });

    test('documento con multiples productos genera PDF multipagina', () async {
      final quote = _quote(
        taxableBase: 80000,
        taxAmount: 14400,
        total: 94400,
        items: [
          for (var index = 0; index < 80; index++)
            _line(name: 'Producto largo ${index + 1}', price: 1000, tax: 180),
        ],
      );

      final bytes = await buildCotizacionPdf(
        cotizacion: quote,
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(buildCotizacionPdfViewData(cotizacion: quote).lines.length, 80);
    });

    test('no conserva textos tecnicos internos en la plantilla', () {
      final source = File(
        'lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('Importes de línea guardados')));
      expect(source, isNot(contains("_headerCell('Monto'")));
      expect(
        source,
        isNot(contains('_descriptionCell(item.description, item.taxLabel)')),
      );
      expect(source, contains('final hasProductDiscount'));
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

CotizacionModel _quote({
  bool fiscalTaxEnabled = true,
  bool includeItbis = true,
  String priceMode = 'TAX_ADDED',
  required double taxableBase,
  required double taxAmount,
  double exemptAmount = 0,
  double discountAmount = 0,
  double globalDiscountAmount = 0,
  required double total,
  required List<CotizacionItem> items,
  String customerName = 'CANATECH SRL',
  String customerPhone = '809-222-2222',
}) {
  return CotizacionModel.fromApi({
    'id': '22222222-2222-4222-8222-222222222222',
    'createdAt': '2026-08-18T10:00:00.000Z',
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerTaxId': '132588312',
    'customerAddress': 'Av. Principal 123',
    'customerEmail': 'cliente@example.com',
    'includeItbis': includeItbis,
    'itbisRate': 0.18,
    'fiscalTaxEnabled': fiscalTaxEnabled,
    'fiscalPriceMode': priceMode,
    'taxableBase': taxableBase,
    'taxAmount': taxAmount,
    'exemptAmount': exemptAmount,
    'discountAmount': discountAmount,
    'globalDiscountAmount': globalDiscountAmount,
    'total': total,
    'items': items.map((item) => item.toMap()).toList(),
  });
}

CotizacionItem _line({
  required String name,
  required double price,
  double qty = 1,
  double? originalUnitPrice,
  double? taxableBase,
  double tax = 0,
  double? total,
  bool exempt = false,
  bool taxIncluded = false,
  String taxTreatment = 'TAXABLE',
  String priceMode = 'TAX_ADDED',
  bool fiscalSnapshot = true,
}) {
  final gross = (originalUnitPrice ?? price) * qty;
  final lineTotal =
      total ??
      (exempt
          ? price * qty
          : priceMode == 'TAX_ADDED'
          ? (taxableBase ?? price * qty) + tax
          : price * qty);
  return CotizacionItem(
    productId: '00000000-0000-4000-8000-000000000001',
    nombre: name,
    imageUrl: null,
    originalUnitPrice: originalUnitPrice,
    unitPrice: price,
    qty: qty,
    taxTreatment: exempt ? 'EXEMPT' : taxTreatment,
    taxRate: tax > 0 ? 0.18 : 0,
    taxPriceMode: priceMode,
    grossAmount: fiscalSnapshot ? gross : 0,
    taxableBase: fiscalSnapshot && !exempt ? (taxableBase ?? price * qty) : 0,
    taxAmount: fiscalSnapshot ? tax : 0,
    exemptAmount: fiscalSnapshot && exempt ? price * qty : 0,
    lineTotalSnapshot: lineTotal,
    taxIncluded: taxIncluded,
    taxExempt: exempt,
  );
}
