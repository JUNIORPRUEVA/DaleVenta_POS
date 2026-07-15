import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../../modules/ventas/data/ventas_repository.dart';
import '../../modules/ventas/sales_models.dart';

enum _AdminSalesMenuAction { filters, sync, panel, resetQuincena }

class AdminSalesRegistryScreen extends ConsumerStatefulWidget {
  const AdminSalesRegistryScreen({super.key});

  @override
  ConsumerState<AdminSalesRegistryScreen> createState() =>
      _AdminSalesRegistryScreenState();
}

class _AdminSalesRegistryScreenState
    extends ConsumerState<AdminSalesRegistryScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showSummaryPanel = true;
  UserFacingError? _error;
  AdminSalesUsersSummary _summary = AdminSalesUsersSummary.empty();
  late DateTime _from;
  late DateTime _to;
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
    final initialRange = _currentSalesQuincenaRange();
    _from = initialRange.from;
    _to = initialRange.to;
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _autoRetryTimer?.cancel();

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _autoRetryCountdown = 0;
      });
    }

    try {
      final repo = ref.read(ventasRepositoryProvider);
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      final summary = await repo.adminSummaryByUser(from: from, to: to);
      if (!mounted) return;

      setState(() {
        _summary = summary;
        _autoRetryAttempt = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
      _scheduleAutoRetryIfNeeded();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAutoRetryIfNeeded() {
    final error = _error;
    if (error == null || !error.autoRetry) return;
    if (_autoRetryAttempt >= _autoRetrySecondsByAttempt.length) return;

    _autoRetryTimer?.cancel();
    final seconds = _autoRetrySecondsByAttempt[_autoRetryAttempt];
    setState(() => _autoRetryCountdown = seconds);

    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoRetryCountdown <= 1) {
        timer.cancel();
        _autoRetryAttempt += 1;
        unawaited(_load());
        return;
      }
      setState(() => _autoRetryCountdown -= 1);
    });
  }

  Future<void> _retryNow() async {
    _autoRetryTimer?.cancel();
    if (mounted) setState(() => _autoRetryCountdown = 0);
    await _load();
  }

  Future<void> _resetToCurrentQuincena() async {
    final next = _currentSalesQuincenaRange();
    setState(() {
      _from = next.from;
      _to = next.to;
    });
    await _load();
  }

  String _money(double value) => formatRdCurrencyAccounting(value);

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(Routes.administracion);
  }

  Future<void> _handleMenuAction(_AdminSalesMenuAction action) async {
    switch (action) {
      case _AdminSalesMenuAction.filters:
        await _pickDateRange();
        break;
      case _AdminSalesMenuAction.sync:
        await _load();
        break;
      case _AdminSalesMenuAction.panel:
        if (!mounted) return;
        setState(() => _showSummaryPanel = !_showSummaryPanel);
        break;
      case _AdminSalesMenuAction.resetQuincena:
        await _resetToCurrentQuincena();
        break;
    }
  }

  List<AdminSalesUserSummary> get _visibleUsers {
    final query = _searchCtrl.text.trim().toLowerCase();
    final rows = _summary.items;
    if (query.isEmpty) return rows;

    return rows.where((item) {
      return item.displayName.toLowerCase().contains(query) ||
          item.userEmail.toLowerCase().contains(query) ||
          item.userId.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _openUserDetail(AdminSalesUserSummary summary) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdminSalesUserDetailScreen(
          user: summary,
          initialFrom: _from,
          initialTo: _to,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleUsers;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = constraints.maxWidth < 700;

            return Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Regresar',
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Buscar usuario',
                                prefixIcon: const Icon(Icons.search_rounded),
                                filled: true,
                                fillColor: scheme.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isPhone)
                            PopupMenuButton<_AdminSalesMenuAction>(
                              tooltip: 'Opciones',
                              onSelected: _handleMenuAction,
                              itemBuilder: (context) => [
                                const PopupMenuItem<_AdminSalesMenuAction>(
                                  value: _AdminSalesMenuAction.filters,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.date_range_rounded,
                                    label: 'Intervalo',
                                  ),
                                ),
                                const PopupMenuItem<_AdminSalesMenuAction>(
                                  value: _AdminSalesMenuAction.resetQuincena,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.calendar_month_rounded,
                                    label: 'Quincena actual',
                                  ),
                                ),
                                const PopupMenuItem<_AdminSalesMenuAction>(
                                  value: _AdminSalesMenuAction.sync,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.sync_rounded,
                                    label: 'Sincronizar',
                                  ),
                                ),
                                PopupMenuItem<_AdminSalesMenuAction>(
                                  value: _AdminSalesMenuAction.panel,
                                  child: _AdminTopMenuItem(
                                    icon: _showSummaryPanel
                                        ? Icons.space_dashboard_rounded
                                        : Icons.space_dashboard_outlined,
                                    label: _showSummaryPanel
                                        ? 'Ocultar panel'
                                        : 'Mostrar panel',
                                  ),
                                ),
                              ],
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.more_vert_rounded),
                              ),
                            )
                          else ...[
                            _CompactTopActionButton(
                              icon: Icons.date_range_rounded,
                              tooltip: 'Intervalo',
                              onTap: _pickDateRange,
                            ),
                            const SizedBox(width: 6),
                            _CompactTopActionButton(
                              icon: Icons.calendar_month_rounded,
                              tooltip: 'Quincena actual',
                              onTap: _resetToCurrentQuincena,
                            ),
                            const SizedBox(width: 6),
                            _CompactTopActionButton(
                              icon: Icons.sync_rounded,
                              tooltip: 'Sincronizar',
                              onTap: _load,
                            ),
                            const SizedBox(width: 6),
                            _CompactTopActionButton(
                              icon: _showSummaryPanel
                                  ? Icons.space_dashboard_rounded
                                  : Icons.space_dashboard_outlined,
                              tooltip: 'Panel',
                              onTap: () => setState(
                                () => _showSummaryPanel = !_showSummaryPanel,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_showSummaryPanel) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _AdminSalesCompactStat(
                                  label: 'Ventas',
                                  value: _money(_summary.totals.totalSold),
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _AdminSalesCompactStat(
                                  label: 'Puntos',
                                  value: _money(_summary.totals.totalProfit),
                                  icon: Icons.stars_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? ProfessionalRecoveryCard(
                          error: _error!,
                          autoRetryCountdown: _autoRetryCountdown > 0
                              ? _autoRetryCountdown
                              : null,
                          isRetrying: _loading,
                          onRetryNow: _retryNow,
                        )
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                'No hay ventas por usuario para mostrar en este período.',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  final accentColor = item.totalProfit >= 0
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFFB91C1C);

                                  return _AdminSalesUserCard(
                                    summary: item,
                                    accentColor: accentColor,
                                    dateRangeLabel:
                                        '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                    soldLabel: _money(item.totalSold),
                                    pointsLabel: _money(item.totalProfit),
                                    salesCountLabel: '${item.totalSales} ventas',
                                    onTap: () => _openUserDetail(item),
                                  );
                                },
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

class _AdminSalesUserDetailScreen extends ConsumerStatefulWidget {
  const _AdminSalesUserDetailScreen({
    required this.user,
    required this.initialFrom,
    required this.initialTo,
  });

  final AdminSalesUserSummary user;
  final DateTime initialFrom;
  final DateTime initialTo;

  @override
  ConsumerState<_AdminSalesUserDetailScreen> createState() =>
      _AdminSalesUserDetailScreenState();
}

class _AdminSalesUserDetailScreenState
    extends ConsumerState<_AdminSalesUserDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showHeaderPanel = true;
  UserFacingError? _error;
  List<SaleModel> _items = const <SaleModel>[];
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(ventasRepositoryProvider);
      final items = await repo.adminListSalesByUser(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day),
        userId: widget.user.userId,
      );
      if (!mounted) return;
      setState(() {
        _items = items..sort(_sortSalesByDateDesc);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sortSalesByDateDesc(SaleModel a, SaleModel b) {
    final aDate = a.saleDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.saleDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  Future<void> _resetToCurrentQuincena() async {
    final next = _currentSalesQuincenaRange();
    setState(() {
      _from = next.from;
      _to = next.to;
    });
    await _load();
  }

  List<SaleModel> get _visibleSales {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _items;

    return _items.where((item) {
      final dateText = item.saleDate == null
          ? ''
          : DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.saleDate!.toLocal());
      return (item.customerName ?? '').toLowerCase().contains(query) ||
          (item.note ?? '').toLowerCase().contains(query) ||
          item.id.toLowerCase().contains(query) ||
          dateText.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  SalesSummaryModel get _detailSummary {
    return SalesSummaryModel(
      totalSales: _visibleSales.length,
      totalSold: _visibleSales.fold<double>(0, (sum, item) => sum + item.totalSold),
      totalCost: _visibleSales.fold<double>(0, (sum, item) => sum + item.totalCost),
      totalProfit: _visibleSales.fold<double>(0, (sum, item) => sum + item.totalProfit),
      totalCommission: _visibleSales.fold<double>(
        0,
        (sum, item) => sum + item.commissionAmount,
      ),
    );
  }

  String _money(double value) => formatRdCurrencyAccounting(value);

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  bool get _isQuincenaRange => _rangeLooksLikeQuincena(_from, _to);

  String get _activeFilterLabel => _isQuincenaRange
      ? _salesRangeLabel(_from, _to)
      : 'Intervalo personalizado';

  void _openSaleDetail(SaleModel sale) {
    final dateText = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(sale.saleDate!.toLocal());

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detalle de venta'),
          content: SizedBox(
            width: 400,
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
                    dateText,
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
                  ...sale.items.map(
                    (item) => Padding(
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
                    ),
                  ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleSales;
    final summary = _detailSummary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Regresar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Buscar venta o cliente',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: scheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _CompactTopActionButton(
                        icon: Icons.date_range_rounded,
                        tooltip: 'Intervalo',
                        onTap: _pickDateRange,
                      ),
                      const SizedBox(width: 6),
                      _CompactTopActionButton(
                        icon: Icons.calendar_month_rounded,
                        tooltip: 'Quincena actual',
                        onTap: _resetToCurrentQuincena,
                      ),
                      const SizedBox(width: 6),
                      _CompactTopActionButton(
                        icon: _showHeaderPanel
                            ? Icons.space_dashboard_rounded
                            : Icons.space_dashboard_outlined,
                        tooltip: 'Panel',
                        onTap: () => setState(
                          () => _showHeaderPanel = !_showHeaderPanel,
                        ),
                      ),
                    ],
                  ),
                  if (_showHeaderPanel) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (widget.user.userEmail.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.user.userEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
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
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: 0.58,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _activeFilterLabel,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: scheme.onSurface,
                                          ),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _AdminSalesFilterPill(
                                      label: 'Quincena',
                                      selected: _isQuincenaRange,
                                      onTap: _resetToCurrentQuincena,
                                    ),
                                    _AdminSalesFilterPill(
                                      label: 'Intervalo',
                                      selected: !_isQuincenaRange,
                                      onTap: _pickDateRange,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _AdminSalesInfoChip(
                                icon: Icons.receipt_long_outlined,
                                label: 'Ventas',
                                value: '${summary.totalSales}',
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.payments_outlined,
                                label: 'Total vendido',
                                value: _money(summary.totalSold),
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.stars_rounded,
                                label: 'Puntos',
                                value: _money(summary.totalProfit),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? ProfessionalRecoveryCard(
                      error: _error!,
                      autoRetryCountdown: null,
                      isRetrying: _loading,
                      onRetryNow: _load,
                    )
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            'No hay ventas para este filtro.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final sale = visible[index];
                              return _AdminSaleItemCard(
                                sale: sale,
                                moneyText: _money,
                                dateText: sale.saleDate == null
                                    ? 'Sin fecha'
                                    : DateFormat(
                                        'dd/MM/yyyy h:mm a',
                                        'es_DO',
                                      ).format(sale.saleDate!.toLocal()),
                                onTap: () => _openSaleDetail(sale),
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

class _AdminTopMenuItem extends StatelessWidget {
  const _AdminTopMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CompactTopActionButton extends StatelessWidget {
  const _CompactTopActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}

class _AdminSalesUserCard extends StatelessWidget {
  const _AdminSalesUserCard({
    required this.summary,
    required this.accentColor,
    required this.dateRangeLabel,
    required this.soldLabel,
    required this.pointsLabel,
    required this.salesCountLabel,
    required this.onTap,
  });

  final AdminSalesUserSummary summary;
  final Color accentColor;
  final String dateRangeLabel;
  final String soldLabel;
  final String pointsLabel;
  final String salesCountLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (summary.userEmail.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary.userEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _AdminSalesInlineChip(
                          label: 'Vendido',
                          value: soldLabel,
                        ),
                        _AdminSalesInlineChip(
                          label: 'Puntos',
                          value: pointsLabel,
                        ),
                        _AdminSalesInlineChip(
                          label: 'Ventas',
                          value: salesCountLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      dateRangeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSaleItemCard extends StatelessWidget {
  const _AdminSaleItemCard({
    required this.sale,
    required this.moneyText,
    required this.dateText,
    required this.onTap,
  });

  final SaleModel sale;
  final String Function(double value) moneyText;
  final String dateText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.customerName?.trim().isNotEmpty == true
                          ? sale.customerName!
                          : 'Cliente no especificado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if ((sale.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sale.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    moneyText(sale.totalSold),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Puntos: ${moneyText(sale.totalProfit)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSalesInlineChip extends StatelessWidget {
  const _AdminSalesInlineChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · $value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _AdminSalesInfoChip extends StatelessWidget {
  const _AdminSalesInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminSalesCompactStat extends StatelessWidget {
  const _AdminSalesCompactStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSalesFilterPill extends StatelessWidget {
  const _AdminSalesFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.88)
          : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

SalesDateRange _currentSalesQuincenaRange([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  final current = DateTime(now.year, now.month, now.day);

  if (current.day <= 14) {
    final previousMonthEnd = DateTime(current.year, current.month, 0);
    return SalesDateRange(
      from: DateTime(
        previousMonthEnd.year,
        previousMonthEnd.month,
        previousMonthEnd.day,
      ),
      to: DateTime(current.year, current.month, 14),
    );
  }

  if (current.day <= 29) {
    return SalesDateRange(
      from: DateTime(current.year, current.month, 15),
      to: DateTime(current.year, current.month, 29),
    );
  }

  final monthEnd = DateTime(current.year, current.month + 1, 0);
  final startDay = current.day == 30 ? 30 : monthEnd.day;
  return SalesDateRange(
    from: DateTime(current.year, current.month, startDay),
    to: DateTime(current.year, current.month + 1, 14),
  );
}

String _salesRangeLabel(DateTime from, DateTime to) {
  if (from.day == 15 && to.day == 29) {
    return 'Quincena 15 - 29';
  }
  if (to.day == 14) {
    return 'Quincena cierre 14';
  }
  return 'Intervalo personalizado';
}

bool _rangeLooksLikeQuincena(DateTime from, DateTime to) {
  return (from.day == 15 && to.day == 29) || to.day == 14;
}
