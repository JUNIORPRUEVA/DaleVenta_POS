import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/time/business_time.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('Business time America/Santo_Domingo', () {
    test('UTC -> RD display para 00:01 RD', () {
      final instant = parseServerInstant('2026-09-16T04:01:00.000Z')!;

      expect(formatBusinessDateTime(instant), '16/09/2026 00:01');
      expect(businessDateKey(instant), '2026-09-16');
    });

    test('frontera 23:59 RD pertenece al dia 15 aunque sea UTC 16', () {
      final instant = parseServerInstant('2026-09-16T03:59:00.000Z')!;

      expect(formatBusinessDateTime(instant), '15/09/2026 23:59');
      expect(businessDateKey(instant), '2026-09-15');
    });

    test('ISO con offset explicito -04:00 no se convierte doble', () {
      final instant = parseServerInstant('2026-09-16T04:01:00.000-04:00')!;

      expect(formatBusinessDateTime(instant), '16/09/2026 04:01');
      expect(instant.toUtc(), DateTime.utc(2026, 9, 16, 8, 1));
    });

    test('sale list/detail model parsea saleDate con zona de negocio', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 'sale-1',
        'userId': 'user-1',
        'saleDate': '2026-09-16T04:01:00.000Z',
        'paymentMethod': 'cash',
      });

      expect(formatBusinessDateTime(sale.saleDate!), '16/09/2026 00:01');
    });

    test('ticket thermal/PDF usa la misma fecha de negocio de Sale', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 'sale-1',
        'userId': 'user-1',
        'saleDate': '2026-09-16T04:01:00.000Z',
        'paymentMethod': 'cash',
      });
      final ticket = TicketData.fromSale(sale);

      expect(formatBusinessDateTime(ticket.dateTime), '16/09/2026 00:01');
    });

    test('cash timestamps se parsean como instantes y muestran RD', () {
      final session = ActiveCashSession.fromJson(<String, dynamic>{
        'userId': 'user-1',
        'shiftId': 'shift-1',
        'openedAt': '2026-09-16T03:59:00.000Z',
        'status': 'OPEN',
        'userName': 'Caja',
        'businessDate': '2026-09-15',
      });

      expect(formatBusinessDateTime(session.openedAt), '15/09/2026 23:59');
      expect(session.businessDate, '2026-09-15');
    });
  });
}
