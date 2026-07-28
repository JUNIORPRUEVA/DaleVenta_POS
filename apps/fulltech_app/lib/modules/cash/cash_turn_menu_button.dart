import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/debug/app_error_reporter.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import 'cash_close_ticket_printer.dart';
import 'cash_dialogs.dart';
import 'cash_models.dart';
import 'cash_providers.dart';
import 'cash_repository.dart';

class CashTurnMenuButton extends ConsumerWidget {
  const CashTurnMenuButton({super.key, this.compact = false});

  static const _navigatorSettleDelay = Duration(milliseconds: 220);

  final bool compact;

  void _runAfterNavigatorSettles(
    BuildContext context,
    Future<void> Function() action,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        Future<void>.delayed(_navigatorSettleDelay).then((_) async {
          if (!context.mounted) return;
          await action();
        }),
      );
    });
  }

  Future<void> _openCash(BuildContext context, WidgetRef ref) async {
    try {
      final opened = await showOpenCashDialog(
        context,
        onOpenShift: (amount) async {
          await ref
              .read(activeCashSessionControllerProvider.notifier)
              .open(amount);
        },
      );
      if (!context.mounted) return;
      if (opened == true) {
        await ref.read(activeCashSessionControllerProvider.notifier).refresh();
        if (!context.mounted) return;
        showCashToast(context, 'Caja abierta');
      }
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Abrir caja desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  Future<void> _closeCash(BuildContext context, WidgetRef ref) async {
    try {
      final summary = await ref.read(cashRepositoryProvider).summary();
      if (!context.mounted) return;
      final result = await showCloseShiftDialog(
        context,
        expectedCash: summary.expectedCash,
        onCloseShift: (amount) {
          return ref
              .read(activeCashSessionControllerProvider.notifier)
              .close(amount);
        },
      );
      if (!context.mounted) return;
      if (result?.success != true) return;
      await ref.read(activeCashSessionControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      final printResult = result?.printResult;
      final message = printResult == null
          ? 'Turno cerrado'
          : printResult.success
          ? 'Turno cerrado e impreso'
          : 'Turno cerrado. ${printResult.message}';
      showCashToast(context, message);
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Cerrar caja desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  Future<void> _showCurrentTurn(BuildContext context, WidgetRef ref) async {
    final summary = await ref.read(cashRepositoryProvider).summary();
    final movements = await ref.read(cashRepositoryProvider).movements();
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CurrentTurnDialog(
        active: ref.read(activeCashSessionControllerProvider).valueOrNull,
        summary: summary,
        movements: movements,
        onCloseTurn: () {
          Navigator.of(dialogContext).pop('close');
        },
      ),
    );
    if (!context.mounted || action != 'close') return;
    _runAfterNavigatorSettles(context, () => _closeCash(context, ref));
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(cashRepositoryProvider).closedSessions();
    if (!context.mounted) return;
    final rootContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TurnHistoryDialog(
        rows: rows,
        onPrint: (row) async {
          final result = await ref
              .read(cashCloseTicketPrinterProvider)
              .printHistoryTicket(row);
          if (!rootContext.mounted) return;
          showCashToast(
            rootContext,
            result.success
                ? 'Ticket de cierre impreso'
                : 'No se pudo imprimir: ${result.message}',
            isError: !result.success,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCashSessionControllerProvider);
    final active = session.valueOrNull;

    return PopupMenuButton<String>(
      tooltip: 'Turno',
      offset: const Offset(0, 44),
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      constraints: const BoxConstraints(minWidth: 258),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE7EE)),
      ),
      onSelected: (value) {
        debugPrint('[TurnMenu] action selected=$value');
        _runAfterNavigatorSettles(context, () async {
          debugPrint('[TurnMenu] popup closed');
          switch (value) {
            case 'open':
              await _openCash(context, ref);
              break;
            case 'current':
              if (active == null) {
                context.go(Routes.caja);
              } else {
                await _showCurrentTurn(context, ref);
              }
              break;
            case 'history':
              await _showHistory(context, ref);
              break;
            case 'close':
              debugPrint('[TurnMenu] opening close dialog');
              await _closeCash(context, ref);
              break;
            case 'cash':
              context.go(Routes.caja);
              break;
          }
        });
      },
      itemBuilder: (context) => [
        if (active == null)
          const PopupMenuItem(
            value: 'open',
            child: _TurnMenuItem(
              icon: Icons.lock_open_rounded,
              label: 'Abrir caja',
            ),
          )
        else ...[
          const PopupMenuItem(
            value: 'current',
            child: _TurnMenuItem(
              icon: Icons.receipt_long_outlined,
              label: 'Turno actual',
            ),
          ),
          const PopupMenuItem(
            value: 'close',
            child: _TurnMenuItem(
              icon: Icons.point_of_sale_rounded,
              label: 'Hacer corte de turno',
            ),
          ),
        ],
        const PopupMenuItem(
          value: 'history',
          child: _TurnMenuItem(
            icon: Icons.history_rounded,
            label: 'Historial de turnos',
          ),
        ),
      ],
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFDCE8FF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                active == null
                    ? Icons.point_of_sale_outlined
                    : Icons.store_rounded,
                color: const Color(0xFF1957E6),
                size: 16,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text(
                'Turno',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF1957E6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnMenuItem extends StatelessWidget {
  const _TurnMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFDDE7EE)),
            ),
            child: Icon(icon, color: const Color(0xFF1957E6), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF183548),
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF94A3B8),
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _CurrentTurnDialog extends StatelessWidget {
  const _CurrentTurnDialog({
    required this.active,
    required this.summary,
    required this.movements,
    required this.onCloseTurn,
  });

  final ActiveCashSession? active;
  final CashSummaryModel summary;
  final List<CashMovementModel> movements;
  final VoidCallback onCloseTurn;

  @override
  Widget build(BuildContext context) {
    final openedAt = active?.openedAt.toLocal();
    final activeDuration = openedAt == null
        ? 'Turno activo'
        : _formatDuration(DateTime.now().difference(openedAt));
    final dateText = openedAt == null
        ? active?.businessDate ?? ''
        : DateFormat('dd/MM HH:mm', 'es_DO').format(openedAt);

    final media = MediaQuery.sizeOf(context);
    final panelWidth = media.width < 720 ? media.width : 620.0;

    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      backgroundColor: const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox(
        width: panelWidth,
        height: media.height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFDDEAFF)),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFF1957E6),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Corte actual',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          'Resumen del turno activo',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF52667C)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TurnChip(
                    icon: Icons.person_outline_rounded,
                    label: active?.userName ?? 'Usuario',
                  ),
                  _TurnChip(
                    icon: Icons.schedule_rounded,
                    label: activeDuration,
                  ),
                  if (dateText.trim().isNotEmpty)
                    _TurnChip(
                      icon: Icons.calendar_today_outlined,
                      label: dateText,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _TurnHero(summary: summary),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniTurnCard(
                      icon: Icons.radio_button_checked_rounded,
                      value: formatRdCurrencyAccounting(summary.openingAmount),
                      label: 'Base inicial',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniTurnCard(
                      icon: Icons.account_balance_wallet_outlined,
                      value: formatRdCurrencyAccounting(summary.expectedCash),
                      label: 'Efectivo esperado',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniTurnCard(
                      icon: Icons.receipt_long_outlined,
                      value: summary.totalTickets.toString(),
                      label: 'Tickets',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CloseTurnCard(onCloseTurn: onCloseTurn),
              const SizedBox(height: 12),
              _TurnComposition(summary: summary),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDE7EE)),
                  ),
                  child: movements.isEmpty
                      ? const _EmptyMovements()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: movements.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = movements[index];
                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: item.isIn
                                      ? const Color(0xFFF1FAF5)
                                      : const Color(0xFFFFF5F5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: item.isIn
                                        ? const Color(0xFFD8F3E2)
                                        : const Color(0xFFFFDEDE),
                                  ),
                                ),
                                child: Icon(
                                  item.isIn
                                      ? Icons.add_circle_outline_rounded
                                      : Icons.remove_circle_outline_rounded,
                                  color: item.isIn
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                item.reason.isEmpty ? item.type : item.reason,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(item.movementType),
                              trailing: Text(
                                formatRdCurrencyAccounting(item.amount),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: item.isIn
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) return '0m activos';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m activos';
    return '${hours}h ${minutes}m activos';
  }
}

class _TurnChip extends StatelessWidget {
  const _TurnChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1957E6)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTurnCard extends StatelessWidget {
  const _MiniTurnCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1957E6)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF52667C), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CloseTurnCard extends StatelessWidget {
  const _CloseTurnCard({required this.onCloseTurn});

  final VoidCallback onCloseTurn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cierre del turno',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Resumen y movimientos en una misma vista.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF52667C)),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Solo vista'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  side: const BorderSide(color: Color(0xFF9DB9F8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ver corte actual'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1957E6),
                    side: const BorderSide(color: Color(0xFF9DB9F8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCloseTurn,
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('Cerrar turno'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1957E6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyMovements extends StatelessWidget {
  const _EmptyMovements();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay movimientos manuales',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cuando se registren entradas o retiros, aparecerán aquí.',
            style: TextStyle(color: Color(0xFF52667C), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TurnHero extends StatelessWidget {
  const _TurnHero({required this.summary});

  final CashSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total vendido',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            formatRdCurrencyAccounting(summary.totalSales),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Efectivo esperado  ${formatRdCurrencyAccounting(summary.expectedCash)}',
            style: const TextStyle(
              color: Color(0xFF1957E6),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnComposition extends StatelessWidget {
  const _TurnComposition({required this.summary});

  final CashSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Composición del corte',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Total vendido incluye todos los métodos; efectivo esperado es solo gaveta.',
                      style: TextStyle(color: Color(0xFF52667C), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  '6',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Line(
            'Ventas efectivo',
            summary.salesCashTotal,
            icon: Icons.payments_outlined,
            color: Color(0xFF16A34A),
          ),
          _Line(
            'Ventas tarjeta',
            0,
            icon: Icons.credit_card_rounded,
            color: Color(0xFF1957E6),
          ),
          _Line(
            'Transferencias',
            summary.salesTransferTotal,
            icon: Icons.sync_alt_rounded,
            color: Color(0xFF1957E6),
          ),
          _Line(
            'Créditos',
            summary.creditSalesTotal,
            icon: Icons.account_balance_wallet_outlined,
            color: Color(0xFFB45309),
          ),
          if (summary.creditBalanceTotal > 0)
            _Line(
              'Balance crédito',
              summary.creditBalanceTotal,
              icon: Icons.pending_actions_outlined,
              color: Color(0xFFB45309),
            ),
          _Line(
            'Entradas manuales',
            summary.cashInManual,
            icon: Icons.add_circle_outline_rounded,
            color: Color(0xFF16A34A),
          ),
          _Line(
            'Salidas de caja',
            summary.cashOutManual,
            negative: true,
            icon: Icons.remove_circle_outline_rounded,
            color: Color(0xFFDC2626),
          ),
          if (summary.categorySummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),
            const Text(
              'Ventas y ganancia por categoría',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final item in summary.categorySummary.take(5))
              _CategoryLine(item: item),
          ],
        ],
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({required this.item});

  final CashCategorySummaryModel item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF52667C),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${formatRdCurrencyAccounting(item.totalSold)} · ${formatRdCurrencyAccounting(item.totalProfit)}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.negative = false,
    required this.icon,
    required this.color,
  });

  final String label;
  final double value;
  final bool negative;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            formatRdCurrencyAccounting(value),
            style: TextStyle(
              color: negative ? const Color(0xFFDC2626) : color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnHistoryDialog extends StatefulWidget {
  const _TurnHistoryDialog({required this.rows, required this.onPrint});

  final List<CashSessionHistoryModel> rows;
  final Future<void> Function(CashSessionHistoryModel row) onPrint;

  @override
  State<_TurnHistoryDialog> createState() => _TurnHistoryDialogState();
}

class _TurnHistoryDialogState extends State<_TurnHistoryDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCashier;
  String? _selectedStatus;
  String? _selectedBusinessDate;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _cashiers {
    final values =
        widget.rows.map((row) => row.userName.trim()).toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _statuses {
    final values = widget.rows.map((row) => row.status.trim()).toSet().toList()
      ..sort();
    return values.where((value) => value.isNotEmpty).toList();
  }

  List<String> get _dates {
    final values =
        widget.rows.map((row) => row.businessDate.trim()).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    return values.where((value) => value.isNotEmpty).toList();
  }

  List<CashSessionHistoryModel> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    return widget.rows
        .where((row) {
          if ((_selectedCashier ?? '').isNotEmpty &&
              row.userName != _selectedCashier) {
            return false;
          }
          if ((_selectedStatus ?? '').isNotEmpty &&
              row.status != _selectedStatus) {
            return false;
          }
          if ((_selectedBusinessDate ?? '').isNotEmpty &&
              row.businessDate != _selectedBusinessDate) {
            return false;
          }
          if (query.isEmpty) return true;
          final haystack = [
            row.id,
            row.userName,
            row.status,
            row.businessDate,
            row.initialAmount.toStringAsFixed(2),
            row.closingAmount.toStringAsFixed(2),
            row.expectedAmount.toStringAsFixed(2),
            row.difference.toStringAsFixed(2),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedCashier = null;
      _selectedStatus = null;
      _selectedBusinessDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final panelWidth = (media.width * 0.38).clamp(520.0, 660.0).toDouble();
    final rows = _filteredRows;

    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: panelWidth,
        height: media.height,
        child: Material(
          color: const Color(0xFFF8FAFC),
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HistoryPanelHeader(
                  total: widget.rows.length,
                  visible: rows.length,
                  onClose: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 42,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Buscar turno...',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 19,
                                  ),
                                  suffixIcon:
                                      _searchController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Limpiar',
                                          onPressed: () =>
                                              _searchController.clear(),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                        ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD6E3F5),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFD6E3F5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 132,
                            child: _HistoryFilterDropdown(
                              label: 'Cajero',
                              value: _selectedCashier,
                              values: _cashiers,
                              onChanged: (value) =>
                                  setState(() => _selectedCashier = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _HistoryFilterDropdown(
                              label: 'Turno',
                              value: _selectedBusinessDate,
                              values: _dates,
                              onChanged: (value) =>
                                  setState(() => _selectedBusinessDate = value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 142,
                            child: _HistoryFilterDropdown(
                              label: 'Estado',
                              value: _selectedStatus,
                              values: _statuses,
                              onChanged: (value) =>
                                  setState(() => _selectedStatus = value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 46,
                            height: 42,
                            child: Tooltip(
                              message: 'Limpiar filtros',
                              child: OutlinedButton(
                                onPressed: _clearFilters,
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: const Color(0xFF334155),
                                  side: const BorderSide(
                                    color: Color(0xFFD6E3F5),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.filter_alt_off_rounded,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFDDE7EE)),
                Expanded(
                  child: rows.isEmpty
                      ? const _HistoryEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _HistoryTurnCard(
                              row: rows[index],
                              onPrint: () => widget.onPrint(rows[index]),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryPanelHeader extends StatelessWidget {
  const _HistoryPanelHeader({
    required this.total,
    required this.visible,
    required this.onClose,
  });

  final int total;
  final int visible;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDDE7EE))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Color(0xFFDDEAFF)),
            ),
            child: const Icon(Icons.history_rounded, color: Color(0xFF1957E6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historial de turnos',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$visible de $total turnos registrados',
                  style: const TextStyle(
                    color: Color(0xFF52667C),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterDropdown extends StatelessWidget {
  const _HistoryFilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(value: '', child: Text('Todos')),
          ...values.map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (next) => onChanged((next ?? '').isEmpty ? null : next),
      ),
    );
  }
}

class _HistoryTurnCard extends StatelessWidget {
  const _HistoryTurnCard({required this.row, required this.onPrint});

  final CashSessionHistoryModel row;
  final Future<void> Function() onPrint;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_DO');
    final opened = fmt.format(row.openedAt.toLocal());
    final closed = row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(row.closedAt!.toLocal());
    final differenceColor = row.difference.abs() < 0.01
        ? const Color(0xFF64748B)
        : row.difference > 0
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Color(0xFF334155),
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Turno ${row.businessDate}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _HistoryStatusPill(status: row.status),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Reimprimir ticket',
                onPressed: onPrint,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  backgroundColor: const Color(0xFFEAF1FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(Icons.print_rounded, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: _HistoryAmount('Inicial', row.initialAmount)),
              Expanded(child: _HistoryAmount('Esperado', row.expectedAmount)),
              Expanded(child: _HistoryAmount('Cierre', row.closingAmount)),
              Expanded(
                child: _HistoryAmount(
                  'Dif.',
                  row.difference,
                  color: differenceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  Expanded(
                    child: _HistoryDateChip(
                      icon: Icons.login_rounded,
                      text: opened,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HistoryDateChip(
                      icon: Icons.logout_rounded,
                      text: closed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDateChip extends StatelessWidget {
  const _HistoryDateChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryAmount extends StatelessWidget {
  const _HistoryAmount(this.label, this.value, {this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          formatRdCurrencyAccounting(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color ?? const Color(0xFF0F172A),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HistoryStatusPill extends StatelessWidget {
  const _HistoryStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toUpperCase();
    final closed = normalized == 'CLOSED' || normalized == 'CERRADO';
    final color = closed ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);
    final label = status.trim().isEmpty
        ? 'Turno'
        : (closed ? 'Cerrado' : status.trim());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                color: Color(0xFF1957E6),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Sin turnos para mostrar',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Prueba cambiando los filtros o revisa cuando existan turnos cerrados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF52667C),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
