import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_page_header.dart';
import 'cash_dialogs.dart';
import 'cash_models.dart';
import 'cash_providers.dart';
import 'cash_repository.dart';
import 'cash_turn_menu_button.dart';

class CashBoxScreen extends ConsumerWidget {
  const CashBoxScreen({super.key});

  static const _primary = Color(0xFF0E5261);
  static const _accent = Color(0xFF1957E6);
  static const _surface = Color(0xFFF7FBFE);
  static const _line = Color(0xFFD4E3ED);

  Future<void> _openCash(BuildContext context, WidgetRef ref) async {
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
  }

  Future<void> _closeCash(BuildContext context, WidgetRef ref) async {
    final currentSummary = await ref.read(cashRepositoryProvider).summary();
    if (!context.mounted) return;
    final amount = await showCashAmountDialog(
      context,
      title: 'Cerrar turno',
      actionLabel: 'Cerrar turno',
      hint: currentSummary.expectedCash.toStringAsFixed(2),
    );
    if (amount == null) return;
    final printResult = await ref
        .read(activeCashSessionControllerProvider.notifier)
        .close(amount);
    if (!context.mounted) return;
    final message = printResult == null
        ? 'Turno cerrado'
        : printResult.success
        ? 'Turno cerrado e impreso'
        : 'Turno cerrado. ${printResult.message}';
    showCashToast(context, message);
  }

