import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';

/// Separación obligatoria entre DESCUENTO COMERCIAL REAL y PRORRATEO FISCAL.
///
/// El PDF debe mostrar únicamente el descuento comercial real por línea.
/// El prorrateo del descuento general (194.31 / 5.69) jamás debe aparecer
/// como descuento de producto si el usuario no descontó esa línea.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('TEST 1 — SOLO DESCUENTO GENERAL (caso real 4220 − 200 = 4020)', () {
    test('view data: descuento línea 0 y general 200', () {
      final data = buildSalePdfViewData(_saleGeneralOnly());

      expect(data.subtotal, 4220);
      expect(data.productDiscount, 0);
      expect(data.generalDiscount, 200);
      expect(data.total, 4020);
      expect(data.fiscalEnabled, isFalse);
    });

    test('PDF NO contiene el prorrateo (194.31 / 5.69)', () async {
      final bytes = await buildSaleInvoicePdf(
        sale: _saleGeneralOnly(),
        company: _company(),
      );
      expect(bytes.length, greaterThan(1000));

      final text = _compactPdfText(_pdfText(bytes));
      expect(text, isNot(contains('194.31')));
      expect(text, isNot(contains('5.69')));
      expect(text, isNot(contains('RD\$194.31')));
      expect(text, isNot(contains('RD\$5.69')));
      expect(text, contains('Subtotal'));
      expect(text, contains('RD\$4,220.00'));
      expect(text, contains('Descuento general'));
      expect(text, contains('RD\$200.00'));
      expect(text, contains('RD\$4,020.00'));
      // Sin terminología fiscal con impuestos OFF.
      expect(text, isNot(contains('ITBIS')));
      expect(text, isNot(contains('Base imponible')));
      expect(text, isNot(contains('Monto exento')));
    });
  });

  group('TEST 2 — SOLO DESCUENTO DE LÍNEA', () {
    test('view data: descuento línea 100 y general 0', () {
      final data = buildSalePdfViewData(_saleLineOnly());

      expect(data.subtotal, 1000);
      expect(data.productDiscount, 100);
      expect(data.generalDiscount, 0);
      expect(data.total, 900);
    });
  });

  group('TEST 3 — MIXTO (línea 100 + general 200)', () {
    test('view data: ambos descuentos separados', () {
      final data = buildSalePdfViewData(_saleMixed());

      expect(data.subtotal, 5000);
      expect(data.productDiscount, 100);
      expect(data.generalDiscount, 200);
      expect(data.total, 4700);
      expect(data.productDiscount + data.generalDiscount, 300);
    });

    test('PDF muestra los dos conceptos por separado', () async {
      final bytes = await buildSaleInvoicePdf(
        sale: _saleMixed(),
        company: _company(),
      );
      expect(bytes.length, greaterThan(1000));

      final text = _compactPdfText(_pdfText(bytes));
      expect(text, contains('Descuentos por productos'));
      expect(text, contains('Descuento general'));
      expect(text, contains('RD\$100.00'));
      expect(text, contains('RD\$200.00'));
      expect(text, contains('RD\$5,000.00'));
      expect(text, contains('RD\$4,700.00'));
    });
  });

  group('TEST 4 — VARIAS LÍNEAS + GENERAL (sin distribuir visualmente)', () {
    test('view data: el general no se reparte en las líneas', () {
      final data = buildSalePdfViewData(_saleThreeLinesGeneral());

      expect(data.subtotal, 3000);
      expect(data.productDiscount, 0);
      expect(data.generalDiscount, 300);
      expect(data.total, 2700);
    });
  });

  group('TEST 5 — IMPUESTOS OFF: columna Descuento solo comercial', () {
    test('view data fiscal OFF con descuento comercial de línea', () {
      final data = buildSalePdfViewData(_saleOffWithLineDiscount());

      expect(data.fiscalEnabled, isFalse);
      expect(data.productDiscount, 100);
      expect(data.generalDiscount, 0);
      expect(data.total, 900);
    });
  });

  group(
    'TEST 6 — IMPUESTOS ON: columna Descuento solo comercial + fiscal OK',
    () {
      test('view data fiscal ON conserva base/ITBIS y descuento comercial', () {
        final data = buildSalePdfViewData(_saleOnWithLineDiscount());

        expect(data.fiscalEnabled, isTrue);
        expect(data.productDiscount, 100);
        expect(data.generalDiscount, 0);
        expect(data.taxableBase, 900);
        expect(data.taxAmount, 162);
        expect(data.total, 1062);
      });

      test(
        'PDF fiscal muestra descuento comercial y mantiene ITBIS/base',
        () async {
          final bytes = await buildSaleInvoicePdf(
            sale: _saleOnWithLineDiscount(),
            company: _company(),
          );
          expect(bytes.length, greaterThan(1000));

          final text = _compactPdfText(_pdfText(bytes));
          expect(text, contains('ITBIS'));
          expect(text, contains('Base imponible'));
          expect(text, contains('Descuento'));
        },
      );
    },
  );

  group('TEST 7 — PRORRATEO INTERNO NUNCA LLEGA AL PDF', () {
    test('aunque el backend prorratee, el PDF usa solo comercial', () async {
      // Venta con SOLO descuento general de 200: el backend internamente
      // prorratea (194.31 + 5.69) para fines fiscales, pero el PDF no debe
      // mostrar esos valores como descuentos de línea.
      final bytes = await buildSaleInvoicePdf(
        sale: _saleGeneralOnly(),
        company: _company(),
      );
      final text = _compactPdfText(_pdfText(bytes));
      expect(text, isNot(contains('194.31')));
      expect(text, isNot(contains('5.69')));
      expect(text, contains('Descuento general'));
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

/// DVR 4,100 + Balum 120 = 4,220 · Descuento general 200 → Total 4,020.
/// Sin descuentos de línea. (Caso real del cliente.)
SaleModel _saleGeneralOnly() {
  return _sale(
    totalSold: 4020,
    discountAmount: 200,
    items: [
      _item(
        id: 'dvr',
        name: 'DVR 8 canales',
        qty: 1,
        net: 4100,
        original: 4100,
        lineDiscount: 0,
      ),
      _item(
        id: 'balum',
        name: 'video Balum',
        qty: 1,
        net: 120,
        original: 120,
        lineDiscount: 0,
      ),
    ],
  );
}

/// Producto A 1,000 → precio 900 (descuento línea 100). Sin general.
SaleModel _saleLineOnly() {
  return _sale(
    totalSold: 900,
    discountAmount: 100,
    items: [
      _item(
        id: 'a',
        name: 'Producto A',
        qty: 1,
        net: 900,
        original: 1000,
        lineDiscount: 100,
      ),
    ],
  );
}

/// A: línea -100 (original 1000, neto 900). B: sin descuento (4000).
/// General 200. Subtotal bruto 5000 → Total 4700.
SaleModel _saleMixed() {
  return _sale(
    totalSold: 4700,
    discountAmount: 300,
    items: [
      _item(
        id: 'a',
        name: 'Producto A',
        qty: 1,
        net: 900,
        original: 1000,
        lineDiscount: 100,
      ),
      _item(
        id: 'b',
        name: 'Producto B',
        qty: 1,
        net: 4000,
        original: 4000,
        lineDiscount: 0,
      ),
    ],
  );
}

/// Tres líneas de 1000 c/u, sin descuentos de línea, general 300 → 2700.
SaleModel _saleThreeLinesGeneral() {
  return _sale(
    totalSold: 2700,
    discountAmount: 300,
    items: [
      for (var i = 0; i < 3; i++)
        _item(
          id: 'p$i',
          name: 'Producto $i',
          qty: 1,
          net: 1000,
          original: 1000,
          lineDiscount: 0,
        ),
    ],
  );
}

/// Impuestos OFF con un descuento comercial de línea (no fiscal).
SaleModel _saleOffWithLineDiscount() {
  return _sale(
    totalSold: 900,
    discountAmount: 100,
    items: [
      _item(
        id: 'a',
        name: 'Producto A',
        qty: 1,
        net: 900,
        original: 1000,
        lineDiscount: 100,
      ),
    ],
  );
}

/// Impuestos ON: descuento comercial de línea 100, base 900, ITBIS 162.
SaleModel _saleOnWithLineDiscount() {
  return SaleModel(
    id: 'fiscal-line-disc',
    userId: 'user-a',
    userName: 'Yunior Lopez',
    customerId: 'client-a',
    customerName: 'Fune, srl',
    customerPhone: '809-111-1111',
    saleDate: DateTime(2026, 8, 22, 15),
    note: '',
    totalSold: 1062,
    totalCost: 0,
    totalProfit: 1062,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 1062,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 900,
    taxAmount: 162,
    exemptAmount: 0,
    discountAmount: 100,
    fiscalVoucherType: 'B01',
    ncf: 'B0100000099',
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
        id: 'a-fiscal',
        productId: 'a-1',
        productNameSnapshot: 'Producto A',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 900,
        costUnitSnapshot: 0,
        subtotalSold: 900,
        subtotalCost: 0,
        profit: 900,
        category: null,
        grossAmount: 1000,
        lineDiscountAmount: 100,
        taxableBase: 900,
        taxRate: 0.18,
        taxAmount: 162,
        exemptAmount: 0,
        taxIncluded: false,
        taxExempt: false,
      ),
    ],
  );
}

SaleModel _sale({
  required double totalSold,
  required double discountAmount,
  required List<SaleItemModel> items,
}) {
  return SaleModel(
    id: 'commercial-sale',
    userId: 'user-a',
    userName: 'Yunior Lopez',
    customerId: null,
    customerName: 'Consumidor Final',
    customerPhone: null,
    saleDate: DateTime(2026, 8, 22, 14),
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

SaleItemModel _item({
  required String id,
  required String name,
  required double qty,
  required double net,
  required double original,
  required double lineDiscount,
}) {
  return SaleItemModel(
    id: id,
    productId: 'product-$id',
    productNameSnapshot: name,
    productImageSnapshot: null,
    qty: qty,
    priceSoldUnit: net,
    costUnitSnapshot: 0,
    subtotalSold: net * qty,
    subtotalCost: 0,
    profit: net * qty,
    category: null,
    grossAmount: original * qty,
    lineDiscountAmount: lineDiscount,
  );
}
