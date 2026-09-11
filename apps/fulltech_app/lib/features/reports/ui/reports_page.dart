import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/debug/trace_log.dart';
import '../../../core/realtime/operations_refresh_signals.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../modules/ventas/data/ventas_repository.dart';
import '../../../modules/ventas/sales_models.dart';
import '../utils/sales_report_pdf_service.dart';

const _primaryBlue = Color(0xFF2563EB);
const _teal = Color(0xFF0D9488);
const _gold = Color(0xFFD97706);
const _error = Color(0xFFDC2626);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _borderSoft = Color(0xFFE5E7EB);
const _pageBg = Color(0xFFF6F8FB);

/// Radio local de la superficie de FILTROS de Reportes (paneles y chips).
/// El design system de la app usa 16/14 para tarjetas y botones y 999 (pill)
/// para los chips globales (`chipTheme`); los filtros de Reportes deben verse
/// mas rectangulares y profesionales, por eso se fija 10 px (dentro del rango
/// 8-12 pedido) SIN alterar el theme global ni otras pantallas.
const double kReportsFilterRadius = 10;

/// Periodos rapidos de fecha, en el ORDEN EXACTO en que se muestran.
/// Una sola fuente de verdad para el selector (desktop y movil) y el drawer.
enum DateRangePeriod { today, yesterday, week, month, year, custom }

const List<DateRangePeriod> kReportPeriodOrder = <DateRangePeriod>[
  DateRangePeriod.today,
  DateRangePeriod.yesterday,
  DateRangePeriod.week,
  DateRangePeriod.month,
  DateRangePeriod.year,
  DateRangePeriod.custom,
];

/// Filtros por defecto al abrir Reportes: Hoy + Todas las categorias.
/// Un acceso limpio a la pantalla debe iniciar siempre en este estado para
/// evitar que el dueno vea un rango o categoria residual y piense que sus
/// numeros estan mal. Los rebuilds dentro de la pantalla NO deben resetearlo.
const DateRangePeriod kDefaultReportsPeriod = DateRangePeriod.today;

/// Estado de filtros de la pantalla de Reportes (periodo + categoria).
///
/// Inmutable, y vive en el State de la pantalla: sobrevive rebuilds, setState,
/// rotacion, resize, carga de datos y cambios responsive sin crear estado
/// global innecesario. Un acceso limpio arranca en Hoy + Todas.
@immutable
class ReportsFilterState {
  const ReportsFilterState({
    required this.period,
    this.customStart,
    this.customEnd,
    this.category,
  });

  /// Estado inicial: Hoy + Todas las categorias.
  static const ReportsFilterState initial = ReportsFilterState(
    period: kDefaultReportsPeriod,
  );

  final DateRangePeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final String? category;

  bool get isDefault => period == kDefaultReportsPeriod && category == null;

  /// Cambia SOLO el periodo. La categoria seleccionada se conserva.
  ReportsFilterState withPeriod(DateRangePeriod next) {
    return ReportsFilterState(
      period: next,
      customStart: customStart,
      customEnd: customEnd,
      category: category,
    );
  }

  /// Fija un rango personalizado (period = custom). Conserva la categoria.
  ReportsFilterState withCustomRange(DateTime start, DateTime end) {
    return ReportsFilterState(
      period: DateRangePeriod.custom,
      customStart: start,
      customEnd: end,
      category: category,
    );
  }

  /// Cambia SOLO la categoria. El periodo seleccionado se conserva.
  /// Una categoria vacia equivale a "Todas".
  ReportsFilterState withCategory(String? next) {
    final normalized = (next ?? '').trim();
    return ReportsFilterState(
      period: period,
      customStart: customStart,
      customEnd: customEnd,
      category: normalized.isEmpty ? null : normalized,
    );
  }

  ReportsFilterState reset() => initial;
}

