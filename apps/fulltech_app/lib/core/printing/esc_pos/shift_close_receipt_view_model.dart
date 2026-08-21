import '../models/company_info.dart';

/// Resumen por categoría del cierre. Los valores [soldAmount] y
/// [profitAmount] son OFICIALES: provienen de `CashSummaryModel.categorySummary`
/// ya calculado por el backend; el renderer NUNCA recalcula ganancia.
class ShiftCloseCategorySummary {
  const ShiftCloseCategorySummary({
    required this.categoryName,
    required this.soldAmount,
    required this.profitAmount,
  });

  final String categoryName;
  final double soldAmount;
  final double profitAmount;
}

/// Movimiento manual del turno (solo presentación).
class ShiftCloseMovement {
  const ShiftCloseMovement({
    required this.label,
    required this.amount,
    required this.isIn,
    this.reason,
  });

  final String label;
  final double amount;
  final bool isIn;
  final String? reason;
}

/// ViewModel / DTO consumido por [FullPosEscPosShiftCloseRenderer].
///
/// Copia de presentación de los datos oficiales del cierre de turno
/// (turno vivo `CashCloseTicketSnapshot` o histórico `CashSessionHistoryModel`).
/// El renderer SOLO presenta: no consulta providers, no calcula ventas,
/// no calcula utilidad/ganancia ni diferencia.
///
/// `showSalesDetails` distingue un cierre vivo (con desglose de ventas,
/// categorías y contadores) de una reimpresión histórica (sin desglose).
class ShiftCloseReceiptViewModel {
  const ShiftCloseReceiptViewModel({
    required this.company,
    required this.title,
    required this.ticketNumber,
    required this.cashierName,
    required this.shiftId,
    required this.cashId,
    required this.businessDate,
    required this.openedAt,
    required this.closedAt,
    required this.capturedAt,
    required this.showSalesDetails,
    required this.openingAmount,
    required this.totalSales,
    required this.cashSales,
    required this.transferSales,
    required this.manualCashIn,
    required this.expenses,
    required this.manualCashOut,
    required this.withdrawals,
    required this.refunds,
    required this.creditSales,
    required this.creditInitialCash,
    required this.creditInitialTransfer,
    required this.creditPaymentCash,
    required this.creditPaymentTransfer,
    required this.creditBalance,
    required this.expectedCash,
    required this.countedCash,
    required this.difference,
    required this.ticketCount,
    required this.refundCount,
    required this.categorySummaries,
    this.status = '',
    this.note,
    this.movements,
  });

  final CompanyInfo company;

  /// 'CIERRE DE TURNO' o 'REIMPRESION CIERRE'.
  final String title;
  final String ticketNumber;

  /// Snapshot oficial del cajero del turno (nunca 'PENDIENTE DE SINCRONIZAR').
  final String cashierName;
  final String shiftId;

  /// ID oficial de la caja del turno, cuando existe.
  final String cashId;
  final String businessDate;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final DateTime capturedAt;

  /// `true` en un cierre vivo (desglose de ventas, categorías y contadores);
  /// `false` en una reimpresión histórica sin desglose.
  final bool showSalesDetails;

  // VENTAS Y EFECTIVO (campos de control de caja: se muestran incluso en 0).
  final double openingAmount;
  final double totalSales;
  final double cashSales;
  final double transferSales;
  final double manualCashIn;
  final double expenses;
  final double manualCashOut;
  final double withdrawals;
  final double refunds;

  // CRÉDITO (solo si hay ventas a crédito).
  final double creditSales;
  final double creditInitialCash;
  final double creditInitialTransfer;
  final double creditPaymentCash;
  final double creditPaymentTransfer;
  final double creditBalance;

  // CUADRE FINAL.
  final double expectedCash;
  final double countedCash;
  final double difference;

  // CONTADORES.
  final int ticketCount;
  final int refundCount;

  /// Resumen por categoría ya calculado (fuente oficial).
  final List<ShiftCloseCategorySummary> categorySummaries;
  final String status;
  final String? note;
  final List<ShiftCloseMovement>? movements;
}
