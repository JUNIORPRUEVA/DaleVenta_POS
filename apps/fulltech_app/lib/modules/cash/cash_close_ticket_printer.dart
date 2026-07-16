import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/printing/models/receipt_text_utils.dart';
import '../../core/printing/unified_ticket_printer.dart';
import 'cash_models.dart';

final cashCloseTicketPrinterProvider = Provider<CashCloseTicketPrinter>((ref) {
  return CashCloseTicketPrinter(ref);
});

class CashCloseTicketSnapshot {
  const CashCloseTicketSnapshot({
    required this.state,
    required this.summary,
    required this.movements,
    required this.closingAmount,
    this.note,
    required this.capturedAt,
  });

  final CashGateState state;
  final CashSummaryModel summary;
  final List<CashMovementModel> movements;
  final double closingAmount;
  final String? note;
  final DateTime capturedAt;

  ActiveCashSession? get active => state.activeSession;
  double get difference => summary.difference(closingAmount);
}

class CashCloseTicketPrinter {
  CashCloseTicketPrinter(this._ref);

  final Ref _ref;

  Future<PrintTicketResult> printCloseTicket(CashCloseTicketSnapshot snapshot) {
    return _ref
        .read(unifiedTicketPrinterProvider)
        .printCustomLines(
          lines: buildLines(snapshot),
          ticketNumber: _ticketNumber(snapshot),
        );
  }

  List<String> buildLines(CashCloseTicketSnapshot snapshot) {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final active = snapshot.active;
    const width = 32;
    final note = (snapshot.note ?? '').trim();
    final movements = snapshot.movements.take(8).toList(growable: false);

    return [
      ReceiptTextUtils.center('CORTE DE TURNO', width),
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.leftRight(
        'Fecha',
        date.format(snapshot.capturedAt.toLocal()),
        width,
      ),
      if (snapshot.state.businessDate.trim().isNotEmpty)
        ReceiptTextUtils.leftRight(
          'Dia negocio',
          snapshot.state.businessDate,
          width,
        ),
      if (active != null) ...[
        ReceiptTextUtils.leftRight('Cajero', active.userName, width),
        ReceiptTextUtils.leftRight(
          'Apertura',
          date.format(active.openedAt.toLocal()),
          width,
        ),
      ],
      ReceiptTextUtils.separator(width, 'dashed'),
      ReceiptTextUtils.leftRight(
        'Base inicial',
        money.format(snapshot.summary.openingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Total vendido',
        money.format(snapshot.summary.totalSales),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Ventas efectivo',
        money.format(snapshot.summary.salesCashTotal),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Transferencias',
        money.format(snapshot.summary.salesTransferTotal),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Entradas',
        money.format(snapshot.summary.cashInManual),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Gastos',
        money.format(snapshot.summary.totalExpenses),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Salidas',
        money.format(snapshot.summary.cashOutManual),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Retiros',
        money.format(snapshot.summary.totalWithdrawals),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Devoluciones',
        money.format(snapshot.summary.refundsCash),
        width,
      ),
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.leftRight(
        'Efectivo esperado',
        money.format(snapshot.summary.expectedCash),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Efectivo contado',
        money.format(snapshot.closingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Diferencia',
        money.format(snapshot.difference),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Tickets',
        snapshot.summary.totalTickets.toString(),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Devoluciones',
        snapshot.summary.totalRefunds.toString(),
        width,
      ),
      if (note.isNotEmpty) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        'Nota:',
        ...ReceiptTextUtils.wrap(note, width),
      ],
      if (movements.isNotEmpty) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        'MOVIMIENTOS',
        for (final movement in movements) ...[
          ReceiptTextUtils.leftRight(
            _movementLabel(movement),
            '${movement.isIn ? '+' : '-'}${money.format(movement.amount)}',
            width,
          ),
          if (movement.reason.trim().isNotEmpty)
            ...ReceiptTextUtils.wrap('  ${movement.reason}', width),
        ],
      ],
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.center('FIRMA CAJERO', width),
      '',
      '____________________________',
    ];
  }

  String _ticketNumber(CashCloseTicketSnapshot snapshot) {
    final date = snapshot.state.businessDate.trim().isNotEmpty
        ? snapshot.state.businessDate.trim().replaceAll(RegExp(r'[^0-9]'), '')
        : DateFormat('yyyyMMdd').format(snapshot.capturedAt);
    final suffix = snapshot.active?.shiftId.replaceAll('-', '');
    final suffixEnd = suffix == null
        ? 0
        : (suffix.length < 6 ? suffix.length : 6);
    final compactSuffix = suffix == null || suffix.isEmpty
        ? DateFormat('HHmmss').format(snapshot.capturedAt)
        : suffix.substring(0, suffixEnd);
    return 'CIERRE-$date-$compactSuffix';
  }

  String _movementLabel(CashMovementModel movement) {
    return switch (movement.movementType) {
      'expense' => 'Gasto',
      'owner_draw' => 'Retiro',
      'transfer' => movement.isIn ? 'Entrada' : 'Transfer.',
      _ => movement.isIn ? 'Entrada' : 'Salida',
    };
  }
}
