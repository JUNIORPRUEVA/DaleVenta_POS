import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/utils/cotizacion_pdf_service.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('Fiscal PDF templates', () {
    test('builds golden FULLTECH/CANATECH quote PDF without NCF', () async {
      final bytes = await buildCotizacionPdf(
        cotizacion: _goldenQuote(),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_goldenQuote().total, 25700);
      expect(_goldenQuote().taxableBase, 21779.66);
      expect(_goldenQuote().taxAmount, 3920.34);
    });

    test('builds golden B01 invoice PDF from stored line snapshots', () async {
      final sale = _goldenSale(voucherType: 'B01', ncf: 'B0100000014');
      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.totalSold, 25700);
      expect(sale.taxableBase, 21779.66);
      expect(sale.taxAmount, 3920.34);
      expect(sale.items.fold<double>(0, (s, i) => s + i.subtotalSold), 25700);
      expect(
        sale.items
            .fold<double>(0, (s, i) => s + i.taxAmount)
            .toStringAsFixed(2),
        '3920.34',
      );
      expect(
        sale.items
            .fold<double>(0, (s, i) => s + i.taxableBase)
            .toStringAsFixed(2),
        '21779.66',
      );
    });

    test(
      'builds tax-enabled normal invoice PDF without requiring NCF',
      () async {
        final sale = _goldenSale(voucherType: '', ncf: '');
        final bytes = await buildSaleInvoicePdf(
          sale: sale,
          company: _company(),
        );

        expect(bytes.length, greaterThan(1000));
        expect(sale.fiscalTaxEnabled, isTrue);
        expect(sale.ncf, '');
        expect(sale.taxableBase, 21779.66);
        expect(sale.taxAmount, 3920.34);
      },
    );

    test(
      'builds B02 invoice PDF without requiring customer fiscal data',
      () async {
        final sale = _goldenSale(
          voucherType: 'B02',
          ncf: 'B0200000014',
          customerName: 'Consumidor Final',
          fiscalCustomerTaxId: null,
        );
        final bytes = await buildSaleInvoicePdf(
          sale: sale,
          company: _company(),
        );

        expect(bytes.length, greaterThan(1000));
        expect(sale.fiscalVoucherType, 'B02');
        expect(sale.ncf, 'B0200000014');
      },
    );

    test('maps ticket fiscal data from sale item snapshots', () {
      final sale = _goldenSale(voucherType: 'B01', ncf: 'B0100000014');
      final ticket = TicketData.fromSale(sale);

      expect(ticket.ncf, 'B0100000014');
      expect(ticket.fiscalVoucherType, 'B01');
      expect(ticket.taxableBase, 21779.66);
      expect(ticket.itbis, 3920.34);
      expect(ticket.items.first.taxableBase, 1016.95);
      expect(ticket.items.first.taxAmount, 183.05);
      expect(ticket.items.first.total, 1200);
    });

    test('tax off invoice PDF stays clean for legacy sale', () async {
      final sale = _legacySale();
      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.fiscalTaxEnabled, isFalse);
      expect(sale.taxAmount, 0);
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

CotizacionModel _goldenQuote() {
  return CotizacionModel.fromApi({
    'id': '22222222-2222-4222-8222-222222222222',
    'createdAt': '2026-08-18T10:00:00.000Z',
    'customerName': 'CANATECH SRL',
    'customerPhone': '809-222-2222',
    'includeItbis': true,
    'itbisRate': 0.18,
    'fiscalTaxEnabled': true,
    'fiscalPriceMode': 'TAX_INCLUDED',
    'taxableBase': 21779.66,
    'taxAmount': 3920.34,
    'exemptAmount': 0,
    'discountAmount': 0,
    'subtotal': 21779.66,
    'itbisAmount': 3920.34,
    'total': 25700,
    'items': _goldenLineMaps(),
  });
}

SaleModel _goldenSale({
  required String voucherType,
  required String ncf,
  String customerName = 'CANATECH SRL',
  String? fiscalCustomerTaxId = '132588312',
}) {
  return SaleModel(
    id: '33333333-3333-4333-8333-333333333333',
    userId: 'user-a',
    userName: 'Caja',
    customerId: 'client-a',
    customerName: customerName,
    customerPhone: '809-222-2222',
    saleDate: DateTime(2026, 8, 18, 10),
    note: '',
    totalSold: 25700,
    totalCost: 0,
    totalProfit: 25700,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 25700,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_INCLUDED',
    taxableBase: 21779.66,
    taxAmount: 3920.34,
    exemptAmount: 0,
    discountAmount: 0,
    fiscalVoucherType: voucherType,
    ncf: ncf,
    fiscalCustomerTaxId: fiscalCustomerTaxId,
    fiscalCustomerName: customerName,
    items: _goldenLineMaps().asMap().entries.map((entry) {
      final map = entry.value;
      return SaleItemModel(
        id: 'sale-item-${entry.key}',
        productId: 'product-${entry.key}',
        productNameSnapshot: map['productNameSnapshot'] as String,
        productImageSnapshot: null,
        qty: map['qty'] as double,
        priceSoldUnit: map['unitPrice'] as double,
        costUnitSnapshot: 0,
        subtotalSold: map['lineTotal'] as double,
        subtotalCost: 0,
        profit: map['lineTotal'] as double,
        category: null,
        grossAmount: map['grossAmount'] as double,
        lineDiscountAmount: 0,
        taxableBase: map['taxableBase'] as double,
        taxRate: 0.18,
        taxAmount: map['taxAmount'] as double,
        exemptAmount: 0,
        taxIncluded: true,
        taxExempt: false,
      );
    }).toList(),
  );
}

SaleModel _legacySale() {
  return SaleModel(
    id: '44444444-4444-4444-8444-444444444444',
    userId: 'user-a',
    userName: 'Caja',
    customerId: null,
    customerName: 'Consumidor Final',
    customerPhone: '',
    saleDate: DateTime(2026, 8, 18, 11),
    note: '',
    totalSold: 100,
    totalCost: 0,
    totalProfit: 100,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 100,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    items: const [
      SaleItemModel(
        id: 'legacy-item',
        productId: null,
        productNameSnapshot: 'Venta rápida',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 100,
        costUnitSnapshot: 0,
        subtotalSold: 100,
        subtotalCost: 0,
        profit: 100,
        category: null,
      ),
    ],
  );
}

List<Map<String, Object>> _goldenLineMaps() {
  return const [
    {
      'productNameSnapshot': 'FOTOCELDA PARA MOTOR',
      'qty': 1.0,
      'unitPrice': 1200.0,
      'grossAmount': 1200.0,
      'taxableBase': 1016.95,
      'taxAmount': 183.05,
      'lineTotal': 1200.0,
    },
    {
      'productNameSnapshot': 'MOTOR WIFI 800KG',
      'qty': 1.0,
      'unitPrice': 13000.0,
      'grossAmount': 13000.0,
      'taxableBase': 11016.95,
      'taxAmount': 1983.05,
      'lineTotal': 13000.0,
    },
    {
      'productNameSnapshot': 'SERVICIO EXTRA',
      'qty': 1.0,
      'unitPrice': 4000.0,
      'grossAmount': 4000.0,
      'taxableBase': 3389.83,
      'taxAmount': 610.17,
      'lineTotal': 4000.0,
    },
    {
      'productNameSnapshot': 'SERVICIO REEMPLAZO',
      'qty': 1.0,
      'unitPrice': 6000.0,
      'grossAmount': 6000.0,
      'taxableBase': 5084.75,
      'taxAmount': 915.25,
      'lineTotal': 6000.0,
    },
    {
      'productNameSnapshot': 'LÁMPARA PARA MOTOR',
      'qty': 1.0,
      'unitPrice': 1500.0,
      'grossAmount': 1500.0,
      'taxableBase': 1271.18,
      'taxAmount': 228.82,
      'lineTotal': 1500.0,
    },
  ];
}