class KpisData {
  const KpisData({
    required this.totalSales,
    required this.totalProfit,
    required this.netProfit,
    required this.totalExpenses,
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
  final double totalExpenses;
  final double totalCost;
  final int salesCount;
  final int quotesCount;
  final int quotesConverted;
  final double avgTicket;
  final double cashIncome;
  final double cashExpense;

  /// Margen del periodo = utilidad NETA / ventas netas.
  /// Confirmado por codigo y por el caso auditado (528 / 2100 = 25.1%),
  /// por eso el label visible es "Margen neto" y NO "Margen".
  double get margin => totalSales == 0 ? 0 : (netProfit / totalSales) * 100;
  double get netMargin => margin;
  bool get hasProfitExpenses => totalExpenses > 0;

  /// La utilidad bruta del periodo (antes de gastos que afectan utilidad)
  /// ya viene descontado el efecto real de devoluciones/anulaciones.
  /// Ver [KpisData.fromReport].
  double get grossProfit => totalProfit;

  factory KpisData.fromSummary(SalesSummaryModel summary) {
    return KpisData(
      totalSales: summary.totalSold,
      totalProfit: summary.totalProfit,
      netProfit: summary.totalProfit,
      totalExpenses: 0,
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
    final totalExpenses = _toDouble(kpis['totalExpenses']);
    final netProfit = _toDouble(kpis['netProfit'] ?? kpis['totalProfit']);
    // UTILIDAD BRUTA = utilidad neta + gastos que afectan utilidad.
    //
    // El backend define, con los mismos snapshots historicos ya corregidos:
    //   netProfit = totalProfit - returnsProfit - profitExpenses
    // por lo tanto:
    //   totalProfit - returnsProfit = netProfit + totalExpenses
    //
    // Esa es exactamente la utilidad bruta que pide el negocio: utilidad de
    // las ventas DESPUES del efecto real de devoluciones/anulaciones y ANTES
    // de gastos. Se deriva de campos autoritativos ya entregados por
    // /reports/sales-overview; NO se recalcula con precios ni costos ACTUALES
    // de Product y no se duplica logica financiera en Flutter.
    final fallbackGross = _toDouble(kpis['totalProfit']);
    final grossProfit = kpis['netProfit'] == null
        ? fallbackGross
        : netProfit + totalExpenses;
    return KpisData(
      totalSales: totalSold,
      totalProfit: grossProfit,
      netProfit: netProfit,
      totalExpenses: totalExpenses,
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
    required this.totalQtyLabel,
    required this.totalProfit,
  });

  final String productName;
  final double totalSales;
  final double totalQty;
  final String totalQtyLabel;
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

class CategoryProfitData {
  const CategoryProfitData({
    required this.category,
    required this.totalSales,
    required this.totalCost,
    required this.totalProfit,
    required this.totalQty,
    required this.totalQtyLabel,
    required this.salesCount,
  });

  final String category;
  final double totalSales;
  final double totalCost;
  final double totalProfit;
  final double totalQty;
  final String totalQtyLabel;
  final int salesCount;

  double get margin => totalSales == 0 ? 0 : (totalProfit / totalSales) * 100;
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  // Estado de filtros de la pantalla. Vive en el State (no en providers
  // globales) para sobrevivir setState/rebuild/rotacion/resize sin crear
  // estado global innecesario, y para reiniciar en Hoy + Todas en un acceso
  // limpio. Ver Fases 4 y 13 del plan de Reportes.
  ReportsFilterState _filters = ReportsFilterState.initial;
  bool _loading = true;
  bool _generatingPdf = false;
  String? _error;
  ProviderSubscription<int>? _salesRefreshSubscription;
  ProviderSubscription<int>? _cashRefreshSubscription;
  Timer? _realtimeReloadDebounce;
  // Protección contra races y tormentas de recarga:
  // - [_loadGeneration]: descarta respuestas obsoletas (filtro antiguo) al
  //   cambiar rápidamente de filtro.
  // - [_loadInFlight]/[_pendingReload]: solo una carga en vuelo; los eventos
  //   de realtime se consolidan en una única recarga pendiente.
  int _loadGeneration = 0;
  bool _loadInFlight = false;
  bool _pendingReload = false;

  KpisData _kpis = KpisData.fromSummary(SalesSummaryModel.empty());
  List<SaleModel> _sales = const [];
  List<String> _categories = const [];
  List<SeriesDataPoint> _salesSeries = const [];
  List<SeriesDataPoint> _profitSeries = const [];
  List<PaymentMethodData> _paymentMethods = const [];
  List<TopProduct> _topProducts = const [];
  List<TopClient> _topClients = const [];
  List<CategoryProfitData> _categoryProfits = const [];
  List<_ComparisonRowData> _comparisons = const [];

  final _date = DateFormat('dd/MM/yyyy');

  DateRangePeriod get _selectedPeriod => _filters.period;
  DateTime? get _customStart => _filters.customStart;
  DateTime? get _customEnd => _filters.customEnd;
  String? get _selectedCategory => _filters.category;

  @override
  void initState() {
    super.initState();
    _salesRefreshSubscription = ref.listenManual<int>(
      salesDataRefreshTickProvider,
      (previous, next) => _scheduleRealtimeReload(),
    );
    _cashRefreshSubscription = ref.listenManual<int>(
      cashDataRefreshTickProvider,
      (previous, next) => _scheduleRealtimeReload(),
    );
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _realtimeReloadDebounce?.cancel();
    _salesRefreshSubscription?.close();
    _cashRefreshSubscription?.close();
    super.dispose();
  }

  void _scheduleRealtimeReload() {
    if (!mounted) return;
    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        // El guard interno de [_loadData] consolida recargas: si hay una carga
        // en vuelo, este evento se encola como recarga pendiente (no se pierde).
        unawaited(_loadData());
      }
    });
  }

  DateTimeRange get _range => DateRangeHelper.getRangeForPeriod(
    _selectedPeriod,
    customStart: _customStart,
    customEnd: _customEnd,
  );

  Future<void> _loadData() async {
    // Incrementa la generación SIEMPRE (incluso si hay una carga en vuelo)
    // para que la carga antigua descarte su resultado al finalizar.
    final generation = ++_loadGeneration;
    if (_loadInFlight) {
      _pendingReload = true;
      return;
    }
    _loadInFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(ventasRepositoryProvider);
      final range = _range;
      final report = await repo.reportsSalesOverview(
        from: range.start,
        to: range.end,
        category: _selectedCategory,
      );
      final sales = _projectSalesByCategory(
        await _loadReportSales(repo, range),
        _selectedCategory,
      );
      final comparisons = await _loadComparisonsSafely(repo);

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _kpis = KpisData.fromReport(report);
        _sales = sales;
        _categories = _parseCategories(report['categories']);
        _salesSeries = _parseSeries(report['salesSeries']);
        _profitSeries = _parseSeries(report['profitSeries']);
        _paymentMethods = _parsePaymentMethods(report['paymentMethods']);
        _topProducts = _parseTopProducts(report['topProducts']);
        _topClients = _parseTopClients(report['topClients']);
        _categoryProfits = _parseCategoryProfits(report['categoryProfits']);
        _comparisons = comparisons;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      TraceLog.log(
        'REPORTS',
        'Error cargando reportes (${e.runtimeType}): $e',
        error: e,
      );
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los reportes';
      });
    } finally {
      _loadInFlight = false;
      if (_pendingReload) {
        _pendingReload = false;
        unawaited(_loadData());
      }
    }
  }

  Future<List<SaleModel>> _loadReportSales(
    VentasRepository repo,
    DateTimeRange range,
  ) async {
    try {
      final rows = await repo.listInvoices(
        from: range.start,
        to: range.end,
        includeDeleted: false,
        // Límite acotado: solo se muestran ~12 en pantalla y 30 en el PDF.
        // Evita descargar y parsear en el hilo principal miles de ventas
        // completas (causa principal del bloqueo "No responde").
        limit: 150,
      );
      // Excluye documentos de devolución (kind=refund): no son ventas y no
      // deben aparecer en "Ventas recientes" ni en el PDF.
      return rows
          .where((sale) => sale.kind != 'refund')
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ComparisonRowData>> _loadComparisonsSafely(
    VentasRepository repo,
  ) async {
    try {
      return await _loadComparisons(repo);
    } catch (_) {
      return const [];
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
    // Cambiar el periodo NUNCA altera la categoria seleccionada.
    setState(() => _filters = _filters.withPeriod(period));
    _loadData();
  }

  void _changeCategory(String? category) {
    // Cambiar la categoria NUNCA altera el periodo seleccionado.
    setState(() => _filters = _filters.withCategory(category));
    _loadData();
  }

  /// Hay filtros distintos del estado inicial (Hoy + Todas).
  /// Se usa solo para mostrar/ocultar la accion discreta "Restablecer".
  bool get _hasNonDefaultFilters => !_filters.isDefault;

  /// Vuelve exactamente al estado inicial: Hoy + Todas las categorias,
  /// conservando la pantalla y recargando el reporte una sola vez.
  void _resetFilters() {
    if (!_hasNonDefaultFilters) return;
    setState(() => _filters = _filters.reset());
    _loadData();
  }

  Future<void> _downloadPdf() async {
    if (_loading || _generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      final range = _range;
      final categoryLabel = _selectedCategory?.trim().isNotEmpty == true
          ? _selectedCategory!.trim()
          : 'Todas las categorias';
      final bytes = await buildProfessionalSalesReportPdf(
        from: range.start,
        to: range.end,
        categoryLabel: categoryLabel,
        kpis: SalesReportPdfKpis(
          totalSales: _kpis.totalSales,
          totalProfit: _kpis.totalProfit,
          netProfit: _kpis.netProfit,
          totalExpenses: _kpis.totalExpenses,
          totalCost: _kpis.totalCost,
          salesCount: _kpis.salesCount,
          avgTicket: _kpis.avgTicket,
          margin: _kpis.netMargin,
        ),
        categories: _categoryProfits
            .map(
              (row) => SalesReportPdfCategoryRow(
                category: row.category,
                totalSales: row.totalSales,
                totalCost: row.totalCost,
                totalProfit: row.totalProfit,
                totalQty: row.totalQty,
                totalQtyLabel: row.totalQtyLabel,
                salesCount: row.salesCount,
              ),
            )
            .toList(growable: false),
        sales: _sales,
      );
      await downloadProfessionalSalesReportPdf(
        bytes: bytes,
        from: range.start,
        to: range.end,
        categoryLabel: categoryLabel,
      );
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Reporte PDF descargado.');
    } catch (_) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        'No se pudo generar el reporte PDF.',
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
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
      _filters = _filters.withCustomRange(picked.start, picked.end);
    });
    _loadData();
  }

  Future<void> _openMobileFilters() async {
    final next = await showGeneralDialog<_ReportsFilterDraft>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de reportes',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: ReportsFilterDrawer(
            selectedPeriod: _selectedPeriod,
            categories: _categories,
            selectedCategory: _selectedCategory,
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
    if (next.period == DateRangePeriod.custom) {
      _pickCustomRange();
      if (next.category != _selectedCategory) _changeCategory(next.category);
      return;
    }
    setState(() {
      _filters = _filters.withPeriod(next.period).withCategory(next.category);
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      backgroundColor: _pageBg,
      appBar: MediaQuery.sizeOf(context).width < 640
          ? CustomAppBar(
              title: 'Reportes',
              showLogo: false,
              showDepartmentLabel: false,
              actions: [
                IconButton(
                  tooltip: 'Filtros',
                  onPressed: _openMobileFilters,
                  icon: Badge(
                    isLabelVisible: _hasNonDefaultFilters,
                    smallSize: 8,
                    child: const Icon(Icons.filter_alt_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Recargar',
                  onPressed: _loading ? null : _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'PDF',
                  onPressed: _loading || _generatingPdf ? null : _downloadPdf,
                  icon: _generatingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                ),
              ],
              trailing: const SizedBox.shrink(),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, pageConstraints) {
          final mobile = pageConstraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.all(mobile ? 8 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mobile) ...[
                  ReportsTopBar(
                    selectedPeriod: _selectedPeriod,
                    customLabel: _selectedPeriod == DateRangePeriod.custom
                        ? '${_date.format(_range.start)} - ${_date.format(_range.end)}'
                        : null,
                    loading: _loading,
                    generatingPdf: _generatingPdf,
                    categories: _categories,
                    selectedCategory: _selectedCategory,
                    onPeriodChanged: _changePeriod,
                    onCategoryChanged: _changeCategory,
                    onReload: _loadData,
                    onDownloadPdf: _downloadPdf,
                    showReset: _hasNonDefaultFilters,
                    onReset: _resetFilters,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  // Movil: accesos rapidos de fecha en UNA fila (scroll
                  // horizontal si no caben) + resumen del rango activo.
                  DateRangeSelector(
                    selectedPeriod: _selectedPeriod,
                    customLabel: _selectedPeriod == DateRangePeriod.custom
                        ? '${_date.format(_range.start)} - ${_date.format(_range.end)}'
                        : null,
                    onPeriodChanged: _changePeriod,
                  ),
                  const SizedBox(height: 6),
                  ReportsActiveFilterBar(
                    period: _periodLabel(_selectedPeriod),
                    range:
                        '${_date.format(_range.start)} - ${_date.format(_range.end)}',
                    category: _selectedCategory,
                    onClearCategory: () => _changeCategory(null),
                    showReset: _hasNonDefaultFilters,
                    onReset: _resetFilters,
                  ),
                ],
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  Expanded(child: Center(child: Text(_error!)))
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1120;
                        // Periodo sin ventas: no es un error. Los KPIs quedan en
                        // RD$0.00 y se explica claramente al usuario que puede
                        // cambiar fecha/categoria (Fase 31).
                        final emptyPeriod = !_loading && _kpis.salesCount == 0;
                        return RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView(
                            padding: EdgeInsets.only(bottom: mobile ? 18 : 0),
                            children: mobile
                                ? [
                                    if (emptyPeriod) const _EmptyPeriodNotice(),
                                    _MobileReportsContent(
                                      kpis: _kpis,
                                      salesSeries: _salesSeries,
                                      profitSeries: _profitSeries,
                                      paymentMethods: _paymentMethods,
                                      topProducts: _topProducts,
                                      topClients: _topClients,
                                      sales: _sales.take(8).toList(),
                                    ),
                                  ]
                                : [
                                    if (emptyPeriod) ...[
                                      const _EmptyPeriodNotice(),
                                      const SizedBox(height: 12),
                                    ],
                                    _HeroReportsPanel(
                                      wide: wide,
                                      kpis: _kpis,
                                      salesSeries: _salesSeries,
                                      paymentMethods: _paymentMethods,
                                      periodLabel:
                                          '${_date.format(_range.start)} - ${_date.format(_range.end)}',
                                    ),
                                    const SizedBox(height: 12),
                                    ReportsFinancialKpiCards(kpis: _kpis),
                                    const SizedBox(height: 12),
                                    CategoryProfitTable(
                                      categories: _categoryProfits,
                                    ),
                                    const SizedBox(height: 12),
                                    wide
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: _PremiumCard(
                                                  title: 'Utilidad bruta',
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
                                                title: 'Utilidad bruta',
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
                                              TopClientsTable(
                                                clients: _topClients,
                                              ),
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
  /// [now] permite fijar la fecha de referencia en los tests para verificar
  /// conteos de dias inequivocos. En produccion se usa la fecha local del
  /// dispositivo (dia comercial RD: el backend interpreta el yyyy-MM-dd
  /// enviado como dia local y aplica fin de rango exclusivo).
  static DateTimeRange getRangeForPeriod(
    DateRangePeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final endOfToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
      23,
      59,
      59,
      999,
    );
    return switch (period) {
      DateRangePeriod.today => DateTimeRange(start: today, end: endOfToday),
      DateRangePeriod.yesterday => DateTimeRange(
        start: today.subtract(const Duration(days: 1)),
        end: today.subtract(const Duration(milliseconds: 1)),
      ),
      // Ultimos 7 dias = HOY + los 6 dias anteriores = 7 fechas locales
      // EXACTAS. Se usa aritmetica de CALENDARIO (constructor DateTime) y no
      // `subtract(Duration(days: 6))`, porque Duration es tiempo ABSOLUTO: en
      // zonas con cambio de horario devolveria 23:00 del dia anterior (8 dias).
      // Con `days: 7` se consultaban 8 dias calendario (bug corregido).
      DateRangePeriod.week => DateTimeRange(
        start: DateTime(today.year, today.month, today.day - 6),
        end: endOfToday,
      ),
      DateRangePeriod.month => DateTimeRange(
        start: DateTime(reference.year, reference.month, 1),
        end: endOfToday,
      ),
      DateRangePeriod.year => DateTimeRange(
        start: DateTime(reference.year, 1, 1),
        end: endOfToday,
      ),
      DateRangePeriod.custom => _customRange(
        customStart,
        customEnd,
        today,
        endOfToday,
      ),
    };
  }

  /// Rango personalizado normalizado a dia local completo y SIEMPRE valido
  /// (start <= end). Evita enviar al backend un rango invertido, que el
  /// endpoint rechaza con "La fecha inicial no puede ser mayor que la final".
  static DateTimeRange _customRange(
    DateTime? customStart,
    DateTime? customEnd,
    DateTime today,
    DateTime endOfToday,
  ) {
    final start = customStart == null
        ? today
        : DateTime(customStart.year, customStart.month, customStart.day);
    var end = customEnd == null
        ? endOfToday
        : DateTime(
            customEnd.year,
            customEnd.month,
            customEnd.day,
            23,
            59,
            59,
            999,
          );
    if (end.isBefore(start)) {
      end = DateTime(start.year, start.month, start.day, 23, 59, 59, 999);
    }
    return DateTimeRange(start: start, end: end);
  }
}

/// Etiqueta de boton que NUNCA se parte en dos lineas ni se trunca: si el
/// espacio es muy reducido se reduce la escala (BoxFit.scaleDown) en lugar de
/// cortar el texto o saltar de linea.
Widget _singleLineLabel(String text) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.center,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}

/// Etiquetas EXACTAS de los accesos rapidos de fecha: una sola fuente de
/// verdad para el selector, el drawer movil y la barra de filtros activos.
String _periodLabel(DateRangePeriod period) {
  return switch (period) {
    DateRangePeriod.today => 'Hoy',
    DateRangePeriod.yesterday => 'Ayer',
    // NO es "semana calendario": es hoy + los 6 dias anteriores = 7 fechas
    // locales exactas (ver DateRangeHelper.week).
    DateRangePeriod.week => 'Semana',
    DateRangePeriod.month => 'Mes',
    DateRangePeriod.year => 'Año',
    DateRangePeriod.custom => 'Personalizado',
  };
}

class _ReportsFilterDraft {
  const _ReportsFilterDraft({required this.period, required this.category});

  final DateRangePeriod period;
  final String? category;
}

// Publico (no `_`) para poder testear la UI de filtros de Reportes sin red:
// chips, categorias, footer y SafeArea.
class ReportsFilterDrawer extends StatefulWidget {
  const ReportsFilterDrawer({
    super.key,
    required this.selectedPeriod,
    required this.categories,
    required this.selectedCategory,
  });

  final DateRangePeriod selectedPeriod;
  final List<String> categories;
  final String? selectedCategory;

  @override
  State<ReportsFilterDrawer> createState() => _ReportsFilterDrawerState();
}

class _ReportsFilterDrawerState extends State<ReportsFilterDrawer> {
  late DateRangePeriod _period = widget.selectedPeriod;
  late String? _category = widget.selectedCategory;

  void _apply() {
    Navigator.of(
      context,
    ).pop(_ReportsFilterDraft(period: _period, category: _category));
  }

  /// Restablece el estado inicial (Hoy + Todas) y lo aplica de inmediato,
  /// para no obligar al usuario a volver a tocar "Aplicar filtros".
  void _resetAndApply() {
    Navigator.of(context).pop(
      const _ReportsFilterDraft(period: kDefaultReportsPeriod, category: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 340.0);
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(kReportsFilterRadius),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x330B1720),
                blurRadius: 24,
                offset: Offset(-10, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1957E6), Color(0xFF2F7BFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(kReportsFilterRadius),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filtros',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    const _DrawerSectionTitle('Rango'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in kReportPeriodOrder)
                          _FilterChip(
                            label: _periodLabel(item),
                            selected: _period == item,
                            onTap: () => setState(() => _period = item),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _DrawerSectionTitle('Categoría'),
                    _FilterCategoryTile(
                      label: 'Todas las categorías',
                      selected: _category == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    for (final category in widget.categories)
                      _FilterCategoryTile(
                        label: category,
                        selected: _category == category,
                        onTap: () => setState(() => _category = category),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                // Respeta el inset inferior (navigation bar Android / home
                // indicator iPhone) y deja aire para el pulgar.
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                // Wrap (no Row): cada accion conserva su ancho INTRINSECO. Si
                // no caben juntas se apilan en una segunda linea en vez de
                // reducir la fuente, partir el texto o desbordar.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Accion secundaria discreta (solo texto, sin relleno).
                    TextButton(
                      onPressed: _resetAndApply,
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryBlue,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: _singleLineLabel('Restablecer'),
                    ),
                    // Accion principal: la UNICA con relleno solido, por lo que
                    // mantiene mayor jerarquia visual que Restablecer.
                    FilledButton.icon(
                      onPressed: _apply,
                      icon: const Icon(Icons.check_rounded),
                      label: _singleLineLabel('Aplicar filtros'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FilterCategoryTile extends StatelessWidget {
  const _FilterCategoryTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? _primaryBlue : _textSecondary,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? _primaryBlue : _textPrimary,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

// Publico (no `_`) para poder testear la barra sin red: chip de categoria y
// "Restablecer" en una sola linea.
class ReportsActiveFilterBar extends StatelessWidget {
  const ReportsActiveFilterBar({
    super.key,
    required this.period,
    required this.range,
    required this.category,
    required this.onClearCategory,
    required this.showReset,
    required this.onReset,
  });

  final String period;
  final String range;
  final String? category;
  final VoidCallback onClearCategory;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Pill(text: '$period · $range'),
          if (category?.trim().isNotEmpty == true)
            InputChip(
              label: Text(category!.trim()),
              avatar: const Icon(Icons.category_outlined, size: 16),
              onDeleted: onClearCategory,
              visualDensity: VisualDensity.compact,
            ),
          if (showReset)
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: _singleLineLabel('Restablecer'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: _primaryBlue,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ReportsTopBar extends StatelessWidget {
  const ReportsTopBar({
    super.key,
    required this.selectedPeriod,
    required this.customLabel,
    required this.loading,
    required this.generatingPdf,
    required this.categories,
    required this.selectedCategory,
    required this.onPeriodChanged,
    required this.onCategoryChanged,
    required this.onReload,
    required this.onDownloadPdf,
    required this.showReset,
    required this.onReset,
  });

  final DateRangePeriod selectedPeriod;
  final String? customLabel;
  final bool loading;
  final bool generatingPdf;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<DateRangePeriod> onPeriodChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onReload;
  final VoidCallback onDownloadPdf;
  final bool showReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return _Surface(
      padding: EdgeInsets.fromLTRB(12, 10, 12, mobile ? 12 : 10),
      radius: kReportsFilterRadius,
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
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Descargar PDF',
                      onPressed: loading || generatingPdf
                          ? null
                          : onDownloadPdf,
                      icon: generatingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
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
                if (showReset) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: loading ? null : onReset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Restablecer'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: loading || generatingPdf ? null : onDownloadPdf,
                  icon: generatingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('Descargar PDF'),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Desktop: los 6 periodos deben caber en UNA fila sin scroll
              // innecesario, asi que el selector toma el ancho disponible y la
              // categoria queda en una columna de ancho fijo.
              Expanded(
                child: DateRangeSelector(
                  selectedPeriod: selectedPeriod,
                  customLabel: customLabel,
                  onPeriodChanged: onPeriodChanged,
                ),
              ),
              if (!mobile) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 260,
                  child: CategoryFilterSelector(
                    categories: categories,
                    selectedCategory: selectedCategory,
                    onChanged: loading ? null : onCategoryChanged,
                  ),
                ),
              ],
            ],
          ),
          if (mobile) ...[
            const SizedBox(height: 8),
            CategoryFilterSelector(
              categories: categories,
              selectedCategory: selectedCategory,
              onChanged: loading ? null : onCategoryChanged,
            ),
          ],
          if (selectedCategory?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _Pill(text: 'Filtrado: ${selectedCategory!.trim()}'),
            ),
          ],
        ],
      ),
    );
  }
}

class CategoryFilterSelector extends StatelessWidget {
  const CategoryFilterSelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Todas las categorías'),
      ),
      for (final category in categories)
        DropdownMenuItem<String?>(value: category, child: Text(category)),
    ];
    final selected = categories.contains(selectedCategory)
        ? selectedCategory
        : null;
    return _Surface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      radius: kReportsFilterRadius,
      shadow: false,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: selected,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
          items: items,
          onChanged: onChanged,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          selectedItemBuilder: (context) => items
              .map(
                (item) => Row(
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 17,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.value ?? 'Todas las categorías',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
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
    return _Surface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      radius: kReportsFilterRadius,
      shadow: false,
      // UNA SOLA FILA (nunca Wrap): si los 6 accesos no caben, la fila se
      // desliza horizontalmente. En desktop >=900 caben y no hay scroll.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            // Orden y labels con una sola fuente de verdad (kReportPeriodOrder
            // + _periodLabel), igual que el drawer movil.
            for (final period in kReportPeriodOrder)
              _FilterChip(
                key: ValueKey<String>('reports-period-${period.name}'),
                label: period == DateRangePeriod.custom && customLabel != null
                    ? customLabel!
                    : _periodLabel(period),
                selected: selectedPeriod == period,
                onTap: () => onPeriodChanged(period),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chip de filtro de Reportes.
///
/// A diferencia del chip global (pill, radius 999) usa un radio moderado
/// ([kReportsFilterRadius]) para verse cuadrado/profesional. El estado seleccionado
/// es evidente por RELLENO + BORDE + peso de texto + icono check, de modo que
/// NO depende exclusivamente del color. El espacio del icono se reserva
/// siempre, asi el chip no cambia de ancho al seleccionarse ni al deslizar.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kReportsFilterRadius),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.55)
              : _borderSoft,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kReportsFilterRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: selected
                    ? Icon(Icons.check_rounded, size: 14, color: scheme.primary)
                    : null,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                // Nunca partir el texto (p. ej. "Personalizado").
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: selected ? scheme.primary : _textPrimary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
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
        // NOTA: aqui NO se repiten "Margen neto" / "Utilidad neta" / "Ordenes"
        // porque ReportsFinancialKpiCards (justo debajo en desktop) ya los
        // muestra: repetirlos seria informacion de utilidad duplicada.
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

class ReportsFinancialKpiCards extends StatelessWidget {
  const ReportsFinancialKpiCards({super.key, required this.kpis});
  final KpisData kpis;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCard(
        key: const ValueKey('reports-kpi-sales'),
        title: 'Ventas',
        value: formatRdCurrencyAccounting(kpis.totalSales),
        icon: Icons.payments_outlined,
        color: _primaryBlue,
      ),
      _KpiCard(
        key: const ValueKey('reports-kpi-net-profit'),
        title: 'Utilidad neta',
        value: formatRdCurrencyAccounting(kpis.netProfit),
        icon: Icons.account_balance_wallet_outlined,
        color: kpis.netProfit >= 0 ? _teal : _error,
      ),
      _KpiCard(
        key: const ValueKey('reports-kpi-net-margin'),
        title: 'Margen neto',
        value: '${kpis.netMargin.toStringAsFixed(1)}%',
        icon: Icons.percent_rounded,
        color: _teal,
      ),
      _KpiCard(
        key: const ValueKey('reports-kpi-tickets'),
        title: 'Tickets',
        value: '${kpis.salesCount}',
        icon: Icons.receipt_long_outlined,
        color: _gold,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  SizedBox(width: width, height: 92, child: card),
              ],
            ),
            if (kpis.hasProfitExpenses) ...[
              const SizedBox(height: 12),
              _ProfitBreakdownPanel(kpis: kpis),
            ],
          ],
        );
      },
    );
  }
}

class _ProfitBreakdownPanel extends StatelessWidget {
  const _ProfitBreakdownPanel({required this.kpis});
  final KpisData kpis;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 14,
      shadow: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [
            _ProfitBreakdownItem(
              label: 'Bruta',
              value: formatRdCurrencyAccounting(kpis.grossProfit),
              color: _teal,
            ),
            _ProfitBreakdownItem(
              label: 'Gastos',
              value: formatRdCurrencyAccounting(-kpis.totalExpenses),
              color: _gold,
            ),
            _ProfitBreakdownItem(
              label: 'Neta',
              value: formatRdCurrencyAccounting(kpis.netProfit),
              color: kpis.netProfit >= 0 ? _primaryBlue : _error,
            ),
          ];
          final content = constraints.maxWidth >= 720
              ? Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: items[i]),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      items[i],
                    ],
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cómo se calcula la utilidad',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              content,
            ],
          );
        },
      ),
    );
  }
}

