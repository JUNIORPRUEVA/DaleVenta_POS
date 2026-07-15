import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/ventas_controller.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';
import 'utils/sales_pdf_service.dart';

class MisVentasScreen extends ConsumerStatefulWidget {
  const MisVentasScreen({super.key});

  @override
  ConsumerState<MisVentasScreen> createState() => _MisVentasScreenState();
}

class _MisVentasScreenState extends ConsumerState<MisVentasScreen> {
  bool _purgingAllDebug = false;
  String? _lastRouteCustomerId;
  String? _lastRouteCustomerName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRouteCustomerFilter();
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1180;

  String _money(double value) => formatRdCurrencyAccounting(value);
  String _date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String _quincenaName(DateTime from, DateTime to) {
    if (from.day == 15) return '1ra quincena';
    if (to.day == 14) return '2da quincena';
    return 'Rango personalizado';
  }

  String _quincenaLabel(DateTime from, DateTime to) {
    return '${_quincenaName(from, to)} · ${_date(from)} - ${_date(to)}';
  }

  void _syncRouteCustomerFilter() {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final nextCustomerId = (qp['customerId'] ?? '').trim();
    final nextCustomerName = (qp['customerName'] ?? '').trim();
    final normalizedCustomerId = nextCustomerId.isEmpty ? null : nextCustomerId;
    final normalizedCustomerName = nextCustomerName.isEmpty
        ? null
        : nextCustomerName;

    if (_lastRouteCustomerId == normalizedCustomerId &&
        _lastRouteCustomerName == normalizedCustomerName) {
      return;
    }

    _lastRouteCustomerId = normalizedCustomerId;
    _lastRouteCustomerName = normalizedCustomerName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(ventasControllerProvider.notifier)
          .setCustomerFilter(normalizedCustomerId);
      setState(() {});
    });
  }

  Widget _buildCustomerFilterBanner(VentasState state) {
    final customerId = state.customerIdFilter;
    if (customerId == null || customerId.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final customerName = (_lastRouteCustomerName ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              customerName.isEmpty
                  ? 'Ventas filtradas por cliente'
                  : 'Ventas de $customerName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go(Routes.ventas),
            child: const Text('Quitar filtro'),
          ),
        ],
      ),
    );
  }

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'ventas',
      impactLabel: 'todas las ventas registradas en este módulo',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(ventasControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Se limpiaron $deleted ventas.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ventasControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final isDesktop = _isDesktop(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Mis Ventas',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          DebugAdminActionButton(
            user: user,
            busy: _purgingAllDebug,
            tooltip: 'Limpiar tabla (debug)',
            onPressed: _purgeAllDebug,
          ),
          IconButton(
            tooltip: 'Actualizar ventas',
            onPressed: () {
              ref.read(ventasControllerProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Informe PDF de quincena',
            onPressed: () async {
              await _openPdfPreviewDialog(
                context,
                employeeName: user?.nombreCompleto ?? user?.email ?? 'Empleado',
                state: state,
              );
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: null,
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openSalesHistoryDialog(context, state),
                      icon: const Icon(Icons.history),
                      label: const Text('Historial'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openRegisterSale,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Registrar'),
                    ),
                  ),
                ],
              ),
            ),
      body: isDesktop
          ? _buildDesktopBody(state, user?.nombreCompleto ?? user?.email)
          : _buildMobileBody(state),
    );
  }

  Future<void> _openRegisterSale() async {
    final created = await context.push<bool>(Routes.registrarVenta);
    if (created == true) {
      await ref.read(ventasControllerProvider.notifier).refresh();
    }
  }

  List<_SalesDayPoint> _salesDayPoints(VentasState state) {
    final totalsByDay = <DateTime, double>{};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      final day = DateTime(date.year, date.month, date.day);
      totalsByDay.update(
        day,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    final points =
        totalsByDay.entries
            .map((entry) => _SalesDayPoint(day: entry.key, total: entry.value))
            .toList(growable: false)
          ..sort((a, b) => a.day.compareTo(b.day));

    if (points.length <= 7) return points;
    return points.sublist(points.length - 7);
  }

  List<_TopProductStat> _topProducts(VentasState state) {
    final totals = <String, double>{};
    for (final sale in state.sales) {
      for (final item in sale.items) {
        final key = item.productNameSnapshot.trim();
        if (key.isEmpty) continue;
        totals.update(
          key,
          (value) => value + item.qty,
          ifAbsent: () => item.qty,
        );
      }
    }

    final rows =
        totals.entries
            .map(
              (entry) =>
                  _TopProductStat(name: entry.key, quantity: entry.value),
            )
            .toList(growable: false)
          ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return rows.take(8).toList(growable: false);
  }

  List<_SalesWeekdayStat> _salesWeekdayStats(VentasState state) {
    final totals = <int, double>{for (var day = 1; day <= 7; day++) day: 0};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      totals.update(
        date.weekday,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    return List.generate(
      7,
      (index) => _SalesWeekdayStat(
        weekday: index + 1,
        label: _weekdayShortLabel(index + 1),
        total: totals[index + 1] ?? 0,
      ),
      growable: false,
    );
  }

  String _weekdayShortLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lun';
      case DateTime.tuesday:
        return 'Mar';
      case DateTime.wednesday:
        return 'Mie';
      case DateTime.thursday:
        return 'Jue';
      case DateTime.friday:
        return 'Vie';
      case DateTime.saturday:
        return 'Sab';
      case DateTime.sunday:
        return 'Dom';
    }
    return '';
  }

  String _moneyCompact(double value) => formatRdCurrencyAccounting(value);

  Widget _buildDesktopBody(VentasState state, String? employeeName) {
    final averageTicket = state.summary.totalSales == 0
        ? 0.0
        : state.summary.totalSold / state.summary.totalSales;
    final bestSale = state.sales.isEmpty
        ? null
        : (state.sales.toList()
                ..sort((a, b) => b.totalSold.compareTo(a.totalSold)))
              .first;
    final daysWithSales = state.sales
        .map(
          (sale) =>
              DateFormat('yyyy-MM-dd').format(sale.saleDate ?? DateTime.now()),
        )
        .toSet()
        .length;
    final dayPoints = _salesDayPoints(state);
    final weekdayStats = _salesWeekdayStats(state);
    final topProducts = _topProducts(state);
    final bestDay = dayPoints.isEmpty
        ? null
        : (dayPoints.toList()..sort((a, b) => b.total.compareTo(a.total)))
              .first;
    final averageDailySales = dayPoints.isEmpty
        ? 0.0
        : state.summary.totalSold / dayPoints.length;
    final strongestWeekday = weekdayStats
        .where((item) => item.total > 0)
        .fold<_SalesWeekdayStat?>(null, (current, item) {
          if (current == null || item.total > current.total) return item;
          return current;
        });
    final metricItems = [
      _DesktopMetricData(
        title: 'Ventas registradas',
        value: state.summary.totalSales.toString(),
        subtitle: 'Ventas en el rango activo',
        icon: Icons.receipt_long_outlined,
      ),
      _DesktopMetricData(
        title: 'Ticket promedio',
        value: _money(averageTicket),
        subtitle: 'Valor medio por venta',
        icon: Icons.leaderboard_outlined,
      ),
      _DesktopMetricData(
        title: 'Dias con ventas',
        value: daysWithSales.toString(),
        subtitle: 'Dias con actividad comercial',
        icon: Icons.calendar_month_outlined,
      ),
      _DesktopMetricData(
        title: 'Mejor venta',
        value: bestSale == null ? _money(0) : _money(bestSale.totalSold),
        subtitle: bestSale == null
            ? 'Sin registros todavia'
            : (bestSale.customerName ?? 'Sin cliente'),
        icon: Icons.emoji_events_outlined,
      ),
    ];

    return RefreshIndicator(
      onRefresh: () => ref.read(ventasControllerProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final useTwoColumns = width >= 1180;
          final gap = width >= 1560 ? 20.0 : 16.0;
          final horizontalPadding = width >= 1560 ? 24.0 : 18.0;
          final maxContentWidth = width >= 1760 ? 1680.0 : 1540.0;
          final leftColumnWidth = width >= 1500
              ? 390.0
              : width >= 1280
              ? 370.0
              : 350.0;
          final header = _StatsHeader(
            rangeLabel: _quincenaLabel(state.from, state.to),
            totalSales: state.summary.totalSales.toString(),
            totalSold: _money(state.summary.totalSold),
            onRegisterSale: _openRegisterSale,
            onOpenHistory: () => _openSalesHistoryDialog(context, state),
            onOpenPdf: () => _openPdfPreviewDialog(
              context,
              employeeName: employeeName ?? 'Empleado',
              state: state,
            ),
          );

          if (useTwoColumns) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.customerIdFilter != null) ...[
                        _buildCustomerFilterBanner(state),
                        SizedBox(height: gap),
                      ],
                      header,
                      SizedBox(height: gap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: leftColumnWidth,
                              child: _StatsCards(
                                rangeLabel: _quincenaLabel(
                                  state.from,
                                  state.to,
                                ),
                                items: metricItems,
                                totalSales: state.summary.totalSales,
                                totalSold: state.summary.totalSold,
                                money: _money,
                              ),
                            ),
                            SizedBox(width: gap),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SalesSummary(
                                      state: state,
                                      dayPoints: dayPoints,
                                      weekdayStats: weekdayStats,
                                      topProducts: topProducts,
                                      bestDay: bestDay,
                                      strongestWeekday: strongestWeekday,
                                      averageDailySales: averageDailySales,
                                      money: _money,
                                      compactMoney: _moneyCompact,
                                    ),
                                  ],
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
            );
          }

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  maxWidth: maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.customerIdFilter != null) ...[
                      _buildCustomerFilterBanner(state),
                      SizedBox(height: gap),
                    ],
                    header,
                    SizedBox(height: gap),
                    _StatsCards(
                      rangeLabel: _quincenaLabel(state.from, state.to),
                      items: metricItems,
                      totalSales: state.summary.totalSales,
                      totalSold: state.summary.totalSold,
                      money: _money,
                    ),
                    SizedBox(height: gap),
                    _SalesSummary(
                      state: state,
                      dayPoints: dayPoints,
                      weekdayStats: weekdayStats,
                      topProducts: topProducts,
                      bestDay: bestDay,
                      strongestWeekday: strongestWeekday,
                      averageDailySales: averageDailySales,
                      money: _money,
                      compactMoney: _moneyCompact,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileBody(VentasState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.customerIdFilter != null) ...[
                _buildCustomerFilterBanner(state),
                const SizedBox(height: 8),
              ],
              if (state.loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              if (state.error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildCurrentQuincenaCard(state, compact: true),
              const SizedBox(height: 10),
              Expanded(
                child: state.sales.isEmpty && !state.loading
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.receipt_long_outlined, size: 44),
                              const SizedBox(height: 8),
                              Text(
                                'No hay ventas registradas en ${_quincenaLabel(state.from, state.to)}',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildSalesByDayStats(state, compact: true, maxItems: 4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentQuincenaCard(VentasState state, {bool compact = false}) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quincena activa',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _quincenaLabel(state.from, state.to),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
            ),
            SizedBox(height: compact ? 8 : 10),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Total vendido',
                    _money(state.summary.totalSold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniMetric(
                    'Cantidad',
                    state.summary.totalSales.toString(),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 10,
                vertical: compact ? 8 : 9,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Resumen directo de ventas registradas en el rango activo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                      maxLines: compact ? 2 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                    ),
                  ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                'Vista rapida del rango activo con cantidad de ventas y total vendido.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildSalesByDayStats(
    VentasState state, {
    bool compact = false,
    int maxItems = 6,
  }) {
    final totalsByDay = <String, double>{};
    for (final sale in state.sales) {
      final date = sale.saleDate ?? DateTime.now();
      final key = DateFormat('dd/MM').format(date);
      totalsByDay.update(
        key,
        (value) => value + sale.totalSold,
        ifAbsent: () => sale.totalSold,
      );
    }

    final entries = totalsByDay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(maxItems).toList();
    final maxValue = top.isEmpty ? 1.0 : top.first.value;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Ventas por día',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (top.isEmpty)
              Text(
                'Aún no hay datos para estadísticas de días.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Expanded(
                child: Column(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.spaceEvenly
                      : MainAxisAlignment.start,
                  children: top
                      .map((entry) {
                        final ratio = (entry.value / maxValue).clamp(0.0, 1.0);
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 2 : 4,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: compact ? 42 : 48,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(value: ratio),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: compact ? 82 : 90,
                                child: Text(
                                  compact
                                      ? _moneyCompact(entry.value)
                                      : _money(entry.value),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, SaleModel sale) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final saleDate = sale.saleDate ?? DateTime.now();
        return AlertDialog(
          title: const Text('Detalle de venta'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Encabezado compacto ──
                  Text(
                    sale.customerName?.trim().isNotEmpty == true
                        ? sale.customerName!
                        : 'Sin cliente',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _date(saleDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((sale.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sale.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const Divider(height: 14),
                  // ── Items ──
                  ...sale.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productNameSnapshot} x${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          _money(item.subtotalSold),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )),
                  const Divider(height: 14),
                  // ── Total a Cobrar ──
                  Row(
                    children: [
                      Text(
                        'Cobrar',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _money(sale.totalSold),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSale(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: const Text(
          'Esta acción ocultará la venta del historial. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ref.read(ventasControllerProvider.notifier).deleteSale(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Venta eliminada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Future<void> _openPdfPreviewDialog(
    BuildContext context, {
    required String employeeName,
    required VentasState state,
  }) async {
    final pdfBytes = await buildSalesSummaryPdf(
      employeeName: employeeName,
      from: state.from,
      to: state.to,
      summary: state.summary,
      sales: state.sales,
    );

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final media = MediaQuery.sizeOf(context);
        final isCompact = media.width < 520;
        return Dialog(
          insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
          child: SizedBox(
            width: isCompact ? media.width - 16 : 920,
            height: isCompact ? media.height * 0.92 : 760,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isCompact ? 10 : 14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Informe PDF de ventas · ${_quincenaName(state.from, state.to)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 14 : 16,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await downloadSalesSummaryPdf(
                            bytes: pdfBytes,
                            from: state.from,
                            to: state.to,
                          );
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: Text(isCompact ? 'Bajar' : 'Descargar'),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: true,
                    build: (_) async => pdfBytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSalesHistoryDialog(
    BuildContext context,
    VentasState currentState,
  ) async {
    final repo = ref.read(ventasRepositoryProvider);
    DateTime from = currentState.from;
    DateTime to = currentState.to;
    List<SaleModel> items = const [];
    bool loading = false;
    String? error;
    bool initialized = false;

    Future<void> load(StateSetter setStateDialog) async {
      setStateDialog(() {
        loading = true;
        error = null;
      });
      try {
        final rows = await repo.listSales(from: from, to: to);
        if (!context.mounted) return;
        setStateDialog(() {
          items = rows;
          loading = false;
        });
      } catch (e) {
        if (!context.mounted) return;
        setStateDialog(() {
          loading = false;
          error = '$e';
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (!initialized) {
            initialized = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => load(setStateDialog),
            );
          }

          final media = MediaQuery.sizeOf(context);
          final isCompact = media.width < 560;
          final filteredCount = items.length;
          final filteredSold = items.fold<double>(
            0,
            (sum, sale) => sum + sale.totalSold,
          );
          final scheme = Theme.of(context).colorScheme;

          return Dialog(
            insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
            child: SizedBox(
              width: isCompact ? media.width - 16 : 760,
              height: isCompact ? media.height * 0.92 : 560,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Historial de ventas',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quincena visible: ${_quincenaLabel(from, to)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(
                              width: isCompact ? 165 : 200,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: from,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked == null) return;
                                  setStateDialog(
                                    () => from = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.event),
                                label: Text('Desde ${_date(from)}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: isCompact ? 165 : 200,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: to,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked == null) return;
                                  setStateDialog(
                                    () => to = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.event_available),
                                label: Text('Hasta ${_date(to)}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: isCompact ? 120 : 130,
                              child: FilledButton.icon(
                                onPressed: loading
                                    ? null
                                    : () => load(setStateDialog),
                                icon: const Icon(Icons.filter_alt_outlined),
                                label: const Text('Filtrar'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Cantidad: $filteredCount',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text('Vendido: ${_money(filteredSold)}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (loading) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: items.isEmpty && !loading
                          ? const Center(
                              child: Text('No hay ventas en este rango'),
                            )
                          : ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final sale = items[index];
                                return ListTile(
                                  onTap: () =>
                                      _showDetailsDialog(context, sale),
                                  title: Text(
                                    '${_date(sale.saleDate ?? DateTime.now())} · ${sale.customerName ?? 'Sin cliente'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Vendido ${_money(sale.totalSold)}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Ver detalle',
                                        onPressed: () =>
                                            _showDetailsDialog(context, sale),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        onPressed: () =>
                                            _deleteSale(context, sale.id),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.rangeLabel,
    required this.totalSales,
    required this.totalSold,
    required this.onRegisterSale,
    required this.onOpenHistory,
    required this.onOpenPdf,
  });

  final String rangeLabel;
  final String totalSales;
  final String totalSold;
  final VoidCallback onRegisterSale;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stacked = width < 1120;
        final statsColumns = width >= 1240
            ? 3
            : width >= 860
            ? 2
            : 1;
        final statsWidth = stacked ? width : (width - 236).clamp(0.0, width);
        final chipWidth = statsColumns == 1
            ? width
            : ((statsWidth - (10 * (statsColumns - 1))) / statsColumns)
                  .clamp(180.0, 240.0)
                  .toDouble();
        final actionWidth = stacked
            ? ((width - 10) / 2).clamp(180.0, 260.0).toDouble()
            : 220.0;

        final statsChips = [
          SizedBox(
            width: chipWidth,
            child: _StatsHeaderChip(
              icon: Icons.event_note_outlined,
              label: 'Rango',
              value: rangeLabel,
            ),
          ),
          SizedBox(
            width: chipWidth,
            child: _StatsHeaderChip(
              icon: Icons.payments_outlined,
              label: 'Vendido',
              value: totalSold,
            ),
          ),
          SizedBox(
            width: chipWidth,
            child: _StatsHeaderChip(
              icon: Icons.receipt_long_outlined,
              label: 'Ventas',
              value: totalSales,
            ),
          ),
        ];

        final actions = stacked
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onRegisterSale,
                    filled: true,
                    icon: Icons.add_shopping_cart,
                    label: 'Registrar venta',
                  ),
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onOpenHistory,
                    icon: Icons.history,
                    label: 'Historial',
                  ),
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onOpenPdf,
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Exportar PDF',
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onRegisterSale,
                    filled: true,
                    icon: Icons.add_shopping_cart,
                    label: 'Registrar venta',
                  ),
                  const SizedBox(height: 10),
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onOpenHistory,
                    icon: Icons.history,
                    label: 'Historial',
                  ),
                  const SizedBox(height: 10),
                  _HeaderActionButton(
                    width: actionWidth,
                    onPressed: onOpenPdf,
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Exportar PDF',
                  ),
                ],
              );

        return Container(
          padding: EdgeInsets.all(width < 900 ? 16 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1D4ED8), Color(0xFF0F172A)],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 10, runSpacing: 10, children: statsChips),
                    const SizedBox(height: 16),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: statsChips,
                      ),
                    ),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
        );
      },
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.width,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final double width;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            ),
          );

    return SizedBox(width: width, child: button);
  }
}

class _StatsHeaderChip extends StatelessWidget {
  const _StatsHeaderChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

class _StatsCards extends StatelessWidget {
  const _StatsCards({
    required this.rangeLabel,
    required this.items,
    required this.totalSales,
    required this.totalSold,
    required this.money,
  });

  final String rangeLabel;
  final List<_DesktopMetricData> items;
  final int totalSales;
  final double totalSold;
  final String Function(double value) money;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final spacing = 16.0;
        final singleColumn = width < 520;
        final cardWidth = singleColumn ? width : (width - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _RangeOverviewCard(
                rangeLabel: rangeLabel,
                totalSales: totalSales,
                totalSold: totalSold,
                money: money,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricPanel(items: items),
            ),
          ],
        );
      },
    );
  }
}

class _RangeOverviewCard extends StatelessWidget {
  const _RangeOverviewCard({
    required this.rangeLabel,
    required this.totalSales,
    required this.totalSold,
    required this.money,
  });

  final String rangeLabel;
  final int totalSales;
  final double totalSold;
  final String Function(double value) money;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.insights_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Panorama del periodo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rangeLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width < 340 ? width : (width - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _InfoMiniStat(
                      label: 'Total vendido',
                      value: money(totalSold),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _InfoMiniStat(
                      label: 'Ventas registradas',
                      value: totalSales.toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Este bloque resume los valores clave del rango visible con foco solo en ventas registradas.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _InfoMiniStat extends StatelessWidget {
  const _InfoMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({required this.items});

  final List<_DesktopMetricData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 320 ? 2 : 1;
          final aspectRatio = crossAxisCount == 2
              ? (width >= 360 ? 1.32 : 1.18)
              : 2.8;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.value,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DesktopMetricData {
  const _DesktopMetricData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
}

class _SalesSummary extends StatelessWidget {
  const _SalesSummary({
    required this.state,
    required this.dayPoints,
    required this.weekdayStats,
    required this.topProducts,
    required this.bestDay,
    required this.strongestWeekday,
    required this.averageDailySales,
    required this.money,
    required this.compactMoney,
  });

  final VentasState state;
  final List<_SalesDayPoint> dayPoints;
  final List<_SalesWeekdayStat> weekdayStats;
  final List<_TopProductStat> topProducts;
  final _SalesDayPoint? bestDay;
  final _SalesWeekdayStat? strongestWeekday;
  final double averageDailySales;
  final String Function(double value) money;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final stackHeader = width < 860;

              return stackHeader
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de ventas',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mira con claridad tu avance comercial, el ritmo diario y los indicadores que importan para cerrar la quincena.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumen de ventas',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                      color: const Color(0xFF0F172A),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Mira con claridad tu avance comercial, el ritmo diario y los indicadores que importan para cerrar la quincena.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
            },
          ),
          if (state.loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (state.sales.isEmpty && !state.loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 58,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Aun no hay datos suficientes',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        'Cuando empieces a registrar ventas, este panel mostrara tendencia, rendimiento y resultados del periodo.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final stackAnalytics = width < 1120;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SalesSummaryGrid(
                      cards: [
                        _SalesSummaryMetric(
                          title: 'Ventas registradas',
                          value: state.summary.totalSales.toString(),
                          subtitle: 'ventas activas en el rango',
                          icon: Icons.receipt_long_outlined,
                        ),
                        _SalesSummaryMetric(
                          title: 'Total vendido',
                          value: money(state.summary.totalSold),
                          subtitle: 'facturacion acumulada',
                          icon: Icons.payments_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (stackAnalytics)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DailyTrendChart(
                            points: dayPoints,
                            bestDay: bestDay,
                            averageDailySales: averageDailySales,
                            compactMoney: compactMoney,
                          ),
                          const SizedBox(height: 12),
                          _WeekdayPerformanceCard(
                            stats: weekdayStats,
                            strongestWeekday: strongestWeekday,
                            compactMoney: compactMoney,
                          ),
                          const SizedBox(height: 12),
                          _TopProductsCard(products: topProducts),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _DailyTrendChart(
                              points: dayPoints,
                              bestDay: bestDay,
                              averageDailySales: averageDailySales,
                              compactMoney: compactMoney,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _WeekdayPerformanceCard(
                                  stats: weekdayStats,
                                  strongestWeekday: strongestWeekday,
                                  compactMoney: compactMoney,
                                ),
                                const SizedBox(height: 12),
                                _TopProductsCard(products: topProducts),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SalesSummaryMetric {
  const _SalesSummaryMetric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
}

class _SalesSummaryGrid extends StatelessWidget {
  const _SalesSummaryGrid({required this.cards});

  final List<_SalesSummaryMetric> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1400
            ? 4
            : width > 1100
            ? 3
            : width > 800
            ? 2
            : 1;
        final aspectRatio = crossAxisCount == 1
            ? 2.9
            : crossAxisCount == 2
            ? 1.95
            : crossAxisCount == 3
            ? 1.55
            : 1.35;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return _SummaryMetricCard(
              title: card.title,
              value: card.value,
              subtitle: card.subtitle,
              icon: card.icon,
            );
          },
        );
      },
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({
    required this.points,
    required this.bestDay,
    required this.averageDailySales,
    required this.compactMoney,
  });

  final List<_SalesDayPoint> points;
  final _SalesDayPoint? bestDay;
  final double averageDailySales;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final aspectRatio = width >= 1280
            ? 3.0
            : width >= 980
            ? 2.6
            : width >= 760
            ? 2.2
            : 1.7;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tendencia diaria',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Asi se ha movido tu facturacion durante los ultimos dias del rango actual.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryInlineBadge(
                    icon: Icons.show_chart_outlined,
                    label: 'Promedio diario',
                    value: compactMoney(averageDailySales),
                  ),
                  _SummaryInlineBadge(
                    icon: Icons.trending_up_outlined,
                    label: 'Pico del rango',
                    value: bestDay == null
                        ? 'Sin datos'
                        : '${DateFormat('dd/MM').format(bestDay!.day)} · ${compactMoney(bestDay!.total)}',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AspectRatio(
                aspectRatio: aspectRatio,
                child: points.isEmpty
                    ? Center(
                        child: Text(
                          'Todavia no hay suficientes datos para dibujar la tendencia.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : _TrendChartPlot(
                        points: points,
                        bestDay: bestDay,
                        averageDailySales: averageDailySales,
                        compactMoney: compactMoney,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendChartPlot extends StatelessWidget {
  const _TrendChartPlot({
    required this.points,
    required this.bestDay,
    required this.averageDailySales,
    required this.compactMoney,
  });

  final List<_SalesDayPoint> points;
  final _SalesDayPoint? bestDay;
  final double averageDailySales;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxValue = points
        .map((item) => item.total)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final chartMax = math.max(maxValue, averageDailySales).toDouble();
    final tickValues = [chartMax, chartMax * 0.66, chartMax * 0.33, 0.0];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.05),
            scheme.surface.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tickValues
                    .map(
                      (value) => Text(
                        compactMoney(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _SalesTrendChartPainter(
                      points: points,
                      maxValue: chartMax,
                      averageValue: averageDailySales,
                      bestDay: bestDay,
                      lineColor: const Color(0xFF2563EB),
                      fillTopColor: const Color(0xFF60A5FA),
                      fillBottomColor: const Color(0xFF1D4ED8),
                      gridColor: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: points
                      .map(
                        (point) => Expanded(
                          child: Text(
                            DateFormat('dd/MM').format(point.day),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesTrendChartPainter extends CustomPainter {
  const _SalesTrendChartPainter({
    required this.points,
    required this.maxValue,
    required this.averageValue,
    required this.bestDay,
    required this.lineColor,
    required this.fillTopColor,
    required this.fillBottomColor,
    required this.gridColor,
  });

  final List<_SalesDayPoint> points;
  final double maxValue;
  final double averageValue;
  final _SalesDayPoint? bestDay;
  final Color lineColor;
  final Color fillTopColor;
  final Color fillBottomColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const topPadding = 16.0;
    const bottomPadding = 10.0;
    const sidePadding = 8.0;
    final usableHeight = size.height - topPadding - bottomPadding;
    final usableWidth = size.width - (sidePadding * 2);
    final baselineY = size.height - bottomPadding;
    final stepX = points.length == 1 ? 0.0 : usableWidth / (points.length - 1);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    final chartPoints = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final x = sidePadding + (stepX * index);
      final normalized = (point.total / safeMax).clamp(0.0, 1.0);
      final y = baselineY - (usableHeight * normalized);
      chartPoints.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var index = 0; index < 4; index++) {
      final y = topPadding + ((usableHeight / 3) * index);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final averageNormalized = (averageValue / safeMax).clamp(0.0, 1.0);
    final averageY = baselineY - (usableHeight * averageNormalized);
    _drawDashedLine(
      canvas,
      start: Offset(0, averageY),
      end: Offset(size.width, averageY),
      color: lineColor.withValues(alpha: 0.35),
    );

    if (bestDay != null) {
      final bestIndex = points.indexWhere(
        (point) => point.day == bestDay!.day && point.total == bestDay!.total,
      );
      if (bestIndex >= 0) {
        final highlightX = chartPoints[bestIndex].dx;
        canvas.drawLine(
          Offset(highlightX, topPadding),
          Offset(highlightX, baselineY),
          Paint()
            ..color = lineColor.withValues(alpha: 0.14)
            ..strokeWidth = 2,
        );
      }
    }

    final linePath = Path()..moveTo(chartPoints.first.dx, chartPoints.first.dy);
    for (final point in chartPoints.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(chartPoints.last.dx, baselineY)
      ..lineTo(chartPoints.first.dx, baselineY)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fillTopColor.withValues(alpha: 0.32),
          fillBottomColor.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTWH(0, topPadding, size.width, usableHeight));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    for (var index = 0; index < chartPoints.length; index++) {
      final point = chartPoints[index];
      final isBest =
          bestDay != null &&
          points[index].day == bestDay!.day &&
          points[index].total == bestDay!.total;

      if (isBest) {
        canvas.drawCircle(
          point,
          8,
          Paint()..color = lineColor.withValues(alpha: 0.14),
        );
      }

      canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3.2, Paint()..color = lineColor);
    }
  }

  void _drawDashedLine(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required Color color,
  }) {
    const dashWidth = 8.0;
    const dashGap = 6.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    final totalWidth = end.dx - start.dx;
    double current = 0;
    while (current < totalWidth) {
      final dashEnd = math.min(current + dashWidth, totalWidth);
      canvas.drawLine(
        Offset(start.dx + current, start.dy),
        Offset(start.dx + dashEnd, start.dy),
        paint,
      );
      current += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _SalesTrendChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.averageValue != averageValue ||
        oldDelegate.bestDay != bestDay ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillTopColor != fillTopColor ||
        oldDelegate.fillBottomColor != fillBottomColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _SummaryInlineBadge extends StatelessWidget {
  const _SummaryInlineBadge({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekdayPerformanceCard extends StatelessWidget {
  const _WeekdayPerformanceCard({
    required this.stats,
    required this.strongestWeekday,
    required this.compactMoney,
  });

  final List<_SalesWeekdayStat> stats;
  final _SalesWeekdayStat? strongestWeekday;
  final String Function(double value) compactMoney;

  @override
  Widget build(BuildContext context) {
    final maxTotal = stats.fold<double>(0, (max, item) {
      if (item.total > max) return item.total;
      return max;
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dias con mejor salida',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            strongestWeekday == null
                ? 'Todavia no hay un patron claro de ventas.'
                : 'Tu dia mas fuerte ahora mismo es ${strongestWeekday!.label} con ${compactMoney(strongestWeekday!.total)} vendidos.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: stats
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            item.label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 10,
                              value: maxTotal <= 0
                                  ? 0
                                  : (item.total / maxTotal)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 78,
                          child: Text(
                            compactMoney(item.total),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products});

  final List<_TopProductStat> products;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = (MediaQuery.sizeOf(context).height * 0.32)
        .clamp(220.0, 360.0)
        .toDouble();
    final shouldScroll = products.length > 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Productos mas movidos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (products.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${products.length} items',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            Text(
              'Sin movimientos suficientes por producto.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ConstrainedBox(
              constraints: shouldScroll
                  ? BoxConstraints(maxHeight: maxListHeight)
                  : const BoxConstraints(),
              child: ListView.builder(
                shrinkWrap: !shouldScroll,
                physics: shouldScroll
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  final isLast = index == products.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'x${product.quantity.toStringAsFixed(product.quantity % 1 == 0 ? 0 : 2)}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SalesWeekdayStat {
  const _SalesWeekdayStat({
    required this.weekday,
    required this.label,
    required this.total,
  });

  final int weekday;
  final String label;
  final double total;
}

class _SalesDayPoint {
  const _SalesDayPoint({required this.day, required this.total});

  final DateTime day;
  final double total;
}

class _TopProductStat {
  const _TopProductStat({required this.name, required this.quantity});

  final String name;
  final double quantity;
}
