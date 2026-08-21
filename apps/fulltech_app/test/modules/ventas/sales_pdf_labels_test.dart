import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';

SaleModel _sale({String? voucherType, String? ncf}) {
  return SaleModel(
    id: '4c1db733-0000-0000-0000-000000000001',
    userId: 'user-1',
    userName: 'Yunior Lopez',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 21, 19, 38),
    note: null,
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
    fiscalTaxEnabled: false,
    fiscalPriceMode: 'NO_TAX',
    taxableBase: 0,
    taxAmount: 0,
    exemptAmount: 0,
    discountAmount: 0,
    fiscalVoucherType: voucherType,
    ncf: ncf,
    items: const [],
  );
}

void main() {
  group('invoicePdfDocumentLabel (V7)', () {
    test('B01 renders FACTURA / CRÉDITO FISCAL', () {
      expect(
        invoicePdfDocumentLabel(_sale(voucherType: 'B01', ncf: 'B0100000003')),
        'FACTURA / CRÉDITO FISCAL',
      );
    });

    test('B02 renders FACTURA / CONSUMIDOR FINAL', () {
      expect(
        invoicePdfDocumentLabel(_sale(voucherType: 'B02', ncf: 'B0200000003')),
        'FACTURA / CONSUMIDOR FINAL',
      );
    });

    test('NCF present without voucher renders CRÉDITO FISCAL', () {
      expect(
        invoicePdfDocumentLabel(_sale(ncf: 'B0100000003')),
        'FACTURA / CRÉDITO FISCAL',
      );
    });

    test('normal invoice renders FACTURA', () {
      expect(invoicePdfDocumentLabel(_sale()), 'FACTURA');
    });
  });

  group('invoicePdfPaymentMethodLabel', () {
    test('maps real methods to friendly labels', () {
      expect(invoicePdfPaymentMethodLabel('cash'), 'Efectivo');
      expect(invoicePdfPaymentMethodLabel('transfer'), 'Transferencia');
      expect(invoicePdfPaymentMethodLabel('mixed'), 'Mixto');
      expect(invoicePdfPaymentMethodLabel('credit'), 'Crédito');
      expect(invoicePdfPaymentMethodLabel('card'), 'Tarjeta');
    });

    test('falls back to Efectivo when empty', () {
      expect(invoicePdfPaymentMethodLabel(''), 'Efectivo');
    });
  });

  group('invoicePdfCode', () {
    test('builds FAC-xxxx token from the sale id', () {
      final code = invoicePdfCode('4c1db733-0000-0000-0000-000000000001');
      expect(code, 'FAC-4C1DB733');
    });
  });

  group('invoicePdfNoteText (sin pago duplicado)', () {
    test('keeps real notes unchanged', () {
      expect(
        invoicePdfNoteText('Entrega en tienda.\nIncluye instalación.'),
        'Entrega en tienda.\nIncluye instalación.',
      );
    });

    test('removes the checkout Pago: line', () {
      expect(
        invoicePdfNoteText('Pago: Efectivo\nEntrega en tienda.'),
        'Entrega en tienda.',
      );
    });

    test('removes only the Pago line leaving empty notes empty', () {
      expect(invoicePdfNoteText('Pago: Transferencia'), '');
    });

    test('handles null and blank notes', () {
      expect(invoicePdfNoteText(null), '');
      expect(invoicePdfNoteText('   '), '');
    });
  });
}