class _ProfitBreakdownItem extends StatelessWidget {
  const _ProfitBreakdownItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileReportsContent extends StatelessWidget {
  const _MobileReportsContent({
    required this.kpis,
    required this.salesSeries,
    required this.profitSeries,
    required this.paymentMethods,
    required this.topProducts,
    required this.topClients,
    required this.sales,
  });

  final KpisData kpis;
  final List<SeriesDataPoint> salesSeries;
  final List<SeriesDataPoint> profitSeries;
  final List<PaymentMethodData> paymentMethods;
  final List<TopProduct> topProducts;
  final List<TopClient> topClients;
  final List<SaleModel> sales;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: ReportsFinancialKpiCards(kpis: kpis),
        ),
        _FlatSection(
          title: 'Ritmo de ventas',
          child: SizedBox(
            height: 180,
            child: SalesBarChart(data: salesSeries, barColor: _primaryBlue),
          ),
        ),
        _FlatSection(
          title: 'Utilidad bruta',
          child: SizedBox(
            height: 160,
            child: ProfitLineChart(data: profitSeries),
          ),
        ),
        _FlatSection(
          title: 'Métodos de pago',
          child: SizedBox(
            height: 220,
            child: PaymentMethodPieChart(data: paymentMethods),
          ),
        ),
        _MobileRankingSection(
          title: 'Productos más vendidos',
          rows: [
            for (var i = 0; i < topProducts.length; i++)
              _MobileRankingData(
                rank: i + 1,
                title: topProducts[i].productName,
                subtitle: topProducts[i].totalQtyLabel,
                value: formatRdCurrencyAccounting(topProducts[i].totalSales),
              ),
          ],
        ),
        _MobileRankingSection(
          title: 'Clientes top',
          rows: [
            for (var i = 0; i < topClients.length; i++)
              _MobileRankingData(
                rank: i + 1,
                title: topClients[i].clientName,
                subtitle: '${topClients[i].purchaseCount} compras',
                value: formatRdCurrencyAccounting(topClients[i].totalSpent),
              ),
          ],
        ),
        _RecentSalesTable(sales: sales),
      ],
    );
  }
}

