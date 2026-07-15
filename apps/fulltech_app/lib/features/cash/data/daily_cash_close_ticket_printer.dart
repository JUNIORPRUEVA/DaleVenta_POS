import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/unified_ticket_printer.dart';
import '../../../modules/cash/cash_repository.dart';

final dailyCashCloseTicketPrinterProvider =
    Provider<DailyCashCloseTicketPrinter>((ref) {
      return DailyCashCloseTicketPrinter(ref);
    });

class DailyCashCloseTicketPrinter {
  DailyCashCloseTicketPrinter(this._ref);

  final Ref _ref;

  Future<PrintTicketResult> printDailyCloseTicket({
    String? note,
    double? closingAmount,
  }) async {
    final repo = _ref.read(cashRepositoryProvider);
    final state = await repo.state();
    final summary = await repo.summary();
    final movements = await repo.movements();
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final active = state.activeSession;
    final finalCash = closingAmount ?? summary.expectedCash;
    final diff = summary.difference(finalCash);

    final lines = <String>[
      'CORTE DE TURNO',
      'Fecha negocio: ${state.businessDate}',
      if (active != null) 'Cajero: ${active.userName}',
      if (active != null) 'Apertura: ${date.format(active.openedAt)}',
      '-' * 32,
      'Fondo inicial: ${money.format(summary.openingAmount)}',
      'Total vendido: ${money.format(summary.totalSales)}',
      'Efectivo ventas: ${money.format(summary.salesCashTotal)}',
      'Transferencias: ${money.format(summary.salesTransferTotal)}',
      'Entradas manuales: ${money.format(summary.cashInManual)}',
      'Salidas manuales: ${money.format(summary.cashOutManual)}',
      'Gastos: ${money.format(summary.totalExpenses)}',
      'Retiros: ${money.format(summary.totalWithdrawals)}',
      'Devoluciones: ${money.format(summary.refundsCash)}',
      '-' * 32,
      'Efectivo esperado: ${money.format(summary.expectedCash)}',
      'Efectivo final: ${money.format(finalCash)}',
      'Diferencia: ${money.format(diff)}',
      'Tickets: ${summary.totalTickets}',
      'Devoluciones: ${summary.totalRefunds}',
      if ((note ?? '').trim().isNotEmpty) ...[
        '-' * 32,
        'Nota: ${note!.trim()}',
      ],
      if (movements.isNotEmpty) ...[
        '-' * 32,
        'ULTIMOS MOVIMIENTOS',
        ...movements
            .take(8)
            .map(
              (m) =>
                  '${m.isIn ? '+' : '-'} ${money.format(m.amount)} ${m.reason}',
            ),
      ],
    ];

    return _ref
        .read(unifiedTicketPrinterProvider)
        .printCustomLines(
          lines: lines,
          ticketNumber: 'CIERRE-${state.businessDate}',
        );
  }
}
