import 'dart:async';

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
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
import 'cash_dialogs.dart';
import 'cash_close_ticket_printer.dart';
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
              loading: () => const _CashPanelMessage(
                icon: Icons.point_of_sale_outlined,
                title: 'Caja',
                detail: 'Preparando datos del turno...',
              ),
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
  _MovementDateFilter _date = _MovementDateFilter.all;
  DateTime? _specificDate;
  String? _selectedMovementId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    // Refresco automático: la página obtiene nuevos movimientos por sí sola,
    // sin necesidad de pulsar "Actualizar" manualmente.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _autoRefresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _autoRefresh() {
    if (!mounted) return;
    ref.invalidate(cashMovementHistoryProvider);
  }

  int get _activeMovementFilterCount {
    var count = 0;
    if (_type != _MovementTypeFilter.all) count++;
    if (_date != _MovementDateFilter.all) count++;
    return count;
  }

  String get _movementFilterSummary {
    final typeLabel = _movementTypeLabel(_type);
    final dateLabel =
        _date == _MovementDateFilter.specific && _specificDate != null
        ? DateFormat('dd/MM/yyyy', 'es_DO').format(_specificDate!)
        : _movementDateLabel(_date);
    if (_type == _MovementTypeFilter.all && _date == _MovementDateFilter.all) {
      return 'Todos';
    }
    return '$typeLabel · $dateLabel';
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

  CashMovementModel? _selectedMovementFrom(List<CashMovementModel> rows) {
    if (rows.isEmpty) return null;
    final selectedId = (_selectedMovementId ?? '').trim();
    if (selectedId.isNotEmpty) {
      for (final row in rows) {
        if (row.id == selectedId) return row;
      }
    }
    return rows.first;
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

  Future<void> _openMovementFilters() async {
    final result = await showGeneralDialog<_CashMovementFilterDraft>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de movimientos',
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _CashMovementsFilterDrawer(
            initialType: _type,
            initialDate: _date,
            initialSpecificDate: _specificDate,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _type = result.type;
      _date = result.date;
      if (result.date == _MovementDateFilter.specific) {
        _specificDate = result.specificDate;
      }
    });
  }

  Widget _buildMovementsContent(
    BuildContext context,
    AsyncValue<List<CashMovementModel>> history, {
    required bool isMobile,
    required bool showStats,
    required EdgeInsetsGeometry listPadding,
  }) {
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
        if (visible.isEmpty) {
          return const _CashPanelMessage(
            icon: Icons.history_toggle_off_rounded,
            title: 'Sin movimientos',
            detail: 'No hay entradas ni salidas en el rango seleccionado.',
          );
        }
        return Column(
          children: [
            if (showStats) ...[
              _MovementStatsGrid(
                isMobile: isMobile,
                entries: entries,
                exits: exits,
                count: visible.length,
              ),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: ListView.separated(
                padding: listPadding,
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _CashMovementRow(row: visible[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopMovementsContent(
    BuildContext context,
    AsyncValue<List<CashMovementModel>> history,
  ) {
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
        final selected = _selectedMovementFrom(visible);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DesktopSalesPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildMovementToolbar(isMobile: false),
                    const SizedBox(height: 14),
                    _MovementStatsGrid(
                      isMobile: false,
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
                              padding: EdgeInsets.zero,
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final row = visible[index];
                                return _CashMovementRow(
                                  row: row,
                                  selected: selected?.id == row.id,
                                  onTap: () => setState(
                                    () => _selectedMovementId = row.id,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: (MediaQuery.sizeOf(context).width * 0.33).clamp(
                420.0,
                640.0,
              ),
              child: _CashMovementDetailColumn(
                row: selected,
                entries: entries,
                exits: exits,
                count: visible.length,
                refreshing: history.isLoading,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMovementToolbar({required bool isMobile}) {
    return Row(
      children: [
        Expanded(
          child: _CashSearchField(
            controller: _searchController,
            hint: isMobile
                ? 'Buscar movimientos...'
                : 'Buscar por usuario, motivo, monto o turno...',
          ),
        ),
        const SizedBox(width: 10),
        _MovementFilterButton(
          activeCount: _activeMovementFilterCount,
          summary: _movementFilterSummary,
          compact: isMobile,
          onPressed: _openMovementFilters,
        ),
      ],
    );
  }

  void _showMovementTotals(List<CashMovementModel> rows) {
    final entries = rows
        .where((row) => row.isIn)
        .fold<double>(0, (sum, row) => sum + row.amount);
    final exits = rows
        .where((row) => !row.isIn)
        .fold<double>(0, (sum, row) => sum + row.amount);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resumen',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _MovementStatsGrid(
                isMobile: true,
                entries: entries,
                exits: exits,
                count: rows.length,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final history = ref.watch(cashMovementHistoryProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final filteredForSummary = history.maybeWhen(
      data: _filter,
      orElse: () => const <CashMovementModel>[],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            ref.refresh(cashMovementHistoryProvider),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _cashBg,
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: isMobile
              ? CustomAppBar(
                  title: 'Movimientos',
                  showLogo: false,
                  showDepartmentLabel: false,
                  actions: [
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: () => ref.refresh(cashMovementHistoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                  trailing: const SizedBox.shrink(),
                )
              : FullTechPageHeader(
                  title: 'Movimiento de efectivo',
                  actions: [
                    IconButton.filledTonal(
                      tooltip: 'Actualizar',
                      onPressed: () => ref.refresh(cashMovementHistoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 10),
                    const CashTurnMenuButton(),
                    const SizedBox(width: 10),
                  ],
                ),
          floatingActionButton: isMobile
              ? FloatingActionButton(
                  heroTag: 'cash_movement_totals',
                  tooltip: 'Ver resumen',
                  onPressed: () => _showMovementTotals(filteredForSummary),
                  backgroundColor: _cashBlue,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.summarize_outlined),
                )
              : null,
          body: isMobile
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      _buildMovementToolbar(isMobile: true),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _buildMovementsContent(
                          context,
                          history,
                          isMobile: true,
                          showStats: false,
                          listPadding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
                        ),
                      ),
                    ],
                  ),
                )
              : DesktopSalesFrame(
                  child: _buildDesktopMovementsContent(context, history),
                ),
        ),
      ),
    );
  }
}

class _MovementFilterButton extends StatelessWidget {
  const _MovementFilterButton({
    required this.activeCount,
    required this.summary,
    required this.compact,
    required this.onPressed,
  });

  final int activeCount;
  final String summary;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeCount > 0;

    return Tooltip(
      message: 'Filtros',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: hasFilters,
          label: Text('$activeCount'),
          child: const Icon(Icons.tune_rounded, size: 20),
        ),
        label: compact
            ? const Text('Filtro')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtros'),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _cashMuted,
                    ),
                  ),
                ],
              ),
        style: OutlinedButton.styleFrom(
          foregroundColor: hasFilters ? _cashBlue : _cashText,
          backgroundColor: hasFilters ? const Color(0xFFEAF1FF) : Colors.white,
          side: BorderSide(
            color: hasFilters ? const Color(0xFF9FBCFF) : _cashLine,
          ),
          minimumSize: Size(compact ? 96 : 156, 48),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 0 : 6,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _CashMovementFilterDraft {
  const _CashMovementFilterDraft({
    required this.type,
    required this.date,
    this.specificDate,
  });

  final _MovementTypeFilter type;
  final _MovementDateFilter date;
  final DateTime? specificDate;
}

class _CashMovementsFilterDrawer extends StatefulWidget {
  const _CashMovementsFilterDrawer({
    required this.initialType,
    required this.initialDate,
    this.initialSpecificDate,
  });

  final _MovementTypeFilter initialType;
  final _MovementDateFilter initialDate;
  final DateTime? initialSpecificDate;

  @override
  State<_CashMovementsFilterDrawer> createState() =>
      _CashMovementsFilterDrawerState();
}

class _CashMovementsFilterDrawerState
    extends State<_CashMovementsFilterDrawer> {
  late _MovementTypeFilter _type;
  late _MovementDateFilter _date;
  DateTime? _specificDate;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _date = widget.initialDate;
    _specificDate = widget.initialSpecificDate;
  }

  Future<DateTime?> _pickSpecificDate() async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: _specificDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('es', 'DO'),
      helpText: 'Filtrar por fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
  }

  void _apply() {
    Navigator.of(context).pop(
      _CashMovementFilterDraft(
        type: _type,
        date: _date,
        specificDate: _specificDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final isMobile = media.width < 700;
    final width = isMobile
        ? media.width
        : (media.width * 0.34).clamp(360.0, 460.0);

    return Dismissible(
      key: const ValueKey('cash-movements-filters-panel'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Material(
        color: const Color(0xFFF8FBFF),
        elevation: 18,
        borderRadius: BorderRadius.zero,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: media.height,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isMobile ? 16 : 20, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCFE0FF)),
                        ),
                        child: const Icon(
                          Icons.filter_alt_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtros de movimientos',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tipo y rango de fechas',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
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
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 12 : 16,
                      14,
                      isMobile ? 12 : 16,
                      14,
                    ),
                    children: [
                      _CashFilterSection<_MovementTypeFilter>(
                        title: 'Tipo de movimiento',
                        subtitle: 'Filtra ingresos, salidas o ambos.',
                        value: _type,
                        options: const [
                          _MovementTypeFilter.all,
                          _MovementTypeFilter.inOnly,
                          _MovementTypeFilter.outOnly,
                        ],
                        labelBuilder: _movementTypeLabel,
                        onSelected: (value) => setState(() => _type = value),
                      ),
                      const SizedBox(height: 16),
                      _CashFilterSection<_MovementDateFilter>(
                        title: 'Rango de fecha',
                        subtitle: 'Elige el periodo que quieres revisar.',
                        value: _date,
                        options: const [
                          _MovementDateFilter.today,
                          _MovementDateFilter.yesterday,
                          _MovementDateFilter.week,
                          _MovementDateFilter.month,
                          _MovementDateFilter.specific,
                          _MovementDateFilter.all,
                        ],
                        labelBuilder: _movementDateLabel,
                        onSelected: (value) async {
                          if (value == _MovementDateFilter.specific) {
                            final picked = await _pickSpecificDate();
                            if (picked == null || !mounted) return;
                            setState(() {
                              _specificDate = picked;
                              _date = value;
                            });
                            return;
                          }
                          setState(() => _date = value);
                        },
                      ),
                      if (_date == _MovementDateFilter.specific)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickSpecificDate();
                              if (picked != null) {
                                setState(() => _specificDate = picked);
                              }
                            },
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(
                              _specificDate == null
                                  ? 'Elegir fecha'
                                  : DateFormat(
                                      'dd/MM/yyyy',
                                      'es_DO',
                                    ).format(_specificDate!),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 12 : 20,
                    12,
                    isMobile ? 12 : 20,
                    18,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceAlt,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(
                            const _CashMovementFilterDraft(
                              type: _MovementTypeFilter.all,
                              date: _MovementDateFilter.all,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: const Text('Limpiar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _apply,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Aplicar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                      ),
                    ],
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

class _CashFilterSection<T> extends StatelessWidget {
  const _CashFilterSection({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080B3550),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  for (var index = 0; index < options.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    Material(
                      color: optionEquals(options[index], value)
                          ? const Color(0xFFEAF1FF)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelected(options[index]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: optionEquals(options[index], value)
                                  ? const Color(0xFF9FBCFF)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                optionEquals(options[index], value)
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 19,
                                color: optionEquals(options[index], value)
                                    ? AppColors.secondary
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  labelBuilder(options[index]),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight:
                                        optionEquals(options[index], value)
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool optionEquals(T left, T right) => left == right;
}

String _movementTypeLabel(_MovementTypeFilter filter) {
  switch (filter) {
    case _MovementTypeFilter.all:
      return 'Todos';
    case _MovementTypeFilter.inOnly:
      return 'Entradas';
    case _MovementTypeFilter.outOnly:
      return 'Salidas';
  }
}

String _movementDateLabel(_MovementDateFilter filter) {
  switch (filter) {
    case _MovementDateFilter.today:
      return 'Hoy';
    case _MovementDateFilter.yesterday:
      return 'Ayer';
    case _MovementDateFilter.week:
      return 'Semana';
    case _MovementDateFilter.month:
      return 'Mes';
    case _MovementDateFilter.specific:
      return 'Fecha específica';
    case _MovementDateFilter.all:
      return 'Todo';
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

class CashTurnHistoryScreen extends ConsumerStatefulWidget {
  const CashTurnHistoryScreen({super.key});

  @override
  ConsumerState<CashTurnHistoryScreen> createState() =>
      _CashTurnHistoryScreenState();
}

class _CashTurnHistoryScreenState extends ConsumerState<CashTurnHistoryScreen> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  DateTimeRange? _selectedRange;
  _ShiftStatusFilter _statusFilter = _ShiftStatusFilter.all;

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

  List<CashSessionHistoryModel> _filterRows(
    List<CashSessionHistoryModel> rows,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    return rows
        .where((row) {
          final range = _selectedRange;
          if (range != null) {
            final rowDate =
                DateTime.tryParse(row.businessDate) ?? row.openedAt.toLocal();
            final rowDay = DateTime(rowDate.year, rowDate.month, rowDate.day);
            final start = DateTime(
              range.start.year,
              range.start.month,
              range.start.day,
            );
            final end = DateTime(
              range.end.year,
              range.end.month,
              range.end.day,
            );
            if (rowDay.isBefore(start) || rowDay.isAfter(end)) {
              return false;
            }
          }
          if (_statusFilter == _ShiftStatusFilter.open &&
              row.status.toUpperCase() != 'OPEN') {
            return false;
          }
          if (_statusFilter == _ShiftStatusFilter.closed &&
              row.status.toUpperCase() == 'OPEN') {
            return false;
          }
          if (query.isEmpty) return true;
          final haystack = [
            row.userName,
            row.businessDate,
            row.status,
            row.expectedAmount.toStringAsFixed(2),
            row.closingAmount.toStringAsFixed(2),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  String get _rangeLabel {
    final range = _selectedRange;
    if (range == null) return 'Todos';
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final yesterday = todayDay.subtract(const Duration(days: 1));
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    if (start == todayDay && end == todayDay) return 'Hoy';
    if (start == yesterday && end == yesterday) return 'Ayer';
    final fmt = DateFormat('dd/MM', 'es_DO');
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }

  Future<void> _openDateFilter() async {
    final next = await showGeneralDialog<_ShiftHistoryFilterDraft>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de turnos',
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _ShiftHistoryFilterDrawer(
            initialRange: _selectedRange,
            initialStatus: _statusFilter,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
    if (next == null || !mounted) return;
    setState(() {
      _selectedRange = next.range;
      _statusFilter = next.status;
    });
  }

  Widget _buildAppBarSearchField() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: 'Buscar',
            hintStyle: const TextStyle(color: Color(0xFF8A9AA8)),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF52667C),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final history = ref.watch(cashTurnHistoryProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      backgroundColor: _cashBg,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: isMobile
          ? CustomAppBar(
              title: 'Historial',
              titleWidget: _searchOpen ? _buildAppBarSearchField() : null,
              showLogo: false,
              showDepartmentLabel: false,
              actions: [
                IconButton(
                  tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchController.clear();
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                if (!_searchOpen)
                  IconButton(
                    tooltip: 'Filtrar por día',
                    onPressed: () {
                      _openDateFilter();
                    },
                    icon: Badge(
                      isLabelVisible:
                          _selectedRange != null ||
                          _statusFilter != _ShiftStatusFilter.all,
                      smallSize: 8,
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                  ),
                if (!_searchOpen)
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: () => ref.invalidate(cashTurnHistoryProvider),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
              trailing: const SizedBox.shrink(),
            )
          : const FullTechPageHeader(
              title: 'Historial',
              actions: [CashTurnMenuButton(), SizedBox(width: 10)],
            ),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 10 : 18),
        child: history.when(
          loading: () => const _CashCard(
            child: _CashPanelMessage(
              icon: Icons.history_rounded,
              title: 'Historial',
              detail: 'Sincronizando turnos...',
            ),
          ),
          error: (error, _) => _CashCard(
            child: _CashPanelMessage(
              icon: Icons.history_toggle_off_rounded,
              title: 'No se pudo cargar historial',
              detail: resolveCashError(error),
            ),
          ),
          data: (rows) {
            final visibleRows = _filterRows(rows);
            final totalExpected = visibleRows.fold<double>(
              0,
              (sum, row) => sum + row.expectedAmount,
            );
            final totalDiff = visibleRows.fold<double>(
              0,
              (sum, row) => sum + row.difference,
            );
            return Column(
              children: [
                if (!isMobile) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.history_rounded,
                          label: 'Turnos cerrados',
                          value: visibleRows.length.toString(),
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
                        onPressed: () =>
                            ref.invalidate(cashTurnHistoryProvider),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (isMobile && _selectedRange != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text(_rangeLabel),
                      avatar: const Icon(Icons.calendar_today_outlined),
                      onDeleted: () => setState(() => _selectedRange = null),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: visibleRows.isEmpty
                      ? const _CashPanelMessage(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'Sin turnos cerrados',
                          detail:
                              'Cuando cierres turnos de caja aparecerán aquí.',
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: visibleRows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _TurnHistoryWideCard(row: visibleRows[index]),
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

enum _ShiftStatusFilter { all, open, closed }

class _ShiftHistoryFilterDraft {
  const _ShiftHistoryFilterDraft({required this.range, required this.status});

  final DateTimeRange? range;
  final _ShiftStatusFilter status;
}

class _ShiftHistoryFilterDrawer extends StatefulWidget {
  const _ShiftHistoryFilterDrawer({
    required this.initialRange,
    required this.initialStatus,
  });

  final DateTimeRange? initialRange;
  final _ShiftStatusFilter initialStatus;

  @override
  State<_ShiftHistoryFilterDrawer> createState() =>
      _ShiftHistoryFilterDrawerState();
}

class _ShiftHistoryFilterDrawerState extends State<_ShiftHistoryFilterDrawer> {
  late DateTimeRange? _range = widget.initialRange;
  late _ShiftStatusFilter _status = widget.initialStatus;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickRange() async {
    final today = _today;
    final next = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 1),
      initialDateRange: _range ?? DateTimeRange(start: today, end: today),
      locale: const Locale('es', 'DO'),
      helpText: 'Intervalo',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (next == null || !mounted) return;
    setState(() => _range = next);
  }

  void _apply() {
    Navigator.of(
      context,
    ).pop(_ShiftHistoryFilterDraft(range: _range, status: _status));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 390 ? width * 0.90 : width * 0.84;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final fmt = DateFormat('dd/MM/yyyy', 'es_DO');
    final today = _today;
    final yesterday = today.subtract(const Duration(days: 1));

    return SafeArea(
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        child: SizedBox(
          width: panelWidth.clamp(286.0, 360.0),
          height: double.infinity,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.secondarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.filter_alt_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtros',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Historial de turnos',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  children: [
                    const _FilterSectionLabel('Fecha'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterPill(
                          label: 'Hoy',
                          selected:
                              _range?.start == today && _range?.end == today,
                          onTap: () => setState(
                            () => _range = DateTimeRange(
                              start: today,
                              end: today,
                            ),
                          ),
                        ),
                        _FilterPill(
                          label: 'Ayer',
                          selected:
                              _range?.start == yesterday &&
                              _range?.end == yesterday,
                          onTap: () => setState(
                            () => _range = DateTimeRange(
                              start: yesterday,
                              end: yesterday,
                            ),
                          ),
                        ),
                        _FilterPill(
                          label: 'Todos',
                          selected: _range == null,
                          onTap: () => setState(() => _range = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_rounded, size: 18),
                      label: Text(
                        _range == null
                            ? 'Personalizado'
                            : '${fmt.format(_range!.start)} - ${fmt.format(_range!.end)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _FilterSectionLabel('Estado'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FilterPill(
                          label: 'Todos',
                          selected: _status == _ShiftStatusFilter.all,
                          onTap: () =>
                              setState(() => _status = _ShiftStatusFilter.all),
                        ),
                        _FilterPill(
                          label: 'Abiertos',
                          selected: _status == _ShiftStatusFilter.open,
                          onTap: () =>
                              setState(() => _status = _ShiftStatusFilter.open),
                        ),
                        _FilterPill(
                          label: 'Cerrados',
                          selected: _status == _ShiftStatusFilter.closed,
                          onTap: () => setState(
                            () => _status = _ShiftStatusFilter.closed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + safeBottom),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          const _ShiftHistoryFilterDraft(
                            range: null,
                            status: _ShiftStatusFilter.all,
                          ),
                        ),
                        child: const Text('Limpiar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _apply,
                        child: const Text('Aplicar'),
                      ),
                    ),
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

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceMuted,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.borderStrong,
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
              loading: () => const _CashPanelMessage(
                icon: Icons.receipt_long_outlined,
                title: 'Gastos recientes',
                detail: 'Sincronizando historial...',
              ),
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
  const _CashMovementRow({
    required this.row,
    this.selected = false,
    this.onTap,
  });

  final CashMovementModel row;
  final bool selected;
  final VoidCallback? onTap;

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
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 14,
        vertical: isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 8 : 8),
        border: Border.all(
          color: selected ? desktopSalesAccent : const Color(0xFFDDE7EE),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: isMobile
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x080B3550),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: InkWell(
        onTap: onTap,
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
                  Container(
                    width: 4,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatRdCurrencyAccounting(row.amount),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CashMovementDetailColumn extends StatelessWidget {
  const _CashMovementDetailColumn({
    required this.row,
    required this.entries,
    required this.exits,
    required this.count,
    required this.refreshing,
  });

  final CashMovementModel? row;
  final double entries;
  final double exits;
  final int count;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final selected = row;
    final isIn = selected?.isIn ?? true;
    final accent = isIn ? _cashBlue : _danger;

    return DesktopSalesPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected == null
                        ? 'Detalle'
                        : (selected.reason.trim().isEmpty
                              ? (isIn ? 'Ingreso' : 'Salida')
                              : selected.reason.trim()),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: desktopSalesText,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _MovementTypePill(
                  label: selected == null
                      ? (refreshing ? 'Cargando' : 'Lista')
                      : isIn
                      ? 'Entrada'
                      : 'Salida',
                  color: selected == null ? desktopSalesAccent : accent,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: desktopSalesLine),
          Expanded(
            child: selected == null
                ? const _CashPanelMessage(
                    icon: Icons.payments_outlined,
                    title: 'Selecciona un movimiento',
                    detail: 'El detalle aparecerá fijo en esta columna.',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CashDetailAmount(
                          label: isIn ? 'Monto entrada' : 'Monto salida',
                          value: formatRdCurrencyAccounting(selected.amount),
                          color: accent,
                        ),
                        const SizedBox(height: 20),
                        _CashDetailLine(
                          label: 'Fecha',
                          value: DateFormat(
                            'dd/MM/yyyy HH:mm',
                            'es_DO',
                          ).format(selected.createdAt.toLocal()),
                        ),
                        _CashDetailLine(
                          label: 'Usuario',
                          value: selected.userName ?? 'Usuario',
                        ),
                        _CashDetailLine(
                          label: 'Turno',
                          value: selected.businessDate ?? 'Actual',
                        ),
                        _CashDetailLine(
                          label: 'Tipo',
                          value: selected.movementType,
                        ),
                        _CashDetailLine(
                          label: 'Afecta ganancia',
                          value: selected.affectsProfit ? 'Si' : 'No',
                        ),
                        _CashDetailLine(
                          label: 'Estado turno',
                          value: selected.sessionStatus ?? 'Sin estado',
                        ),
                      ],
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: const BoxDecoration(
              color: Color(0xFFF7FAFC),
              border: Border(top: BorderSide(color: desktopSalesLine)),
            ),
            child: Column(
              children: [
                _CashDetailTotalRow(label: 'Movimientos', value: '$count'),
                _CashDetailTotalRow(
                  label: 'Entradas',
                  value: formatRdCurrencyAccounting(entries),
                ),
                _CashDetailTotalRow(
                  label: 'Salidas',
                  value: formatRdCurrencyAccounting(exits),
                ),
                const Divider(height: 18, color: desktopSalesLine),
                _CashDetailTotalRow(
                  label: 'Neto vigente',
                  value: formatRdCurrencyAccounting(entries - exits),
                  strong: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashDetailAmount extends StatelessWidget {
  const _CashDetailAmount({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: desktopSalesMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashDetailLine extends StatelessWidget {
  const _CashDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(
                color: desktopSalesMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: desktopSalesText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashDetailTotalRow extends StatelessWidget {
  const _CashDetailTotalRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? desktopSalesText : desktopSalesMuted,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: desktopSalesText,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
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
    if (MediaQuery.sizeOf(context).width < 700) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => _ShiftDetailPage(row: row)),
      );
    }
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (context) => _TurnDetailDialog(row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
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

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(10, isMobile ? 9 : 10, 10, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
            border: Border.all(color: const Color(0xFFDDE8F1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x070B3550),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            color: _cashBlue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TurnInfoBlock(
                            title: row.userName,
                            subtitle: 'Turno ${row.businessDate}',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _showDetail(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _cashBlue,
                            side: const BorderSide(color: Color(0xFFC7D8FF)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Ver'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _TurnMiniPill(label: 'Abrió', value: opened),
                        _TurnMiniPill(label: 'Cerró', value: closed),
                        _TurnMiniPill(
                          label: 'Esperado',
                          value: formatRdCurrencyAccounting(row.expectedAmount),
                        ),
                        _TurnMiniPill(
                          label: 'Diferencia',
                          value: formatRdCurrencyAccounting(row.difference),
                          color: diffColor,
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: _cashBlue,
                      ),
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
                        subtitle: formatRdCurrencyAccounting(
                          row.expectedAmount,
                        ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TurnMiniPill extends StatelessWidget {
  const _TurnMiniPill({
    required this.label,
    required this.value,
    this.color = _cashText,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cashLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _cashMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
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

class _ShiftDetailPage extends ConsumerWidget {
  const _ShiftDetailPage({required this.row});

  final CashSessionHistoryModel row;

  Future<void> _print(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(cashCloseTicketPrinterProvider)
          .printHistoryTicket(row);
      if (!context.mounted) return;
      showCashToast(
        context,
        result.success ? 'Turno enviado a imprimir' : result.message,
        isError: !result.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      showCashToast(context, 'No se pudo imprimir: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_DO');
    final opened = fmt.format(row.openedAt.toLocal());
    final closed = row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(row.closedAt!.toLocal());
    final diffColor = row.difference.abs() < 0.01
        ? _cashBlue
        : row.difference > 0
        ? const Color(0xFF16A34A)
        : _danger;

    return Scaffold(
      backgroundColor: _cashBg,
      appBar: CustomAppBar(
        title: 'Detalle',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Imprimir turno',
            onPressed: () => _print(context, ref),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
        trailing: const SizedBox.shrink(),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            18 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _cashLine),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.secondarySoft,
                      borderRadius: BorderRadius.circular(11),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: _cashText,
                          ),
                        ),
                        Text(
                          'Turno ${row.businessDate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _cashMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: row.status),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _ShiftDetailSection(
              title: 'Resumen',
              children: [
                _TurnDetailLine(
                  label: 'Base inicial',
                  value: formatRdCurrencyAccounting(row.initialAmount),
                ),
                _TurnDetailLine(
                  label: 'Efectivo esperado',
                  value: formatRdCurrencyAccounting(row.expectedAmount),
                ),
                _TurnDetailLine(
                  label: 'Efectivo contado',
                  value: formatRdCurrencyAccounting(row.closingAmount),
                ),
                _TurnDetailLine(
                  label: 'Diferencia',
                  value: formatRdCurrencyAccounting(row.difference),
                  color: diffColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ShiftDetailSection(
              title: 'Tiempos',
              children: [
                _TurnDetailLine(label: 'Apertura', value: opened),
                _TurnDetailLine(label: 'Cierre', value: closed),
                _TurnDetailLine(label: 'Día negocio', value: row.businessDate),
              ],
            ),
            const SizedBox(height: 10),
            _ShiftDetailSection(
              title: 'Auditoría',
              children: [
                _TurnDetailLine(label: 'Estado', value: row.status),
                _TurnDetailLine(label: 'ID turno', value: row.id),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftDetailSection extends StatelessWidget {
  const _ShiftDetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cashLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _cashText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final open = status.toUpperCase() == 'OPEN';
    final color = open ? const Color(0xFF16A34A) : _cashBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        open ? 'Abierto' : 'Cerrado',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
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
  const _TurnDetailLine({
    required this.label,
    required this.value,
    this.color = _cashText,
  });

  final String label;
  final String value;
  final Color color;

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
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
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