class _FlatSection extends StatelessWidget {
  const _FlatSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MobileRankingData {
  const _MobileRankingData({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String value;
}

class _MobileRankingSection extends StatelessWidget {
  const _MobileRankingSection({required this.title, required this.rows});

  final String title;
  final List<_MobileRankingData> rows;

  @override
  Widget build(BuildContext context) {
    return _FlatSection(
      title: title,
      child: rows.isEmpty
          ? const SizedBox(height: 80, child: _EmptyChart())
          : Column(
              children: [
                for (final row in rows.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '#${row.rank}',
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
                                row.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                row.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          row.value,
                          style: const TextStyle(
                            color: _primaryBlue,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
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
                    subtitle: products[i].totalQtyLabel,
                    trailing: formatRdCurrencyAccounting(
                      products[i].totalSales,
                    ),
                  ),
              ],
            ),
    );
  }
}

class CategoryProfitTable extends StatelessWidget {
  const CategoryProfitTable({super.key, required this.categories});
  final List<CategoryProfitData> categories;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return _PremiumCard(
      title: 'Ganancia por categoría',
      child: categories.isEmpty
          ? const _EmptyChart()
          : Column(
              children: [
                for (var i = 0; i < categories.length; i++) ...[
                  _CategoryProfitRow(data: categories[i], mobile: mobile),
                  if (i != categories.length - 1) const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}

class _CategoryProfitRow extends StatelessWidget {
  const _CategoryProfitRow({required this.data, required this.mobile});
  final CategoryProfitData data;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final content = [
      _CategoryMetric(
        label: 'Ventas',
        value: formatRdCurrencyAccounting(data.totalSales),
      ),
      _CategoryMetric(
        label: 'Costo',
        value: formatRdCurrencyAccounting(data.totalCost),
      ),
      _CategoryMetric(
        label: 'Ganancia',
        value: formatRdCurrencyAccounting(data.totalProfit),
        color: data.totalProfit >= 0 ? _teal : _error,
      ),
      _CategoryMetric(
        label: 'Margen bruto',
        value: '${data.margin.toStringAsFixed(1)}%',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.category_outlined,
                color: _teal,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${data.salesCount} ventas',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        mobile
            ? Wrap(spacing: 8, runSpacing: 8, children: content)
            : Row(
                children: [
                  for (var i = 0; i < content.length; i++) ...[
                    Expanded(child: content[i]),
                    if (i != content.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
      ],
    );
  }
}

class _CategoryMetric extends StatelessWidget {
  const _CategoryMetric({
    required this.label,
    required this.value,
    this.color = _textPrimary,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _pageBg,
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
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
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

/// Estado vacío del periodo: NO es un error. Se muestra cuando el rango y la
/// categoría seleccionados no tienen ventas; los KPIs permanecen en RD$0.00 y
/// el usuario puede seguir cambiando fecha/categoría.
class _EmptyPeriodNotice extends StatelessWidget {
  const _EmptyPeriodNotice();

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.all(16),
      radius: 14,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: _primaryBlue,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No hay ventas para este período',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  'Puedes cambiar la fecha o la categoría para ver otros resultados.',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ],
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
    super.key,
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
    return _Surface(
      padding: const EdgeInsets.all(11),
      radius: 14,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
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
  final parsed = switch (value) {
    num v => v.toDouble(),
    null => 0.0,
    _ => double.tryParse(value.toString()) ?? 0,
  };
  // Fase 33: nunca propagar NaN/Infinity a la UI ni al PDF.
  if (!parsed.isFinite) return 0;
  // Normaliza -0.0 para que no se muestre como "-RD$0.00".
  return parsed == 0 ? 0 : parsed;
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
          totalQtyLabel:
              (row['totalQtyLabel'] ?? '${_toDouble(row['totalQty'])}')
                  .toString(),
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

List<CategoryProfitData> _parseCategoryProfits(dynamic raw) {
  final rows = raw is List ? raw : const [];
  return rows
      .whereType<Map>()
      .map(
        (row) => CategoryProfitData(
          category: (row['category'] ?? 'Sin categoria').toString(),
          totalSales: _toDouble(row['totalSales']),
          totalCost: _toDouble(row['totalCost']),
          totalProfit: _toDouble(row['totalProfit']),
          totalQty: _toDouble(row['totalQty']),
          totalQtyLabel:
              (row['totalQtyLabel'] ?? '${_toDouble(row['totalQty'])}')
                  .toString(),
          salesCount: (row['salesCount'] as num?)?.toInt() ?? 0,
        ),
      )
      .where((row) => row.category.trim().isNotEmpty)
      .toList(growable: false);
}

List<String> _parseCategories(dynamic raw) {
  final rows = raw is List ? raw : const [];
  final categories = rows
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
  categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return categories;
}

List<SaleModel> _projectSalesByCategory(
  List<SaleModel> sales,
  String? selectedCategory,
) {
  final category = (selectedCategory ?? '').trim().toLowerCase();
  if (category.isEmpty) return sales;
  final projected = <SaleModel>[];
  for (final sale in sales) {
    final items = sale.items
        .where((item) => item.categoryLabel.trim().toLowerCase() == category)
        .toList(growable: false);
    if (items.isEmpty) continue;
    final totalSold = items.fold(0.0, (sum, item) => sum + item.subtotalSold);
    final totalCost = items.fold(0.0, (sum, item) => sum + item.subtotalCost);
    final totalProfit = items.fold(0.0, (sum, item) => sum + item.profit);
    final saleSold = sale.totalSold;
    final allocation = saleSold > 0 ? totalSold / saleSold : 0.0;
    projected.add(
      SaleModel(
        id: sale.id,
        userId: sale.userId,
        userName: sale.userName,
        customerId: sale.customerId,
        customerName: sale.customerName,
        customerPhone: sale.customerPhone,
        saleDate: sale.saleDate,
        note: sale.note,
        totalSold: totalSold,
        totalCost: totalCost,
        totalProfit: totalProfit,
        commissionAmount: sale.commissionAmount * allocation,
        paymentMethod: sale.paymentMethod,
        paymentCashAmount: sale.paymentCashAmount * allocation,
        paymentTransferAmount: sale.paymentTransferAmount * allocation,
        creditAmount: sale.creditAmount * allocation,
        creditPaidAmount: sale.creditPaidAmount * allocation,
        creditBalance: sale.creditBalance * allocation,
        creditStatus: sale.creditStatus,
        isDeleted: sale.isDeleted,
        deletedAt: sale.deletedAt,
        items: items,
      ),
    );
  }
  return projected;
}
