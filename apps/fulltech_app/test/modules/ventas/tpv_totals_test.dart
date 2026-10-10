import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/tpv_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión del defecto financiero de TPV: la lista está paginada (50 por
/// página) y el encabezado sumaba `.fold()` sobre las filas cargadas, así que
/// con más de una página mostraba menos facturas y menos dinero que el periodo.
void main() {
  const summary = SalesSummaryModel(
    totalSales: 500,
    totalSold: 99999.5,
    totalCost: 40000,
    totalProfit: 30000,
    totalCommission: 1500,
  );

  test('con agregado del backend el encabezado usa el total del PERIODO', () {
    final totals = tpvHeaderTotals(
      periodSummary: summary,
      loadedCount: 50,
      loadedSold: 1200,
    );

    expect(totals.count, 500);
    expect(totals.sold, 99999.5);
    expect(totals.authoritative, isTrue);
  });

  test('el total no cambia al cargar más páginas (50 / 500 / >1000)', () {
    final page1 = tpvHeaderTotals(
      periodSummary: summary,
      loadedCount: 50,
      loadedSold: 1200,
    );
    final page10 = tpvHeaderTotals(
      periodSummary: summary,
      loadedCount: 500,
      loadedSold: 99999.5,
    );
    final manyPages = tpvHeaderTotals(
      periodSummary: summary,
      loadedCount: 1200,
      loadedSold: 99999.5,
    );

    expect(page10.count, page1.count);
    expect(page10.sold, page1.sold);
    expect(manyPages.count, page1.count);
    expect(manyPages.sold, page1.sold);
  });

  test('sin agregado del backend el valor local se marca NO autoritativo', () {
    final totals = tpvHeaderTotals(
      periodSummary: null,
      loadedCount: 50,
      loadedSold: 1200,
    );

    expect(totals.count, 50);
    expect(totals.sold, 1200);
    expect(
      totals.authoritative,
      isFalse,
      reason: 'la UI debe rotularlo como "cargadas", nunca como total',
    );
  });

  test('sin agregado y sin filas no inventa montos', () {
    final totals = tpvHeaderTotals(
      periodSummary: null,
      loadedCount: 0,
      loadedSold: 0,
    );

    expect(totals.count, 0);
    expect(totals.sold, 0);
    expect(totals.authoritative, isFalse);
  });

  test('un periodo sin ventas del backend devuelve ceros autoritativos', () {
    final totals = tpvHeaderTotals(
      periodSummary: SalesSummaryModel.empty(),
      loadedCount: 0,
      loadedSold: 0,
    );

    expect(totals.count, 0);
    expect(totals.sold, 0);
    expect(totals.authoritative, isTrue);
  });
}
