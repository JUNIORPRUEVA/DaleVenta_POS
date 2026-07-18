import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../modules/ventas/data/ventas_repository.dart';
import '../../../modules/ventas/sales_models.dart';

const _primaryBlue = Color(0xFF2563EB);
const _teal = Color(0xFF0D9488);
const _gold = Color(0xFFD97706);
const _error = Color(0xFFDC2626);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _borderSoft = Color(0xFFE5E7EB);
const _pageBg = Color(0xFFF6F8FB);

enum DateRangePeriod { today, week, biweekly, month, year, custom }

class KpisData {
  const KpisData({
    required this.totalSales,
    required this.totalProfit,
    required this.netProfit,
    required this.totalCost,
    required this.salesCount,
    required this.quotesCount,
    required this.quotesConverted,
    required this.avgTicket,
    required this.cashIncome,
    required this.cashExpense,
  });

  final double totalSales;
  final double totalProfit;
  final double netProfit;
  final double totalCost;
  final int salesCount;
  final int quotesCount;
  final int quotesConverted;
  final double avgTicket;
  final double cashIncome;
  final double cashExpense;

  double get margin => totalSales == 0 ? 0 : (netProfit / totalSales) * 100;

  factory KpisData.fromSummary(SalesSummaryModel summary) {
    return KpisData(
      totalSales: summary.totalSold,
      totalProfit: summary.totalProfit,
      netProfit: summary.totalProfit,
      totalCost: summary.totalCost,
      salesCount: summary.totalSales,
      quotesCount: 0,
      quotesConverted: 0,
      avgTicket: summary.totalSales == 0
          ? 0
          : summary.totalSold / summary.totalSales,
      cashIncome: summary.totalSold,
      cashExpense: summary.totalCost,
    );
  }

  factory KpisData.fromReport(Map<String, dynamic> json) {
    final kpis = ((json['kpis'] as Map?) ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    final totalSales = (kpis['totalSales'] as num?)?.toInt() ?? 0;
    final totalSold = _toDouble(kpis['netSales'] ?? kpis['totalSold']);
    return KpisData(
      totalSales: totalSold,
      totalProfit: _toDouble(kpis['totalProfit']),
      netProfit: _toDouble(kpis['netProfit'] ?? kpis['totalProfit']),
      totalCost: _toDouble(kpis['totalCost']),
      salesCount: totalSales,
      quotesCount: 0,
      quotesConverted: 0,
      avgTicket: _toDouble(
        kpis['avgTicket'] ?? (totalSales == 0 ? 0 : totalSold / totalSales),
      ),
      cashIncome: _toDouble(kpis['cashIncome']),
      cashExpense: _toDouble(kpis['cashExpense']),
    );
  }
}

class PaymentMethodData {
  const PaymentMethodData({
    required this.method,
    required this.amount,
    required this.count,
  });

  final String method;
  final double amount;
  final int count;
}

class SeriesDataPoint {
  const SeriesDataPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class TopProduct {
  const TopProduct({
    required this.productName,
    required this.totalSales,
    required this.totalQty,
    required this.totalProfit,
  });

  final String productName;
  final double totalSales;
  final double totalQty;
  final double totalProfit;
}

class TopClient {
  const TopClient({
    required this.clientName,
    required this.totalSpent,
    required this.purchaseCount,
  });

  final String clientName;
  final double totalSpent;
  final int purchaseCount;
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  DateRangePeriod _selectedPeriod = DateRangePeriod.month;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _loading = true;
  String? _error;

  KpisData _kpis = KpisData.fromSummary(SalesSummaryModel.empty());
  List<SaleModel> _sales = const [];
  List<SeriesDataPoint> _salesSeries = const [];
  List<SeriesDataPoint> _profitSeries = const [];
  List<PaymentMethodData> _paymentMethods = const [];
  List<TopProduct> _topProducts = const [];
  List<TopClient> _topClients = const [];
  List<_ComparisonRowData> _comparisons = const [];

  final _date = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
  }

  DateTimeRange get _range => DateRangeHelper.getRangeForPeriod(
    _selectedPeriod,
    customStart: _customStart,
    customEnd: _customEnd,
  );

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(ventasRepositoryProvider);
      final range = _range;
      final results = await Future.wait([
        repo.reportsSalesOverview(from: range.start, to: range.end),
        repo.listSales(from: range.start, to: range.end),
      ]);
      final report = results[0] as Map<String, dynamic>;
      final sales = results[1] as List<SaleModel>;
      final comparisons = await _loadComparisons(repo);

