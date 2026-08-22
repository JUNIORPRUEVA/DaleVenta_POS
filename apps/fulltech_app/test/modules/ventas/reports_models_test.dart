import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/reports/ui/reports_page.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

void main() {
  group('SaleModel.kind', () {
    test('por defecto es invoice cuando el backend no lo envía', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's1',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'invoice');
    });

    test('parsea kind=refund desde el backend', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 'r1',
        'kind': 'refund',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'refund');
    });

    test('parsea kind=invoice desde el backend', () {
      final sale = SaleModel.fromJson(<String, dynamic>{
        'id': 's2',
        'kind': 'invoice',
        'items': <dynamic>[],
      });
      expect(sale.kind, 'invoice');
    });
  });

  group('KpisData.fromReport', () {
    test('kpis vacíos producen ceros sin excepciones', () {
      final kpis = KpisData.fromReport(<String, dynamic>{});
      expect(kpis.totalSales, 0);
      expect(kpis.totalProfit, 0);
      expect(kpis.netProfit, 0);
      expect(kpis.totalCost, 0);
      expect(kpis.avgTicket, 0);
      expect(kpis.margin, 0);
    });

    test('usa netSales como total de ventas y calcula avgTicket', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': 4,
          'netSales': 1000,
          'totalProfit': 300,
          'totalCost': 700,
        },
      });
      expect(kpis.totalSales, 1000);
      expect(kpis.netProfit, 300);
      expect(kpis.margin, closeTo(30.0, 0.001));
      // avgTicket no viene del backend -> totalSold / totalSales = 1000/4
      expect(kpis.avgTicket, closeTo(250.0, 0.001));
    });

    test('respuesta con nulls no rompe el parseo', () {
      final kpis = KpisData.fromReport(<String, dynamic>{
        'kpis': <String, dynamic>{
          'totalSales': null,
          'netSales': null,
          'totalProfit': null,
          'totalCost': null,
        },
      });
      expect(kpis.totalSales, 0);
      expect(kpis.totalProfit, 0);
      expect(kpis.margin.isFinite, isTrue);
    });
  });

  group('DateRangeHelper', () {
    test('Hoy inicia a medianoche y termina a 23:59:59.999', () {
      final range = DateRangeHelper.getRangeForPeriod(DateRangePeriod.today);
      final now = DateTime.now();
      expect(range.start.year, now.year);
      expect(range.start.month, now.month);
      expect(range.start.day, now.day);
      expect(range.start.hour, 0);
      expect(range.start.minute, 0);
      expect(range.end.day, now.day);
      expect(range.end.hour, 23);
      expect(range.end.minute, 59);
    });

    test('Ayer dura exactamente un día calendario', () {
      final yesterday = DateRangeHelper.getRangeForPeriod(
        DateRangePeriod.yesterday,
      );
      final duration = yesterday.end.difference(yesterday.start);
      // 23:59:59.999 - 00:00:00.000 = 24h - 1ms
      expect(duration.inHours, 23);
      expect(duration.inMinutes, 23 * 60 + 59);
      expect(yesterday.start.isBefore(yesterday.end), isTrue);
    });

    test('rango nunca es invertido (start <= end)', () {
      for (final period in DateRangePeriod.values) {
        final range = DateRangeHelper.getRangeForPeriod(period);
        expect(
          range.start.isBefore(range.end) || range.start == range.end,
          isTrue,
          reason: 'periodo $period',
        );
      }
    });
  });
}
