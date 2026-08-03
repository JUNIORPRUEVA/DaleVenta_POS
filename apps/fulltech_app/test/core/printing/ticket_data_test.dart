import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TicketData.fromSale prints mixed payment amounts', () {
    final sale = SaleModel(
      id: 'sale-12345678',
      userId: 'user-1',
      userName: 'Caja',
      customerId: 'client-1',
      customerName: 'Cliente',
      customerPhone: '8090000000',
      saleDate: DateTime(2026, 8, 2, 10),
      note: null,
      totalSold: 1000,
      totalCost: 600,
      totalProfit: 400,
      commissionAmount: 40,
      paymentMethod: 'mixed',
      paymentCashAmount: 350,
      paymentTransferAmount: 650,
      creditAmount: 0,
      creditPaidAmount: 1000,
      creditBalance: 0,
      creditStatus: 'none',
      isDeleted: false,
      deletedAt: null,
      items: const [],
    );

    final ticket = TicketData.fromSale(sale);

    expect(
      ticket.paymentMethod,
      'Efectivo RD\$ 350.00 + Transferencia RD\$ 650.00',
    );
  });
}