      if (!mounted) return;
      setState(() {
        _kpis = KpisData.fromReport(report);
        _sales = sales;
        _salesSeries = _parseSeries(report['salesSeries']);
        _profitSeries = _parseSeries(report['profitSeries']);
        _paymentMethods = _parsePaymentMethods(report['paymentMethods']);
        _topProducts = _parseTopProducts(report['topProducts']);
        _topClients = _parseTopClients(report['topClients']);
        _comparisons = comparisons;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los reportes';
      });
    }
  }

  Future<List<_ComparisonRowData>> _loadComparisons(
    VentasRepository repo,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);

    Future<SalesSummaryModel> summary(DateTime from, DateTime to) {
      return repo.summary(from: from, to: to);
    }

    final data = await Future.wait([
      summary(today, today),
      summary(yesterday, yesterday),
      summary(weekStart, today),
      summary(lastWeekStart, lastWeekStart.add(const Duration(days: 6))),
      summary(monthStart, today),
      summary(lastMonthStart, lastMonthEnd),
    ]);

    return [
      _ComparisonRowData(
        icon: Icons.today_outlined,
        currentLabel: 'Hoy',
        previousLabel: 'Ayer',
        currentValue: data[0].totalSold,
        previousValue: data[1].totalSold,
        currentCount: data[0].totalSales,
        previousCount: data[1].totalSales,
      ),
      _ComparisonRowData(
        icon: Icons.date_range_outlined,
        currentLabel: 'Esta semana',
        previousLabel: 'Semana pasada',
        currentValue: data[2].totalSold,
        previousValue: data[3].totalSold,
        currentCount: data[2].totalSales,
        previousCount: data[3].totalSales,
      ),
      _ComparisonRowData(
        icon: Icons.calendar_month_outlined,
        currentLabel: 'Este mes',
        previousLabel: 'Mes pasado',
        currentValue: data[4].totalSold,
        previousValue: data[5].totalSold,
        currentCount: data[4].totalSales,
        previousCount: data[5].totalSales,
      ),
    ];
  }

  void _changePeriod(DateRangePeriod period) {
    if (period == DateRangePeriod.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _selectedPeriod = period);
    _loadData();
  }

  Future<void> _pickCustomRange() async {
    final initial = _range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _selectedPeriod = DateRangePeriod.custom;
      _customStart = picked.start;
      _customEnd = picked.end;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      backgroundColor: _pageBg,
      body: LayoutBuilder(
        builder: (context, pageConstraints) {
          final mobile = pageConstraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.all(mobile ? 8 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReportsTopBar(
                  selectedPeriod: _selectedPeriod,
                  customLabel: _selectedPeriod == DateRangePeriod.custom
                      ? '${_date.format(_range.start)} - ${_date.format(_range.end)}'
                      : null,
                  loading: _loading,
                  onPeriodChanged: _changePeriod,
                  onReload: _loadData,
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Expanded(child: Center(child: Text(_error!)))
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1120;
                        return RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView(
                            padding: EdgeInsets.only(bottom: mobile ? 18 : 0),
                            children: [
                              _HeroReportsPanel(
                                wide: wide,
                                kpis: _kpis,
                                salesSeries: _salesSeries,
                                paymentMethods: _paymentMethods,
                                periodLabel:
                                    '${_date.format(_range.start)} - ${_date.format(_range.end)}',
                              ),
                              const SizedBox(height: 12),
                              _AdvancedKpiCards(kpis: _kpis),
                              const SizedBox(height: 12),
                              wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: _PremiumCard(
                                            title: 'Utilidad',
                                            child: SizedBox(
                                              height: 260,
                                              child: ProfitLineChart(
                                                data: _profitSeries,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: _ComparativeStatsCard(
                                            rows: _comparisons,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _PremiumCard(
                                          title: 'Utilidad',
                                          child: SizedBox(
                                            height: 230,
                                            child: ProfitLineChart(
                                              data: _profitSeries,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _ComparativeStatsCard(
                                          rows: _comparisons,
                                        ),
                                      ],
                                    ),
                              const SizedBox(height: 12),
                              wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TopProductsTable(
                                            products: _topProducts,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TopClientsTable(
                                            clients: _topClients,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        TopProductsTable(
                                          products: _topProducts,
                                        ),
                                        const SizedBox(height: 12),
                                        TopClientsTable(clients: _topClients),
                                      ],
                                    ),
                              const SizedBox(height: 12),
                              _RecentSalesTable(
                                sales: _sales.take(12).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DateRangeHelper {
  static DateTimeRange getRangeForPeriod(
    DateRangePeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return switch (period) {
      DateRangePeriod.today => DateTimeRange(start: today, end: endOfToday),
      DateRangePeriod.week => DateTimeRange(
        start: today.subtract(const Duration(days: 7)),
        end: endOfToday,
      ),
      DateRangePeriod.biweekly => DateTimeRange(
        start: today.subtract(const Duration(days: 15)),
        end: endOfToday,
      ),
      DateRangePeriod.month => DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: endOfToday,
      ),
      DateRangePeriod.year => DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: endOfToday,
      ),
      DateRangePeriod.custom => DateTimeRange(
        start: customStart ?? today,
        end: customEnd ?? endOfToday,
      ),
    };
  }
}

class _ReportsTopBar extends StatelessWidget {
  const _ReportsTopBar({
    required this.selectedPeriod,
    required this.customLabel,
    required this.loading,
    required this.onPeriodChanged,
    required this.onReload,
  });

  final DateRangePeriod selectedPeriod;
  final String? customLabel;
  final bool loading;
  final ValueChanged<DateRangePeriod> onPeriodChanged;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return _Surface(
      padding: EdgeInsets.fromLTRB(12, 10, 12, mobile ? 12 : 10),
      radius: 14,
      child: Column(
        children: [
          if (mobile)
            Column(
              children: [
                Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Menú',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(
                        Icons.bar_chart_rounded,
                        color: scheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Reportes',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Recargar',
                      onPressed: loading ? null : onReload,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Menú',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reportes',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: loading ? null : onReload,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Recargar'),
                ),
              ],
            ),
          const SizedBox(height: 10),
          DateRangeSelector(
            selectedPeriod: selectedPeriod,
            customLabel: customLabel,
            onPeriodChanged: onPeriodChanged,
          ),
        ],
      ),
    );
  }
}

class DateRangeSelector extends StatelessWidget {
  const DateRangeSelector({
    super.key,
    required this.selectedPeriod,
    required this.customLabel,
    required this.onPeriodChanged,
  });

  final DateRangePeriod selectedPeriod;
  final String? customLabel;
  final ValueChanged<DateRangePeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return _Surface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      radius: 12,
      shadow: false,
      child: SingleChildScrollView(
        scrollDirection: mobile ? Axis.horizontal : Axis.vertical,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(context, 'Hoy', DateRangePeriod.today),
            _chip(context, 'Semana', DateRangePeriod.week),
            _chip(context, '15 días', DateRangePeriod.biweekly),
            _chip(context, 'Mes', DateRangePeriod.month),
            _chip(context, 'Año', DateRangePeriod.year),
            _chip(
              context,
              customLabel == null ? 'Personalizado' : customLabel!,
              DateRangePeriod.custom,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, DateRangePeriod period) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedPeriod == period;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        if (value) onPeriodChanged(period);
      },
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: TextStyle(
        color: selected ? scheme.primary : scheme.onSurface,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
    );
  }
}

class _HeroReportsPanel extends StatelessWidget {
  const _HeroReportsPanel({
    required this.wide,
    required this.kpis,
    required this.salesSeries,
    required this.paymentMethods,
    required this.periodLabel,
  });

  final bool wide;
  final KpisData kpis;
  final List<SeriesDataPoint> salesSeries;
  final List<PaymentMethodData> paymentMethods;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    final salesPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ventas del período',
          style: TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRdCurrencyAccounting(kpis.totalSales),
            style: TextStyle(
              fontSize: wide
                  ? 42
                  : mobile
                  ? 28
                  : 34,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Pill(text: periodLabel),
        const SizedBox(height: 16),
        SizedBox(
          height: wide
              ? 290
              : mobile
              ? 190
              : 240,
          child: SalesBarChart(data: salesSeries, barColor: _primaryBlue),
        ),
      ],
    );

    final methodPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryTile(
              label: 'Margen',
              value: '${kpis.margin.toStringAsFixed(1)}%',
              color: _teal,
            ),
            _SummaryTile(
              label: 'Órdenes',
              value: '${kpis.salesCount}',
              color: _primaryBlue,
            ),
            _SummaryTile(
              label: 'Utilidad',
              value: formatRdCurrencyAccounting(kpis.netProfit),
              color: _gold,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: mobile ? 230 : 250,
          child: PaymentMethodPieChart(data: paymentMethods),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HeroMiniInfo(
              label: 'Ticket promedio',
              value: formatRdCurrencyAccounting(kpis.avgTicket),
            ),
            _HeroMiniInfo(
              label: 'Método líder',
              value: paymentMethods.isEmpty
                  ? 'Sin datos'
                  : paymentMethods.first.method,
            ),
          ],
        ),
      ],
    );

    return _Surface(
      padding: EdgeInsets.all(mobile ? 14 : 22),
      radius: 12,
      gradient: const LinearGradient(
        colors: [Color(0xFFF8FBFF), Color(0xFFEDF4FF), Color(0xFFF6FBFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: salesPanel),
                const SizedBox(width: 26),
                Expanded(flex: 4, child: methodPanel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [salesPanel, const SizedBox(height: 18), methodPanel],
            ),
    );
  }
}

class _AdvancedKpiCards extends StatelessWidget {
  const _AdvancedKpiCards({required this.kpis});
  final KpisData kpis;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiCard(
          title: 'Ventas totales',
          value: formatRdCurrencyAccounting(kpis.totalSales),
          icon: Icons.payments_outlined,
          color: _primaryBlue,
        ),
        _KpiCard(
          title: 'Utilidad',
          value: formatRdCurrencyAccounting(kpis.netProfit),
          icon: Icons.trending_up_rounded,
          color: _teal,
        ),
        _KpiCard(
          title: 'Costo vendido',
          value: formatRdCurrencyAccounting(kpis.totalCost),
          icon: Icons.inventory_2_outlined,
          color: _gold,
        ),
        _KpiCard(
          title: 'Ticket promedio',
          value: formatRdCurrencyAccounting(kpis.avgTicket),
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF7C3AED),
        ),
      ],
    );
  }
}

class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.data, required this.barColor});
  final List<SeriesDataPoint> data;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _EmptyChart();
    return CustomPaint(
      painter: _BarChartPainter(data: data, color: barColor),
      child: const SizedBox.expand(),
    );
  }
}

