import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/utils/cotizacion_pdf_service.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';

/// Regresión del caso real: Subtotal RD$8,050 · Descuentos por productos
/// -RD$400 · Descuento general -RD$200 · TOTAL RD$7,450, SIN impuestos.
///
/// Verifica que factura y cotización usen la misma lógica financiera
/// (misma plantilla y mismos importes) y que con impuestos OFF no aparezca
/// terminología fiscal en el PDF.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('Caso real 8,050 → 7,450 (impuestos OFF)', () {
    test('factura deriva descuentos reales y no prorratea', () {
      final data = buildSalePdfViewData(_sale8050a7450());

      expect(data.subtotal, 8050);
      expect(data.productDiscount, 400);
      expect(data.generalDiscount, 200);
      expect(data.total, 7450);
      expect(data.fiscalEnabled, isFalse);
      expect(data.productDiscount + data.generalDiscount, 600);
    });

    test('cotización deriva los mismos descuentos reales', () {
      final data = buildCotizacionPdfViewData(
        cotizacion: _quote8050a7450(),
        company: _company(),
      );

      expect(data.totals.subtotal, 8050);
      expect(data.totals.productDiscount, 400);
      expect(data.totals.generalDiscount, 200);
      expect(data.totals.total, 7450);
      expect(data.totals.fiscalEnabled, isFalse);
      expect(data.totals.productDiscount + data.totals.generalDiscount, 600);
    });

    test('factura y cotización producen los mismos importes comerciales', () {
      final invoice = buildSalePdfViewData(_sale8050a7450());
      final quote = buildCotizacionPdfViewData(
        cotizacion: _quote8050a7450(),
        company: _company(),
      );

      expect(invoice.subtotal, quote.totals.subtotal);
      expect(invoice.productDiscount, quote.totals.productDiscount);
      expect(invoice.generalDiscount, quote.totals.generalDiscount);
      expect(invoice.total, quote.totals.total);
    });

    test(
      'PDF de factura muestra el resumen real y NO terminología fiscal',
      () async {
        final bytes = await buildSaleInvoicePdf(
          sale: _sale8050a7450(),
          company: _company(),
        );
        expect(bytes.length, greaterThan(1000));

        final text = _compactPdfText(_pdfText(bytes));
        expect(text, contains('Subtotal'));
        expect(text, contains('Descuentos por productos'));
        expect(text, contains('Descuento general'));
        expect(text, contains('RD\$8,050.00'));
        expect(text, contains('RD\$400.00'));
        expect(text, contains('RD\$200.00'));
        expect(text, contains('RD\$7,450.00'));
        expect(text, isNot(contains('ITBIS')));
        expect(text, isNot(contains('Base imponible')));
        expect(text, isNot(contains('Monto exento')));
        expect(text, isNot(contains('Sin impuesto')));
        expect(text, isNot(contains('Condición')));
        expect(text, isNot(contains('NCF')));
      },
    );

    test(
      'PDF de cotización muestra el resumen real y NO terminología fiscal',
      () async {
        final bytes = await buildCotizacionPdf(
          cotizacion: _quote8050a7450(),
          company: _company(),
        );
        expect(bytes.length, greaterThan(1000));

        final text = _compactPdfText(_pdfText(bytes));
        expect(text, contains('Subtotal'));
        expect(text, contains('Descuentos por productos'));
        expect(text, contains('Descuento general'));
        expect(text, contains('RD\$8,050.00'));
        expect(text, contains('RD\$400.00'));
        expect(text, contains('RD\$200.00'));
        expect(text, contains('RD\$7,450.00'));
        expect(text, isNot(contains('ITBIS')));
        expect(text, isNot(contains('Base imponible')));
        expect(text, isNot(contains('Monto exento')));
        expect(text, isNot(contains('Sin impuesto')));
        expect(text, isNot(contains('Condición')));
      },
    );
  });

  group('Descuentos (impuestos OFF)', () {
    test('sin descuento: no se muestran filas de descuento', () {
      final data = buildSalePdfViewData(_saleNoDiscount());
      expect(data.productDiscount, 0);
      expect(data.generalDiscount, 0);
      expect(data.subtotal, 1500);
      expect(data.total, 1500);
    });

    test('descuento de línea se representa exacto', () {
      final data = buildSalePdfViewData(_saleLineDiscount());
      expect(data.productDiscount, 200);
      expect(data.generalDiscount, 0);
      expect(data.total, 800);
    });

    test('descuento general se representa exacto', () {
      final data = buildSalePdfViewData(_saleGeneralDiscount());
      expect(data.productDiscount, 0);
      expect(data.generalDiscount, 200);
      expect(data.total, 800);
    });

    test('cantidad > 1 no multiplica el descuento de línea dos veces', () {
      final data = buildSalePdfViewData(_saleQty4());
      // Descuento REAL de línea total (4 × 50) y sin descuento general.
      expect(data.productDiscount, 200);
      expect(data.generalDiscount, 0);
      expect(data.total, 5800);
    });
  });

  group('Impuestos ON', () {
    test('factura fiscal conserva ITBIS, base imponible y NCF', () async {
      final data = buildSalePdfViewData(_fiscalSale());
      expect(data.fiscalEnabled, isTrue);
      expect(data.taxableBase, greaterThan(0));
      expect(data.taxAmount, greaterThan(0));

      final bytes = await buildSaleInvoicePdf(
        sale: _fiscalSale(),
        company: _company(),
      );
      expect(bytes.length, greaterThan(1000));
      final text = _compactPdfText(_pdfText(bytes));
      expect(text, contains('ITBIS'));
      expect(text, contains('Base imponible'));
      expect(text, contains('NCF'));
    });

    test('cotización fiscal conserva ITBIS y condición', () async {
      final bytes = await buildCotizacionPdf(
        cotizacion: _fiscalQuote(),
        company: _company(),
      );
      expect(bytes.length, greaterThan(1000));
      final text = _compactPdfText(_pdfText(bytes));
      expect(text, contains('ITBIS'));
      expect(text, contains('Condición'));
    });
  });
}

