import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_page_header.dart';
import 'cash_dialogs.dart';
import 'cash_models.dart';
import 'cash_providers.dart';
import 'cash_repository.dart';
import 'cash_turn_menu_button.dart';

const _cashPrimary = AppColors.primary;
const _cashBlue = AppColors.secondary;
const _cashBg = AppColors.background;
const _cashSurface = AppColors.surfaceAlt;
const _cashLine = AppColors.border;
const _cashText = AppColors.textPrimary;
const _cashMuted = AppColors.textSecondary;
const _danger = AppColors.error;

final cashExpenseHistoryProvider = FutureProvider<List<CashMovementModel>>((
  ref,
) {
  return ref
      .watch(cashRepositoryProvider)
      .movementHistory(type: 'OUT', movementType: 'expense', take: 220);
});

final cashMovementHistoryProvider = FutureProvider<List<CashMovementModel>>((
  ref,
) {
  return ref.watch(cashRepositoryProvider).movementHistory(take: 260);
});

final cashTurnHistoryProvider = FutureProvider<List<CashSessionHistoryModel>>((
  ref,
) {
  return ref.watch(cashRepositoryProvider).closedSessions();
});

class CashExpenseScreen extends ConsumerStatefulWidget {
  const CashExpenseScreen({super.key});

  @override
  ConsumerState<CashExpenseScreen> createState() => _CashExpenseScreenState();
}