class ProfitLineChart extends StatelessWidget {
  const ProfitLineChart({super.key, required this.data});
  final List<SeriesDataPoint> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _EmptyChart();
    return CustomPaint(
      painter: _LineChartPainter(data: data, color: _gold),
      child: const SizedBox.expand(),
    );
  }
}

class PaymentMethodPieChart extends StatelessWidget {
  const PaymentMethodPieChart({super.key, required this.data});
  final List<PaymentMethodData> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _EmptyChart();
    final total = data.fold<double>(0, (sum, item) => sum + item.amount);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 360;
        final chart = CustomPaint(
          painter: _PieChartPainter(data: data),
          child: Center(
            child: Text(
              formatRdCurrencyAccounting(total),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        );
        final legend = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < data.length; i++)
              _LegendRow(
                color: _chartColors[i % _chartColors.length],
                label: data[i].method,
                value:
                    '${total == 0 ? 0 : ((data[i].amount / total) * 100).toStringAsFixed(0)}% · ${data[i].count}',
              ),
          ],
        );
        if (mobile) {
          return Column(
            children: [
              SizedBox(height: 150, child: chart),
              const SizedBox(height: 8),
              legend,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: chart),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: legend),
          ],
        );
      },
    );
  }
}

class TopProductsTable extends StatelessWidget {
  const TopProductsTable({super.key, required this.products});
  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    return _PremiumCard(
      title: 'Productos más vendidos',
      child: products.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                for (var i = 0; i < products.length; i++)
                  _RankingRow(
                    rank: i + 1,
                    title: products[i].productName,
                    subtitle:
                        '${products[i].totalQty.toStringAsFixed(0)} unidades',
                    trailing: formatRdCurrencyAccounting(
                      products[i].totalSales,
                    ),
                  ),
              ],
            ),
    );
  }
}

