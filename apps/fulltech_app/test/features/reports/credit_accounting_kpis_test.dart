import 'package:daleventa_pos/features/reports/ui/reports_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credit return reports net cost matching net sales and gross profit', () {
    final kpis = KpisData.fromReport({'kpis': {
      'netSales': 2000, 'totalSales': 1, 'totalCost': 1000,
      'netCost': 800, 'totalProfit': 1500, 'grossProfit': 1200,
      'netProfit': 1200, 'totalExpenses': 0,
    }});
    expect(kpis.totalSales,2000);
    expect(kpis.totalCost,800);
    expect(kpis.grossProfit,1200);
    expect(kpis.netProfit,1200);
    expect(kpis.totalSales - kpis.totalCost,kpis.grossProfit);
  });
  test('old server payload retains its existing cost and profit mapping', () {
    final kpis = KpisData.fromReport({'kpis': {'totalSold': 2500,'totalCost':1000,'totalProfit':1500,'netProfit':1450,'totalExpenses':50}});
    expect(kpis.totalCost,1000);
    expect(kpis.grossProfit,1500);
    expect(kpis.netProfit,1450);
  });
}
