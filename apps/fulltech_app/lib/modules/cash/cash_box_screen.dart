import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import 'cash_models.dart';
import 'cash_providers.dart';

Future<double?> showCashAmountDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String hint = '0.00',
}) {
  final controller = TextEditingController(text: hint);
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Monto',
          prefixText: r'RD$ ',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            Navigator.pop(context, value);
          },
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

class CashBoxScreen extends ConsumerWidget {
  const CashBoxScreen({super.key});

  Future<void> _openCash(BuildContext context, WidgetRef ref) async {
    final amount = await showCashAmountDialog(
      context,
      title: 'Abrir caja',
      actionLabel: 'Abrir turno',
    );
    if (amount == null) return;
    await ref.read(activeCashSessionControllerProvider.notifier).open(amount);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Caja abierta')));
  }

  Future<void> _closeCash(BuildContext context, WidgetRef ref) async {
    final amount = await showCashAmountDialog(
      context,
      title: 'Cerrar turno',
      actionLabel: 'Cerrar',
    );
    if (amount == null) return;
    await ref.read(activeCashSessionControllerProvider.notifier).close(amount);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Turno cerrado')));
  }

  Future<void> _addMovement(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) async {
    final amount = await showCashAmountDialog(
      context,
      title: type == 'IN' ? 'Entrada de efectivo' : 'Salida de efectivo',
      actionLabel: 'Guardar',
    );
    if (amount == null) return;
    await ref
        .read(activeCashSessionControllerProvider.notifier)
        .addMovement(
          type: type,
          amount: amount,
          reason: type == 'IN' ? 'Entrada manual' : 'Salida manual',
          movementType: type == 'OUT' ? 'expense' : 'transfer',
          affectsProfit: type == 'OUT',
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Movimiento guardado')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final session = ref.watch(activeCashSessionControllerProvider);
    final summary = ref.watch(cashSummaryProvider);
    final movements = ref.watch(cashMovementsProvider);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(Routes.cotizaciones),
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('Entrar al POS'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: session.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CashError(error: '$error'),
          data: (active) => active == null
              ? _ClosedCashView(onOpen: () => _openCash(context, ref))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _ActiveCashPanel(
                        active: active,
                        summary: summary,
                        onClose: () => _closeCash(context, ref),
                        onCashIn: () => _addMovement(context, ref, 'IN'),
                        onCashOut: () => _addMovement(context, ref, 'OUT'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _MovementsPanel(movements: movements)),
                  ],
                ),
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
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.point_of_sale_rounded, size: 48),
                const SizedBox(height: 14),
                const Text(
                  'Caja cerrada',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Abre un turno para poder facturar y registrar movimientos.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Abrir caja'),
                ),
              ],
            ),
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
  final AsyncValue<CashSummaryModel> summary;
  final VoidCallback onClose;
  final VoidCallback onCashIn;
  final VoidCallback onCashOut;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Turno activo',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text('${active.userName} · ${active.businessDate}'),
            const SizedBox(height: 18),
            summary.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('$error'),
              data: (data) => Column(
                children: [
                  _Metric('Base inicial', data.openingAmount),
                  _Metric('Ventas efectivo', data.salesCashTotal),
                  _Metric('Transferencias', data.salesTransferTotal),
                  _Metric('Entradas manuales', data.cashInManual),
                  _Metric('Salidas manuales', data.cashOutManual),
                  const Divider(height: 24),
                  _Metric('Efectivo esperado', data.expectedCash, strong: true),
                  _Metric('Tickets', data.totalTickets.toDouble(), count: true),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCashIn,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Entrada'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCashOut,
                    icon: const Icon(Icons.remove_rounded),
                    label: const Text('Salida'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Cerrar turno'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsPanel extends StatelessWidget {
  const _MovementsPanel({required this.movements});

  final AsyncValue<List<CashMovementModel>> movements;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Movimientos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const Divider(),
            Expanded(
              child: movements.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (rows) => rows.isEmpty
                    ? const Center(child: Text('Sin movimientos registrados'))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            leading: Icon(
                              row.isIn
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                            ),
                            title: Text(
                              row.reason.isEmpty ? row.type : row.reason,
                            ),
                            subtitle: Text(row.movementType),
                            trailing: Text(
                              formatRdCurrencyAccounting(row.amount),
                              style: TextStyle(
                                color: row.isIn ? Colors.green : Colors.red,
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
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
    this.label,
    this.value, {
    this.strong = false,
    this.count = false,
  });

  final String label;
  final double value;
  final bool strong;
  final bool count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            count
                ? value.toStringAsFixed(0)
                : formatRdCurrencyAccounting(value),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
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
