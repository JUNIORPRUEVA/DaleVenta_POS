import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

SaleModel _sale({
  String? userName = 'Yunior Lopez',
  String? ncf = 'B0100000003',
  DateTime? ncfExpirationDate,
  String? fiscalVoucherType = 'B01',
  String? fiscalCustomerTaxId = '133206111',
  String? fiscalCustomerName = 'Fune, srl',
  double taxAmount = 3920.34,
  double taxableBase = 21779.66,
  double total = 25700,
}) {
  return SaleModel(
    id: 'sale-1',
    userId: 'user-1',
    userName: userName,
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 20, 19, 29),
    note: null,
    totalSold: total,
    totalCost: 0,
    totalProfit: total,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: total,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: taxableBase,
    taxAmount: taxAmount,
    exemptAmount: 0,
    discountAmount: 0,
    fiscalVoucherType: fiscalVoucherType,
    ncf: ncf,
    ncfExpirationDate: ncfExpirationDate,
    issuerNameSnapshot: 'FULLTECH, SRL',
    issuerTaxIdSnapshot: '133080206',
    issuerAddressSnapshot: 'Higuey',
    issuerPhoneSnapshot: '809-000-0000',
    issuerEmailSnapshot: null,
    fiscalCustomerTaxId: fiscalCustomerTaxId,
    fiscalCustomerName: fiscalCustomerName,
    customerAddressSnapshot: null,
    customerPhoneSnapshot: null,
    items: const [],
  );
}

void main() {
  group('NCF expiration + cashier across print routes', () {
    test('SaleModel.fromJson parses user.nombreCompleto and ncfExpirationDate', () {
      final sale = SaleModel.fromJson({
        'id': 'sale-1',
        'userId': 'user-1',
        'totalSold': 25700,
        'totalCost': 0,
        'totalProfit': 25700,
        'commissionAmount': 0,
        'paymentMethod': 'cash',
        'paymentCashAmount': 25700,
        'paymentTransferAmount': 0,
        'creditAmount': 0,
        'creditPaidAmount': 0,
        'creditBalance': 0,
        'creditStatus': 'none',
        'isDeleted': false,
        'fiscalTaxEnabled': true,
        'fiscalPriceMode': 'TAX_ADDED',
        'taxableBase': 21779.66,
        'taxAmount': 3920.34,
        'exemptAmount': 0,
        'discountAmount': 0,
        'fiscalVoucherType': 'B01',
        'ncf': 'B0100000003',
        'ncfExpirationDate': '2026-12-31T00:00:00.000Z',
        'fiscalCustomerTaxId': '133206111',
        'fiscalCustomerName': 'Fune, srl',
        'user': {
          'id': 'user-1',
          'nombreCompleto': 'Yunior Lopez',
          'email': 'yunior@test.do',
        },
        'items': <dynamic>[],
      });

      expect(sale.userName, 'Yunior Lopez');
      expect(sale.ncf, 'B0100000003');
      expect(sale.ncfExpirationDate, DateTime.utc(2026, 12, 31));
    });

    test('immediate and reprint produce the SAME fiscal/identity data', () {
      final sale = _sale(ncfExpirationDate: DateTime(2026, 12, 31));
      final immediate = TicketData.fromSale(sale);
      final reprint = TicketData.fromSale(sale, isCopy: true);

      expect(immediate.cashierName, 'Yunior Lopez');
      expect(reprint.cashierName, 'Yunior Lopez');
      expect(immediate.cashierName, reprint.cashierName);

      expect(immediate.ncf, 'B0100000003');
      expect(reprint.ncf, 'B0100000003');
      expect(immediate.ncf, reprint.ncf);

      expect(immediate.ncfExpirationDate, DateTime(2026, 12, 31));
      expect(reprint.ncfExpirationDate, DateTime(2026, 12, 31));
      expect(immediate.ncfExpirationDate, reprint.ncfExpirationDate);

      expect(immediate.client?.document, '133206111');
      expect(reprint.client?.document, '133206111');
      expect(immediate.client?.name, 'Fune, srl');

      expect(immediate.itbis, 3920.34);
      expect(reprint.itbis, 3920.34);
      expect(immediate.total, reprint.total);
    });

    test('without persisted cashier the fallback is No disponible (not wrong user)', () {
      final sale = _sale(userName: null);
      final ticket = TicketData.fromSale(sale);
      expect(ticket.cashierName, 'No disponible');
    });

    test('reprint keeps the historical NCF expiration snapshot', () {
      // La venta histórica conserva su propio vencimiento (snapshot).
      final sale = _sale(ncfExpirationDate: DateTime(2026, 12, 31));
      final reprint = TicketData.fromSale(sale, isCopy: true);

      expect(reprint.ncfExpirationDate, DateTime(2026, 12, 31));
      // No importa la secuencia/config actual: el dato sale del snapshot.
      expect(reprint.ncfExpirationDate, sale.ncfExpirationDate);
    });
  });
}
