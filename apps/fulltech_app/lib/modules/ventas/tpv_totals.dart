import 'sales_models.dart';

/// Totales que debe mostrar el encabezado del historial TPV.
///
/// Motivo (defecto confirmado): la lista de facturas esta PAGINADA
/// (`_invoicePageSize = 50`), pero el encabezado sumaba con `.fold()` las filas
/// cargadas, de modo que a partir de la segunda pagina mostraba un monto y un
/// conteo MENORES que los reales del periodo.
///
/// La fuente autoritativa es el agregado del backend (`/sales/summary`), que
/// se aplica al mismo rango de fechas que la pantalla. Si ese agregado no esta
/// disponible (fallo de red), se conserva el calculo local pero se marca
/// `authoritative: false` para que la UI lo rotule como "cargadas" en lugar de
/// presentarlo como total del periodo.
typedef TpvHeaderTotals = ({int count, double sold, bool authoritative});

TpvHeaderTotals tpvHeaderTotals({
  required SalesSummaryModel? periodSummary,
  required int loadedCount,
  required double loadedSold,
}) {
  final summary = periodSummary;
  if (summary == null) {
    return (count: loadedCount, sold: loadedSold, authoritative: false);
  }
  return (
    count: summary.totalSales,
    sold: summary.totalSold,
    authoritative: true,
  );
}

/// Subtitulo del dialogo "Resumen de ventas".
///
/// Declara SIEMPRE de donde salen los numeros: los totales del periodo son el
/// agregado del servidor y los contadores derivados de la lista corresponden
/// solo a las facturas cargadas (la lista esta paginada).
String tpvSummaryScopeLabel({
  required bool authoritative,
  required int loadedCount,
}) {
  if (authoritative) {
    return 'Totales del período (servidor). Activas, devueltas y clientes: '
        'sobre $loadedCount facturas cargadas.';
  }
  return 'Solo las $loadedCount facturas cargadas. El agregado del período no '
      'está disponible.';
}