class TopClientsTable extends StatelessWidget {
  const TopClientsTable({super.key, required this.clients});
  final List<TopClient> clients;

  @override
  Widget build(BuildContext context) {
    return _PremiumCard(
      title: 'Clientes top',
      child: clients.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                for (var i = 0; i < clients.length; i++)
                  _RankingRow(
                    rank: i + 1,
                    title: clients[i].clientName,
                    subtitle: '${clients[i].purchaseCount} compras',
                    trailing: formatRdCurrencyAccounting(clients[i].totalSpent),
                  ),
              ],
            ),
    );
  }
}

class _ComparativeStatsCard extends StatelessWidget {
  const _ComparativeStatsCard({required this.rows});
  final List<_ComparisonRowData> rows;

  @override
  Widget build(BuildContext context) {
    return _PremiumCard(
      title: 'Comparativas',
      child: Column(
        children: [
          for (final row in rows) ...[
            _ComparisonRow(data: row),
            if (row != rows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _RecentSalesTable extends StatelessWidget {
  const _RecentSalesTable({required this.sales});
  final List<SaleModel> sales;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy');
    return _PremiumCard(
      title: 'Ventas recientes',
      child: sales.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                for (final sale in sales)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEFF6FF),
                      foregroundColor: _primaryBlue,
                      child: Icon(Icons.receipt_long_outlined),
                    ),
                    title: Text(
                      sale.customerName ?? 'Cliente General',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      sale.saleDate == null
                          ? sale.id
                          : date.format(sale.saleDate!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatRdCurrencyAccounting(sale.totalSold),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _primaryBlue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
    this.shadow = true,
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool shadow;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _borderSoft),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return _Surface(
      padding: EdgeInsets.all(mobile ? 12 : 16),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return SizedBox(
      width: mobile ? double.infinity : 260,
      child: _Surface(
        padding: EdgeInsets.all(mobile ? 14 : 18),
        radius: 14,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return Container(
      width: mobile ? double.infinity : 145,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniInfo extends StatelessWidget {
  const _HeroMiniInfo({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return Container(
      width: mobile ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textSecondary, fontSize: 11),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _primaryBlue,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: mobile
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      color: _primaryBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        trailing,
                        style: const TextStyle(
                          color: _primaryBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      color: _primaryBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      trailing,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.icon,
    required this.currentLabel,
    required this.previousLabel,
    required this.currentValue,
    required this.previousValue,
    required this.currentCount,
    required this.previousCount,
  });

  final IconData icon;
  final String currentLabel;
  final String previousLabel;
  final double currentValue;
  final double previousValue;
  final int currentCount;
  final int previousCount;
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.data});
  final _ComparisonRowData data;

  @override
  Widget build(BuildContext context) {
    final change = data.previousValue == 0
        ? (data.currentValue == 0 ? 0.0 : 100.0)
        : ((data.currentValue - data.previousValue) / data.previousValue) * 100;
    final positive = change >= 0;
    final color = positive ? _teal : _error;
    final mobile = MediaQuery.sizeOf(context).width < 640;

    final trend = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${positive ? '+' : ''}${change.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSoft),
      ),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(data.icon, color: _primaryBlue, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.currentLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    trend,
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRdCurrencyAccounting(data.currentValue),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: _primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.currentCount} ventas | ${data.previousLabel}: ${formatRdCurrencyAccounting(data.previousValue)} (${data.previousCount} ventas)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, color: _primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.currentLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          trend,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatRdCurrencyAccounting(data.currentValue),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${data.currentCount} ventas | ${data.previousLabel}: ${formatRdCurrencyAccounting(data.previousValue)} (${data.previousCount} ventas)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
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

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Sin datos en el rango seleccionado',
        textAlign: TextAlign.center,
        style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({required this.data, required this.color});
  final List<SeriesDataPoint> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    const bottom = 28.0;
    const top = 12.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - 8,
      size.height - top - bottom,
    );
    final maxValue = data.map((e) => e.value.abs()).fold<double>(0, math.max);
    final safeMax = maxValue == 0 ? 1 : maxValue;
    final axis = Paint()
      ..color = _borderSoft
      ..strokeWidth = 1;
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axis);
    for (var i = 0; i < 4; i++) {
      final y = chart.top + (chart.height / 4) * i;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), axis);
    }
    final slot = chart.width / data.length;
    final barW = slot <= 16 ? slot * 0.58 : math.min(slot * 0.62, 28.0);
    final barPaint = Paint()..color = color;
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final labelStep = math.max(1, (data.length / 7).ceil()).toInt();
    for (var i = 0; i < data.length; i++) {
      final h = (data[i].value.abs() / safeMax) * (chart.height - 8);
      final x = chart.left + slot * i + (slot - barW) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chart.bottom - h, barW, h),
        const Radius.circular(4),
      );
      barPaint.color = data[i].value < 0 ? _error : color;
      canvas.drawRRect(rect, barPaint);
      if (i % labelStep == 0) {
        textPainter.text = TextSpan(
          text: data[i].label.substring(5).replaceAll('-', '/'),
          style: const TextStyle(fontSize: 10, color: _textSecondary),
        );
        textPainter.layout(maxWidth: slot + 8);
        textPainter.paint(canvas, Offset(x - 4, chart.bottom + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.data, required this.color});
  final List<SeriesDataPoint> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 18.0;
    final rect = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    final maxValue = data.map((e) => e.value).fold<double>(0, math.max);
    final safeMax = maxValue == 0 ? 1 : maxValue;
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = rect.left + (rect.width / math.max(1, data.length - 1)) * i;
      final y = rect.bottom - (data[i].value / safeMax) * rect.height;
      points.add(Offset(x, y));
    }
    final grid = Paint()
      ..color = _borderSoft
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = rect.top + (rect.height / 4) * i;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final fill = Path.from(path)
      ..lineTo(points.last.dx, rect.bottom)
      ..lineTo(points.first.dx, rect.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({required this.data});
  final List<PaymentMethodData> data;

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(0, (sum, item) => sum + item.amount);
    if (total == 0) return;
    final radius = math.min(size.width, size.height) / 2 - 8;
    final center = Offset(size.width / 2, size.height / 2);
    var start = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26;
    for (var i = 0; i < data.length; i++) {
      final sweep = (data[i].amount / total) * math.pi * 2;
      paint.color = _chartColors[i % _chartColors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

const _chartColors = [
  _primaryBlue,
  _teal,
  _gold,
  _error,
  Color(0xFF60A5FA),
  Color(0xFFFBBF24),
];

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}

List<SeriesDataPoint> _parseSeries(dynamic raw) {
  final rows = raw is List ? raw : const [];
  return rows
      .whereType<Map>()
      .map(
        (row) => SeriesDataPoint(
          label: (row['label'] ?? '').toString(),
          value: _toDouble(row['value']),
        ),
      )
      .where((row) => row.label.trim().isNotEmpty)
      .toList(growable: false);
}

List<PaymentMethodData> _parsePaymentMethods(dynamic raw) {
  final rows = raw is List ? raw : const [];
  return rows
      .whereType<Map>()
      .map(
        (row) => PaymentMethodData(
          method: (row['method'] ?? '').toString(),
          amount: _toDouble(row['amount']),
          count: (row['count'] as num?)?.toInt() ?? 0,
        ),
      )
      .where((row) => row.method.trim().isNotEmpty)
      .toList(growable: false);
}

List<TopProduct> _parseTopProducts(dynamic raw) {
  final rows = raw is List ? raw : const [];
  return rows
      .whereType<Map>()
      .map(
        (row) => TopProduct(
          productName: (row['productName'] ?? '').toString(),
          totalSales: _toDouble(row['totalSales']),
          totalQty: _toDouble(row['totalQty']),
          totalProfit: _toDouble(row['totalProfit']),
        ),
      )
      .where((row) => row.productName.trim().isNotEmpty)
      .toList(growable: false);
}

List<TopClient> _parseTopClients(dynamic raw) {
  final rows = raw is List ? raw : const [];
  return rows
      .whereType<Map>()
      .map(
        (row) => TopClient(
          clientName: (row['clientName'] ?? '').toString(),
          totalSpent: _toDouble(row['totalSpent']),
          purchaseCount: (row['purchaseCount'] as num?)?.toInt() ?? 0,
        ),
      )
      .where((row) => row.clientName.trim().isNotEmpty)
      .toList(growable: false);
}