  Future<void> _addMovement(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) async {
    final input = await showCashMovementDialog(context, type: type);
    if (input == null) return;
    await ref
        .read(activeCashSessionControllerProvider.notifier)
        .addMovement(
          type: type,
          amount: input.amount,
          reason: input.reason,
          movementType: input.movementType,
          affectsProfit: input.affectsProfit,
        );
    if (!context.mounted) return;
    showCashToast(context, 'Movimiento guardado');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final session = ref.watch(activeCashSessionControllerProvider);
    final summary = ref.watch(cashSummaryProvider);
    final movements = ref.watch(cashMovementsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FA),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: FullTechPageHeader(
        title: 'Caja',
        actions: [
          const CashTurnMenuButton(),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => context.go(Routes.cotizaciones),
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('Entrar al POS'),
            style: TextButton.styleFrom(foregroundColor: _accent),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: session.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CashError(error: '$error'),
          data: (active) {
            if (active == null) {
              return _ClosedCashView(onOpen: () => _openCash(context, ref));
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final activePanel = _ActiveCashPanel(
                  active: active,
                  summary: summary,
                  onClose: () => _closeCash(context, ref),
                  onCashIn: () => _addMovement(context, ref, 'IN'),
                  onCashOut: () => _addMovement(context, ref, 'OUT'),
                );
                final movementsPanel = _MovementsPanel(movements: movements);
                if (constraints.maxWidth < 980) {
                  return ListView(
                    children: [
                      SizedBox(height: 620, child: activePanel),
                      const SizedBox(height: 14),
                      SizedBox(height: 420, child: movementsPanel),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: activePanel),
                    const SizedBox(width: 16),
                    Expanded(child: movementsPanel),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ClosedCashView extends StatelessWidget {
  const _ClosedCashView({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _CashCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _IconBox(
                icon: Icons.point_of_sale_rounded,
                size: 58,
                iconSize: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                'Caja cerrada',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Abre un turno para poder facturar y registrar movimientos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF5D7085)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Abrir caja'),
                style: FilledButton.styleFrom(
                  backgroundColor: CashBoxScreen._accent,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveCashPanel extends StatelessWidget {
  const _ActiveCashPanel({
    required this.active,
    required this.summary,
    required this.onClose,
    required this.onCashIn,
    required this.onCashOut,
  });

  final ActiveCashSession active;
  final AsyncValue<CashSummaryModel?> summary;
  final VoidCallback onClose;
  final VoidCallback onCashIn;
  final VoidCallback onCashOut;

  @override
  Widget build(BuildContext context) {
    return _CashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.account_balance_wallet_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turno activo',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _CashChip(
                          icon: Icons.person_outline_rounded,
                          label: active.userName,
                        ),
                        _CashChip(
                          icon: Icons.calendar_today_outlined,
                          label: active.businessDate,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _PanelMessage(
                icon: Icons.info_outline_rounded,
                title: 'No se pudo cargar el corte',
                detail: '$error',
              ),
              data: (data) {
                if (data == null) {
                  return const _PanelMessage(
                    icon: Icons.lock_outline_rounded,
                    title: 'No hay turno abierto',
                    detail: 'Abre un turno para ver el corte.',
                  );
                }
                return ListView(
                  children: [
                    _HeroTotal(summary: data),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallTotal(
                            icon: Icons.savings_outlined,
                            label: 'Base inicial',
                            value: formatRdCurrencyAccounting(
                              data.openingAmount,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SmallTotal(
                            icon: Icons.payments_outlined,
                            label: 'Efectivo esperado',
                            value: formatRdCurrencyAccounting(
                              data.expectedCash,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SmallTotal(
                            icon: Icons.confirmation_number_outlined,
                            label: 'Tickets',
                            value: data.totalTickets.toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CompositionCard(summary: data),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCashIn,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Entrada'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CashBoxScreen._primary,
                    side: const BorderSide(color: CashBoxScreen._primary),
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCashOut,
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Gasto / salida'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CashBoxScreen._primary,
                    side: const BorderSide(color: CashBoxScreen._primary),
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Cerrar turno'),
            style: FilledButton.styleFrom(
              backgroundColor: CashBoxScreen._primary,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementsPanel extends ConsumerWidget {
  const _MovementsPanel({required this.movements});

  final AsyncValue<List<CashMovementModel>> movements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Movimientos',
                  style: TextStyle(
                    fontSize: 18,
                    color: Color(0xFF536A80),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => ref.invalidate(cashMovementsProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const Divider(color: CashBoxScreen._line),
          Expanded(
            child: movements.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => const _PanelMessage(
                icon: Icons.info_outline_rounded,
                title: 'Sin movimientos disponibles',
                detail: 'Abre un turno para consultar movimientos.',
              ),
              data: (rows) => rows.isEmpty
                  ? const _PanelMessage(
                      icon: Icons.receipt_long_outlined,
                      title: 'No hay movimientos manuales',
                      detail:
                          'Cuando se registren entradas o salidas, apareceran aqui.',
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: CashBoxScreen._line),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: row.isIn
                                  ? const Color(0xFFE8F8EF)
                                  : const Color(0xFFFFEEF0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              row.isIn
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: row.isIn
                                  ? const Color(0xFF11A852)
                                  : const Color(0xFFE11D48),
                            ),
                          ),
                          title: Text(
                            row.reason.isEmpty ? row.type : row.reason,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(_movementLabel(row.movementType)),
                          trailing: Text(
                            formatRdCurrencyAccounting(row.amount),
                            style: TextStyle(
                              color: row.isIn
                                  ? const Color(0xFF11A852)
                                  : const Color(0xFFE11D48),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _movementLabel(String value) {
    return switch (value) {
      'transfer' => 'Transferencia',
      'expense' => 'Gasto',
      'owner_draw' => 'Retiro',
      _ => value,
    };
  }
}

class _HeroTotal extends StatelessWidget {
  const _HeroTotal({required this.summary});

  final CashSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CashBoxScreen._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total vendido',
            style: TextStyle(
              color: Color(0xFF61748A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatRdCurrencyAccounting(summary.totalSales),
            style: const TextStyle(
              fontSize: 32,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Efectivo esperado  ${formatRdCurrencyAccounting(summary.expectedCash)}',
              style: const TextStyle(
                color: CashBoxScreen._accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallTotal extends StatelessWidget {
  const _SmallTotal({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CashBoxScreen._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CashBoxScreen._accent, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF61748A), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.summary});

  final CashSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CashBoxScreen._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Composición del corte',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _Metric('Ventas efectivo', summary.salesCashTotal),
          _Metric('Transferencias', summary.salesTransferTotal),
          _Metric('Entradas manuales', summary.cashInManual),
          _Metric('Salidas de caja', summary.cashOutManual, negative: true),
          _Metric('Devoluciones efectivo', summary.refundsCash, negative: true),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.negative = false});

  final String label;
  final double value;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF52677C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatRdCurrencyAccounting(value),
            style: TextStyle(
              color: negative ? const Color(0xFFE11D48) : CashBoxScreen._accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CashBoxScreen._surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CashBoxScreen._line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110B3550),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CashChip extends StatelessWidget {
  const _CashChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE8F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: CashBoxScreen._accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF43566B),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.size = 42, this.iconSize = 24});

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: CashBoxScreen._accent, size: iconSize),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBox(icon: icon, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF61748A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashError extends StatelessWidget {
  const _CashError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(error));
  }
}