String _pdfText(List<int> bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    return PdfTextExtractor(document).extractText();
  } finally {
    document.dispose();
  }
}

String _compactPdfText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

CompanySettings _company() {
  return CompanySettings.empty().copyWith(
    companyName: 'FULLTECH, SRL',
    rnc: '133080206',
    address: 'Santo Domingo, República Dominicana',
    phone: '809-000-0000',
  );
}

/// Subtotal 8,050 · Descuento por productos 400 · Descuento general 200 ·
/// Total 7,450. Los items ya traen el bruto original (grossAmount) y el
/// descuento REAL de línea que el backend guarda tras la corrección.
SaleModel _sale8050a7450() {
  return SaleModel(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    userId: 'user-a',
    userName: 'Yunior Lopez',
    customerId: 'client-a',
    customerName: 'Fune, srl',
    customerPhone: '809-111-1111',
    saleDate: DateTime(2026, 8, 22, 10, 30),
    note: '',
    totalSold: 7450,
    totalCost: 0,
    totalProfit: 7450,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 7450,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    discountAmount: 600,
    items: [
      _saleItem(
        id: 'item-1',
        name: 'Producto A',
        gross: 3000,
        net: 2800,
        lineDiscount: 200,
        lineTotal: 2700,
      ),
      _saleItem(
        id: 'item-2',
        name: 'Producto B',
        gross: 3000,
        net: 2800,
        lineDiscount: 200,
        lineTotal: 2700,
      ),
      _saleItem(
        id: 'item-3',
        name: 'Producto C',
        gross: 1000,
        net: 1000,
        lineDiscount: 0,
        lineTotal: 1000,
      ),
      _saleItem(
        id: 'item-4',
        name: 'Producto D',
        gross: 1050,
        net: 1050,
        lineDiscount: 0,
        lineTotal: 1050,
      ),
    ],
  );
}

SaleItemModel _saleItem({
  required String id,
  required String name,
  required double gross,
  required double net,
  required double lineDiscount,
  required double lineTotal,
}) {
  return SaleItemModel(
    id: id,
    productId: 'product-$id',
    productNameSnapshot: name,
    productImageSnapshot: null,
    qty: 1,
    priceSoldUnit: net,
    costUnitSnapshot: 0,
    subtotalSold: lineTotal,
    subtotalCost: 0,
    profit: lineTotal,
    category: null,
    grossAmount: gross,
    lineDiscountAmount: lineDiscount,
  );
}

CotizacionModel _quote8050a7450() {
  return CotizacionModel(
    id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    createdAt: DateTime(2026, 8, 22, 10, 30),
    customerId: 'client-a',
    customerName: 'Fune, srl',
    customerPhone: '809-111-1111',
    note: '',
    includeItbis: false,
    itbisRate: 0,
    globalDiscountAmount: 200,
    fiscalTaxEnabled: false,
    fiscalPriceMode: 'NO_TAX',
    taxableBase: 0,
    taxAmount: 0,
    exemptAmount: 0,
    totalSnapshot: 7450,
    items: [
      _quoteItem(name: 'Producto A', original: 3000, net: 2800),
      _quoteItem(name: 'Producto B', original: 3000, net: 2800),
      _quoteItem(name: 'Producto C', original: 1000, net: 1000),
      _quoteItem(name: 'Producto D', original: 1050, net: 1050),
    ],
  );
}

CotizacionItem _quoteItem({
  required String name,
  required double original,
  required double net,
}) {
  return CotizacionItem(
    productId: 'product-$name',
    nombre: name,
    imageUrl: null,
    originalUnitPrice: original,
    unitPrice: net,
    qty: 1,
  );
}