class _CashExpenseScreenState extends ConsumerState<CashExpenseScreen> {
  final _amountController = TextEditingController(text: '0.00');
  final _reasonController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseDominicanAmount(_amountController.text);
    final reason = _reasonController.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresa un monto válido.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Indica el concepto del gasto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(activeCashSessionControllerProvider.notifier)
          .addMovement(
            type: 'OUT',
            amount: amount,
            reason: reason,
            movementType: 'expense',
            affectsProfit: true,
          );
      ref.invalidate(cashExpenseHistoryProvider);
      if (!mounted) return;
      showCashToast(context, 'Gasto registrado');
      _amountController.text = '0.00';
      _reasonController.clear();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = resolveCashError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final session = ref.watch(activeCashSessionControllerProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            context.go(Routes.caja),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _cashBg,
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: const FullTechPageHeader(
            title: 'Registrar gasto',
            actions: [CashTurnMenuButton(), SizedBox(width: 10)],
          ),
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: session.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _CashPanelMessage(
                icon: Icons.info_outline_rounded,
                title: 'No se pudo cargar caja',
                detail: '$error',
              ),
              data: (active) {
                if (active == null) {
                  return _CashPanelMessage(
                    icon: Icons.lock_outline_rounded,
                    title: 'Caja cerrada',
                    detail:
                        'Abre un turno para registrar gastos y movimientos de caja.',
                    action: FilledButton.icon(
                      onPressed: () => context.go(Routes.caja),
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: const Text('Ir a caja'),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final form = _ExpenseFormCard(
                      amountController: _amountController,
                      reasonController: _reasonController,
                      error: _error,
                      saving: _saving,
                      onSave: _save,
                    );
                    final recent = const _RecentExpensesCard();
                    if (!wide) {
                      return ListView(
                        children: [
                          form,
                          const SizedBox(height: 14),
                          SizedBox(height: 420, child: recent),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: form),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: recent),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class CashMovementsHistoryScreen extends ConsumerStatefulWidget {
  const CashMovementsHistoryScreen({super.key});

  @override
  ConsumerState<CashMovementsHistoryScreen> createState() =>
      _CashMovementsHistoryScreenState();
}

enum _MovementTypeFilter { all, inOnly, outOnly }

enum _MovementDateFilter { today, yesterday, week, month, specific, all }

class _CashMovementsHistoryScreenState
    extends ConsumerState<CashMovementsHistoryScreen> {
  final _searchController = TextEditingController();
  _MovementTypeFilter _type = _MovementTypeFilter.all;
  _MovementDateFilter _date = _MovementDateFilter.today;
  DateTime? _specificDate;

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

  Future<void> _register(String type) async {
    final input = await showCashMovementDialog(context, type: type);
    if (input == null) return;
    try {
      await ref
          .read(activeCashSessionControllerProvider.notifier)
          .addMovement(
            type: type,
            amount: input.amount,
            reason: input.reason,
            movementType: input.movementType,
            affectsProfit: input.affectsProfit,
          );
      ref.invalidate(cashMovementHistoryProvider);
      ref.invalidate(cashExpenseHistoryProvider);
      if (!mounted) return;
      showCashToast(
        context,
        type == 'IN' ? 'Ingreso registrado' : 'Salida registrada',
      );
    } catch (error) {
      if (!mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  List<CashMovementModel> _filter(List<CashMovementModel> rows) {
    final query = _searchController.text.trim().toLowerCase();
    return rows
        .where((row) {
          if (_type == _MovementTypeFilter.inOnly && !row.isIn) return false;
          if (_type == _MovementTypeFilter.outOnly && row.isIn) return false;
          if (!_matchesDate(row.createdAt)) return false;
          if (query.isEmpty) return true;
          final text = [
            row.reason,
            row.userName ?? '',
            row.businessDate ?? '',
            row.amount.toStringAsFixed(2),
            row.type,
            row.movementType,
            row.sessionStatus ?? '',
          ].join(' ').toLowerCase();
          return text.contains(query);
        })
        .toList(growable: false);
  }

  bool _matchesDate(DateTime value) {
    if (_date == _MovementDateFilter.all) return true;
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rowDay = DateTime(local.year, local.month, local.day);
    return switch (_date) {
      _MovementDateFilter.today => rowDay == today,
      _MovementDateFilter.yesterday =>
        rowDay == today.subtract(const Duration(days: 1)),
      _MovementDateFilter.week => !rowDay.isBefore(
        today.subtract(Duration(days: today.weekday - 1)),
      ),
      _MovementDateFilter.month =>
        rowDay.year == today.year && rowDay.month == today.month,
      _MovementDateFilter.specific =>
        _specificDate == null || _sameCalendarDay(rowDay, _specificDate!),
      _MovementDateFilter.all => true,
    };
  }

  Future<void> _pickSpecificDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('es', 'DO'),
      helpText: 'Filtrar por fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _specificDate = selected;
      _date = _MovementDateFilter.specific;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final history = ref.watch(cashMovementHistoryProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            ref.invalidate(cashMovementHistoryProvider),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _cashBg,
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: FullTechPageHeader(
            title: 'Movimiento de efectivo',
            actions: [
              if (isMobile) ...[
                IconButton.filledTonal(
                  tooltip: 'Registrar ingreso',
                  onPressed: () => _register('IN'),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Registrar salida',
                  onPressed: () => _register('OUT'),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else ...[
                TextButton.icon(
                  onPressed: () => _register('IN'),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Registrar ingreso'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _register('OUT'),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: const Text('Registrar salida'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Actualizar',
                onPressed: () => ref.invalidate(cashMovementHistoryProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
              SizedBox(width: isMobile ? 6 : 10),
              const CashTurnMenuButton(),
              SizedBox(width: isMobile ? 6 : 10),
            ],
          ),
          body: Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 18),
            child: _CashCard(
              child: Column(
                children: [
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CashSearchField(
                          controller: _searchController,
                          hint: 'Buscar movimientos...',
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _MovementTypeSelector(
                            selected: _type,
                            onChanged: (value) => setState(() => _type = value),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _CashSearchField(
                            controller: _searchController,
                            hint:
                                'Buscar por usuario, motivo, monto o turno...',
                          ),
                        ),
                        const SizedBox(width: 10),
                        _MovementTypeSelector(
                          selected: _type,
                          onChanged: (value) => setState(() => _type = value),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _MovementDateSelector(
                            selected: _date,
                            onChanged: (next) {
                              if (next == _MovementDateFilter.specific) {
                                _pickSpecificDate();
                                return;
                              }
                              setState(() => _date = next);
                            },
                          ),
                          if (_date == _MovementDateFilter.specific) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _pickSpecificDate,
                              icon: const Icon(Icons.event_rounded, size: 18),
                              label: Text(
                                _specificDate == null
                                    ? 'Elegir fecha'
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                        'es_DO',
                                      ).format(_specificDate!),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _cashText,
                                minimumSize: Size(isMobile ? 118 : 132, 40),
                                side: const BorderSide(color: _cashLine),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: history.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _CashPanelMessage(
                        icon: Icons.payments_outlined,
                        title: 'No se pudieron cargar movimientos',
                        detail: resolveCashError(error),
                      ),
                      data: (rows) {
                        final visible = _filter(rows);
                        final entries = visible
                            .where((row) => row.isIn)
                            .fold<double>(0, (sum, row) => sum + row.amount);
                        final exits = visible
                            .where((row) => !row.isIn)
                            .fold<double>(0, (sum, row) => sum + row.amount);
                        return Column(
                          children: [
                            _MovementStatsGrid(
                              isMobile: isMobile,
                              entries: entries,
                              exits: exits,
                              count: visible.length,
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: visible.isEmpty
                                  ? const _CashPanelMessage(
                                      icon: Icons.history_toggle_off_rounded,
                                      title: 'Sin movimientos',
                                      detail:
                                          'No hay entradas ni salidas en el rango seleccionado.',
                                    )
                                  : ListView.separated(
                                      padding: EdgeInsets.only(
                                        bottom: isMobile ? 8 : 0,
                                      ),
                                      itemCount: visible.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) =>
                                          _CashMovementRow(row: visible[index]),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MovementTypeSelector extends StatelessWidget {
  const _MovementTypeSelector({
    required this.selected,
    required this.onChanged,
  });

  final _MovementTypeFilter selected;
  final ValueChanged<_MovementTypeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_MovementTypeFilter>(
      segments: const [
        ButtonSegment(value: _MovementTypeFilter.all, label: Text('Todos')),
        ButtonSegment(
          value: _MovementTypeFilter.inOnly,
          label: Text('Entradas'),
        ),
        ButtonSegment(
          value: _MovementTypeFilter.outOnly,
          label: Text('Salidas'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _MovementDateSelector extends StatelessWidget {
  const _MovementDateSelector({
    required this.selected,
    required this.onChanged,
  });

  final _MovementDateFilter selected;
  final ValueChanged<_MovementDateFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_MovementDateFilter>(
      segments: const [
        ButtonSegment(value: _MovementDateFilter.today, label: Text('Hoy')),
        ButtonSegment(
          value: _MovementDateFilter.yesterday,
          label: Text('Ayer'),
        ),
        ButtonSegment(value: _MovementDateFilter.week, label: Text('Semana')),
        ButtonSegment(value: _MovementDateFilter.month, label: Text('Mes')),
        ButtonSegment(
          value: _MovementDateFilter.specific,
          label: Text('Fecha'),
        ),
        ButtonSegment(value: _MovementDateFilter.all, label: Text('Todo')),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _MovementStatsGrid extends StatelessWidget {
  const _MovementStatsGrid({
    required this.isMobile,
    required this.entries,
    required this.exits,
    required this.count,
  });

  final bool isMobile;
  final double entries;
  final double exits;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.receipt_long_outlined,
        label: 'Movimientos',
        value: count.toString(),
      ),
      _StatCard(
        icon: Icons.add_circle_outline_rounded,
        label: 'Entradas',
        value: formatRdCurrencyAccounting(entries),
        valueColor: _cashBlue,
      ),
      _StatCard(
        icon: Icons.remove_circle_outline_rounded,
        label: 'Salidas',
        value: formatRdCurrencyAccounting(exits),
        valueColor: _danger,
      ),
      _StatCard(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Balance',
        value: formatRdCurrencyAccounting(entries - exits),
      ),
    ];

    if (!isMobile) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.55,
      children: cards,
    );
  }
}

class CashExpensesHistoryScreen extends ConsumerStatefulWidget {
  const CashExpensesHistoryScreen({super.key});

  @override
  ConsumerState<CashExpensesHistoryScreen> createState() =>
      _CashExpensesHistoryScreenState();
}

class _CashExpensesHistoryScreenState
    extends ConsumerState<CashExpensesHistoryScreen> {
  final _searchController = TextEditingController();
  DateTime? _expenseDate;

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

  List<CashMovementModel> _filter(List<CashMovementModel> rows) {
    final query = _searchController.text.trim().toLowerCase();
    return rows
        .where((row) {
          if (_expenseDate != null &&
              !_sameCalendarDay(row.createdAt.toLocal(), _expenseDate!)) {
            return false;
          }
          if (query.isEmpty) return true;
          final text = [
            row.reason,
            row.userName ?? '',
            row.businessDate ?? '',
            row.amount.toStringAsFixed(2),
          ].join(' ').toLowerCase();
          return text.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _pickExpenseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expenseDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('es', 'DO'),
      helpText: 'Filtrar gastos por fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (selected == null || !mounted) return;
    setState(() => _expenseDate = selected);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final history = ref.watch(cashExpenseHistoryProvider);

    return Scaffold(
      backgroundColor: _cashBg,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const FullTechPageHeader(
        title: 'Historial de gastos',
        actions: [CashTurnMenuButton(), SizedBox(width: 10)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: _CashCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _CashSearchField(
                      controller: _searchController,
                      hint: 'Buscar por concepto, usuario o monto...',
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.cajaRegistrarGasto),
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('Registrar gasto'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _cashBlue,
                      minimumSize: const Size(172, 48),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickExpenseDate,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      _expenseDate == null
                          ? 'Fecha'
                          : DateFormat(
                              'dd/MM/yyyy',
                              'es_DO',
                            ).format(_expenseDate!),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cashText,
                      minimumSize: const Size(116, 48),
                      side: const BorderSide(color: _cashLine),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  if (_expenseDate != null) ...[
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Quitar filtro de fecha',
                      onPressed: () => setState(() => _expenseDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Actualizar',
                    onPressed: () => ref.invalidate(cashExpenseHistoryProvider),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: history.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _CashPanelMessage(
                    icon: Icons.receipt_long_outlined,
                    title: 'No se pudo cargar historial',
                    detail: resolveCashError(error),
                  ),
                  data: (rows) {
                    final visible = _filter(rows);
                    final total = visible.fold<double>(
                      0,
                      (sum, row) => sum + row.amount,
                    );
                    return Column(
                      children: [
                        _HistorySummaryBar(
                          count: visible.length,
                          total: total,
                          label: 'Gastos registrados',
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: visible.isEmpty
                              ? const _CashPanelMessage(
                                  icon: Icons.payments_outlined,
                                  title: 'Sin gastos para mostrar',
                                  detail:
                                      'Cuando registres gastos de caja aparecerán aquí.',
                                )
                              : ListView.separated(
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) =>
                                      _ExpenseHistoryRow(row: visible[index]),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CashTurnHistoryScreen extends ConsumerWidget {
  const CashTurnHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final history = ref.watch(cashTurnHistoryProvider);

    return Scaffold(
      backgroundColor: _cashBg,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const FullTechPageHeader(
        title: 'Historial de turnos',
        actions: [CashTurnMenuButton(), SizedBox(width: 10)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CashCard(
            child: _CashPanelMessage(
              icon: Icons.history_toggle_off_rounded,
              title: 'No se pudo cargar historial',
              detail: resolveCashError(error),
            ),
          ),
          data: (rows) {
            final totalExpected = rows.fold<double>(
              0,
              (sum, row) => sum + row.expectedAmount,
            );
            final totalDiff = rows.fold<double>(
              0,
              (sum, row) => sum + row.difference,
            );
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.history_rounded,
                        label: 'Turnos cerrados',
                        value: rows.length.toString(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Esperado acumulado',
                        value: formatRdCurrencyAccounting(totalExpected),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Diferencia',
                        value: formatRdCurrencyAccounting(totalDiff),
                        valueColor: totalDiff.abs() < 0.01
                            ? _cashText
                            : totalDiff > 0
                            ? const Color(0xFF16A34A)
                            : _danger,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Actualizar',
                      onPressed: () => ref.invalidate(cashTurnHistoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _CashCard(
                    padding: EdgeInsets.zero,
                    child: rows.isEmpty
                        ? const _CashPanelMessage(
                            icon: Icons.history_toggle_off_rounded,
                            title: 'Sin turnos cerrados',
                            detail:
                                'Cuando cierres turnos de caja aparecerán aquí.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) =>
                                _TurnHistoryWideCard(row: rows[index]),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExpenseFormCard extends StatelessWidget {
  const _ExpenseFormCard({
    required this.amountController,
    required this.reasonController,
    required this.error,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController amountController;
  final TextEditingController reasonController;
  final String? error;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _CashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.add_card_rounded,
            title: 'Registrar gasto',
            subtitle: 'Salida operativa que afecta utilidad y corte de caja',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('Monto', prefix: 'RD\$ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            minLines: 3,
            maxLines: 5,
            decoration: _inputDecoration(
              'Concepto del gasto',
              hint: 'Ejemplo: Compra de material, transporte, mantenimiento...',
            ),
          ),
          if ((error ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _InlineError(error!),
          ],
          const Spacer(),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando...' : 'Registrar gasto'),
            style: FilledButton.styleFrom(
              backgroundColor: _cashPrimary,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter para guardar · Esc para volver',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _cashMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentExpensesCard extends ConsumerWidget {
  const _RecentExpensesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(cashExpenseHistoryProvider);
    return _CashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Gastos recientes',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              TextButton(
                onPressed: () => context.go(Routes.cajaGastosHistorial),
                child: const Text('Ver historial'),
              ),
            ],
          ),
          const Divider(color: _cashLine),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _CashPanelMessage(
                icon: Icons.info_outline_rounded,
                title: 'Sin historial disponible',
                detail: resolveCashError(error),
              ),
              data: (rows) {
                final recent = rows.take(8).toList(growable: false);
                if (recent.isEmpty) {
                  return const _CashPanelMessage(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin gastos registrados',
                    detail: 'Los gastos nuevos aparecerán aquí.',
                  );
                }
                return ListView.separated(
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _ExpenseHistoryRow(row: recent[index], dense: true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseHistoryRow extends StatelessWidget {
  const _ExpenseHistoryRow({required this.row, this.dense = false});

  final CashMovementModel row;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
      'es_DO',
    ).format(row.createdAt.toLocal());
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 0 : 14,
        vertical: dense ? 8 : 12,
      ),
      decoration: dense
          ? null
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cashLine),
            ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEF0),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.payments_outlined, color: _danger),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.reason.isEmpty ? 'Gasto operativo' : row.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${row.userName ?? 'Usuario'} · ${row.businessDate ?? date}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _cashMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRdCurrencyAccounting(row.amount),
                style: const TextStyle(
                  color: _danger,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                date,
                style: const TextStyle(color: _cashMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashMovementRow extends StatelessWidget {
  const _CashMovementRow({required this.row});

  final CashMovementModel row;

  @override
  Widget build(BuildContext context) {
    final isIn = row.isIn;
    final color = isIn ? _cashBlue : _danger;
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
      'es_DO',
    ).format(row.createdAt.toLocal());
    final label = isIn ? 'Ingreso' : 'Salida';

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _cashLine),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MovementIcon(isIn: isIn, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MovementText(row: row, label: label),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatRdCurrencyAccounting(row.amount),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MovementTypePill(label: label, color: color),
                    Text(
                      date,
                      style: const TextStyle(
                        color: _cashMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                _MovementIcon(isIn: isIn, color: color),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _MovementText(row: row, label: label),
                ),
                Expanded(
                  child: Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _cashMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MovementTypePill(label: label, color: color),
                const SizedBox(width: 16),
                SizedBox(
                  width: 140,
                  child: Text(
                    formatRdCurrencyAccounting(row.amount),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MovementIcon extends StatelessWidget {
  const _MovementIcon({required this.isIn, required this.color});

  final bool isIn;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isIn
            ? Icons.add_circle_outline_rounded
            : Icons.remove_circle_outline_rounded,
        color: color,
      ),
    );
  }
}

class _MovementText extends StatelessWidget {
  const _MovementText({required this.row, required this.label});

  final CashMovementModel row;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.reason.trim().isEmpty ? label : row.reason.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          '${row.userName ?? 'Usuario'} · Turno ${row.businessDate ?? 'actual'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _cashMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MovementTypePill extends StatelessWidget {
  const _MovementTypePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TurnHistoryWideCard extends StatelessWidget {
  const _TurnHistoryWideCard({required this.row});

  final CashSessionHistoryModel row;

  Future<void> _showDetail(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (context) => _TurnDetailDialog(row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_DO');
    final opened = fmt.format(row.openedAt.toLocal());
    final closed = row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(row.closedAt!.toLocal());
    final diffColor = row.difference.abs() < 0.01
        ? _cashMuted
        : row.difference > 0
        ? const Color(0xFF16A34A)
        : _danger;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE8F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0B3550),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.point_of_sale_rounded, color: _cashBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _TurnInfoBlock(
              title: row.userName,
              subtitle: 'Turno ${row.businessDate}',
            ),
          ),
          Expanded(
            child: _TurnInfoBlock(title: 'Abrió', subtitle: opened),
          ),
          Expanded(
            child: _TurnInfoBlock(title: 'Cerró', subtitle: closed),
          ),
          Expanded(
            child: _TurnInfoBlock(
              title: 'Inicial',
              subtitle: formatRdCurrencyAccounting(row.initialAmount),
            ),
          ),
          Expanded(
            child: _TurnInfoBlock(
              title: 'Esperado',
              subtitle: formatRdCurrencyAccounting(row.expectedAmount),
            ),
          ),
          Expanded(
            child: _TurnInfoBlock(
              title: 'Cierre',
              subtitle: formatRdCurrencyAccounting(row.closingAmount),
            ),
          ),
          Expanded(
            child: _TurnInfoBlock(
              title: 'Diferencia',
              subtitle: formatRdCurrencyAccounting(row.difference),
              color: diffColor,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _showDetail(context),
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('Ver detalle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _cashBlue,
              side: const BorderSide(color: Color(0xFFC7D8FF)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnDetailDialog extends StatelessWidget {
  const _TurnDetailDialog({required this.row});

  final CashSessionHistoryModel row;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_DO');
    final opened = fmt.format(row.openedAt.toLocal());
    final closed = row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(row.closedAt!.toLocal());
    final diffColor = row.difference.abs() < 0.01
        ? _cashMuted
        : row.difference > 0
        ? const Color(0xFF16A34A)
        : _danger;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330B1720),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: _cashBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _cashText,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Turno ${row.businessDate}',
                            style: const TextStyle(
                              color: _cashMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _cashLine),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _TurnDetailAmount(
                            label: 'Base inicial',
                            value: row.initialAmount,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TurnDetailAmount(
                            label: 'Efectivo esperado',
                            value: row.expectedAmount,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TurnDetailAmount(
                            label: 'Efectivo contado',
                            value: row.closingAmount,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: diffColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: diffColor.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Diferencia del turno',
                              style: TextStyle(
                                color: _cashText,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            formatRdCurrencyAccounting(row.difference),
                            style: TextStyle(
                              color: diffColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _TurnDetailLine(label: 'Estado', value: row.status),
                    _TurnDetailLine(label: 'Abrió', value: opened),
                    _TurnDetailLine(label: 'Cerró', value: closed),
                    _TurnDetailLine(label: 'ID turno', value: row.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnDetailAmount extends StatelessWidget {
  const _TurnDetailAmount({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cashLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _cashMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatRdCurrencyAccounting(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _cashText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnDetailLine extends StatelessWidget {
  const _TurnDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: _cashMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _cashText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnInfoBlock extends StatelessWidget {
  const _TurnInfoBlock({
    required this.title,
    required this.subtitle,
    this.color,
  });

  final String title;
  final String subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _cashMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? _cashText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySummaryBar extends StatelessWidget {
  const _HistorySummaryBar({
    required this.count,
    required this.total,
    required this.label,
  });

  final int count;
  final double total;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD7DD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count $label',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            formatRdCurrencyAccounting(total),
            style: const TextStyle(color: _danger, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return _CashCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: _cashBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _cashMuted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? _cashText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _cashBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _cashText,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _cashMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CashSearchField extends StatelessWidget {
  const _CashSearchField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: _inputDecoration(hint, icon: Icons.search_rounded),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _danger, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CashPanelMessage extends StatelessWidget {
  const _CashPanelMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

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
              child: Icon(icon, color: _cashBlue),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _cashText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _cashMuted, height: 1.35),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
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
        color: _cashSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cashLine),
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

InputDecoration _inputDecoration(
  String label, {
  String? hint,
  String? prefix,
  IconData? icon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefix,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _cashLine),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _cashLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _cashBlue, width: 1.6),
    ),
  );
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