SaleModel _saleNoDiscount() {
  return _saleWith(
    discountAmount: 0,
    totalSold: 1500,
    items: [
      _saleItem(
        id: 'n-1',
        name: 'Producto A',
        gross: 1000,
        net: 1000,
        lineDiscount: 0,
        lineTotal: 1000,
      ),
      _saleItem(
        id: 'n-2',
        name: 'Producto B',
        gross: 500,
        net: 500,
        lineDiscount: 0,
        lineTotal: 500,
      ),
    ],
  );
}

SaleModel _saleLineDiscount() {
  return _saleWith(
    discountAmount: 200,
    totalSold: 800,
    items: [
      _saleItem(
        id: 'l-1',
        name: 'Producto A',
        gross: 1000,
        net: 800,
        lineDiscount: 200,
        lineTotal: 800,
      ),
    ],
  );
}

SaleModel _saleGeneralDiscount() {
  return _saleWith(
    discountAmount: 200,
    totalSold: 800,
    items: [
      _saleItem(
        id: 'g-1',
        name: 'Producto A',
        gross: 1000,
        net: 1000,
        lineDiscount: 0,
        lineTotal: 800,
      ),
    ],
  );
}

SaleModel _saleQty4() {
  return _saleWith(
    discountAmount: 200,
    totalSold: 5800,
    items: [
      SaleItemModel(
        id: 'q-1',
        productId: 'product-q-1',
        productNameSnapshot: 'Producto A',
        productImageSnapshot: null,
        qty: 4,
        priceSoldUnit: 1450,
        costUnitSnapshot: 0,
        subtotalSold: 5800,
        subtotalCost: 0,
        profit: 5800,
        category: null,
        grossAmount: 6000,
        lineDiscountAmount: 200,
      ),
    ],
  );
}

SaleModel _saleWith({
  required double discountAmount,
  required double totalSold,
  required List<SaleItemModel> items,
}) {
  return SaleModel(
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    userId: 'user-a',
    userName: 'Yunior Lopez',
    customerId: null,
    customerName: 'Consumidor Final',
    customerPhone: null,
    saleDate: DateTime(2026, 8, 22, 11),
    note: '',
    totalSold: totalSold,
    totalCost: 0,
    totalProfit: totalSold,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: totalSold,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    discountAmount: discountAmount,
    items: items,
  );
}

SaleModel _fiscalSale() {
  return SaleModel(
    id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    userId: 'user-a',
    userName: 'Yunior Lopez',
    customerId: 'client-a',
    customerName: 'Fune, srl',
    customerPhone: '809-111-1111',
    saleDate: DateTime(2026, 8, 22, 12),
    note: '',
    totalSold: 1180,
    totalCost: 0,
    totalProfit: 1180,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 1180,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 1000,
    taxAmount: 180,
    exemptAmount: 0,
    discountAmount: 0,
    fiscalVoucherType: 'B01',
    ncf: 'B0100000001',
    ncfExpirationDate: DateTime(2026, 12, 31),
    issuerNameSnapshot: 'FULLTECH, SRL',
    issuerTaxIdSnapshot: '133080206',
    issuerAddressSnapshot: 'Higüey',
    issuerPhoneSnapshot: '8295319442',
    issuerEmailSnapshot: null,
    fiscalCustomerTaxId: '133206111',
    fiscalCustomerName: 'Fune, srl',
    customerAddressSnapshot: null,
    customerPhoneSnapshot: null,
    items: [
      SaleItemModel(
        id: 'fiscal-item',
        productId: 'fiscal-1',
        productNameSnapshot: 'Producto gravado',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 1180,
        costUnitSnapshot: 0,
        subtotalSold: 1180,
        subtotalCost: 0,
        profit: 1180,
        category: null,
        grossAmount: 1180,
        lineDiscountAmount: 0,
        taxableBase: 1000,
        taxRate: 0.18,
        taxAmount: 180,
        exemptAmount: 0,
        taxIncluded: false,
        taxExempt: false,
      ),
    ],
  );
}

CotizacionModel _fiscalQuote() {
  return CotizacionModel(
    id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    createdAt: DateTime(2026, 8, 22, 12),
    customerId: 'client-a',
    customerName: 'Fune, srl',
    customerPhone: '809-111-1111',
    note: '',
    includeItbis: true,
    itbisRate: 0.18,
    globalDiscountAmount: 0,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 1000,
    taxAmount: 180,
    exemptAmount: 0,
    totalSnapshot: 1180,
    items: [
      CotizacionItem(
        productId: 'fiscal-1',
        nombre: 'Producto gravado',
        imageUrl: null,
        originalUnitPrice: 1000,
        unitPrice: 1000,
        qty: 1,
        taxableBase: 1000,
        taxAmount: 180,
        taxIncluded: false,
        taxExempt: false,
      ),
    ],
  );
}
