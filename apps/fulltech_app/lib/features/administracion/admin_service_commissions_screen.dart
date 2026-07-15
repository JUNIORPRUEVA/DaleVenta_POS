import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/models/user_model.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../../features/user/data/users_repository.dart';
import '../../modules/clientes/cliente_model.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/service_orders/commissions_models.dart';
import '../../modules/service_orders/data/service_order_commissions_api.dart';
import '../../modules/service_orders/data/service_orders_api.dart';
import '../../modules/service_orders/data/service_orders_local_repository.dart';
import '../../modules/service_orders/service_order_models.dart';

enum _AdminServiceMenuAction { filters, sync, panel, resetQuincena }

class AdminServiceCommissionsScreen extends ConsumerStatefulWidget {
  const AdminServiceCommissionsScreen({super.key});

  @override
  ConsumerState<AdminServiceCommissionsScreen> createState() =>
      _AdminServiceCommissionsScreenState();
}

class _AdminServiceCommissionsScreenState
    extends ConsumerState<AdminServiceCommissionsScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showSummaryPanel = true;
  UserFacingError? _error;
  AdminServiceCommissionUsersSummary _summary =
      AdminServiceCommissionUsersSummary.empty();
  late DateTime _from;
  late DateTime _to;
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
    final initialRange = _currentAdminCommissionQuincenaRange();
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
      final repo = ref.read(serviceOrderCommissionsApiProvider);
      final fallbackRepo = _AdminServiceCommissionFallbackRepository(ref);
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      AdminServiceCommissionUsersSummary summary;
      try {
        final remoteSummary = await repo.adminSummaryByUser(from: from, to: to);
        final localSummary = await fallbackRepo.loadSummary(from: from, to: to);
        summary = _mergeSummaryWithLocal(remoteSummary, localSummary);
      } catch (_) {
        summary = await fallbackRepo.loadSummary(from: from, to: to);
      }
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
    final next = _currentAdminCommissionQuincenaRange();
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

  Future<void> _handleMenuAction(_AdminServiceMenuAction action) async {
    switch (action) {
      case _AdminServiceMenuAction.filters:
        await _pickDateRange();
        break;
      case _AdminServiceMenuAction.sync:
        await _load();
        break;
      case _AdminServiceMenuAction.panel:
        if (!mounted) return;
        setState(() => _showSummaryPanel = !_showSummaryPanel);
        break;
      case _AdminServiceMenuAction.resetQuincena:
        await _resetToCurrentQuincena();
        break;
    }
  }

  List<AdminServiceCommissionUserSummary> get _visibleUsers {
    final query = _searchCtrl.text.trim().toLowerCase();
    final rows = _summary.items;
    if (query.isEmpty) return rows;

    return rows
        .where((item) {
          return item.displayName.toLowerCase().contains(query) ||
              item.userEmail.toLowerCase().contains(query) ||
              item.userId.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openUserDetail(
    AdminServiceCommissionUserSummary summary,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdminServiceUserDetailScreen(
          user: summary,
          initialFrom: _from,
          initialTo: _to,
        ),
      ),
    );
  }

  AdminServiceCommissionUsersSummary _mergeSummaryWithLocal(
    AdminServiceCommissionUsersSummary remote,
    AdminServiceCommissionUsersSummary local,
  ) {
    final remoteById = {
      for (final item in remote.items) item.userId.trim(): item,
    };
    final localById = {
      for (final item in local.items) item.userId.trim(): item,
    };
    final userIds = <String>{...remoteById.keys, ...localById.keys};

    final mergedItems =
        userIds
            .map((userId) {
              final remoteItem = remoteById[userId];
              final localItem = localById[userId];
              final base = remoteItem ?? localItem!;
              final localPoints = localItem?.totalPoints ?? 0;
              return AdminServiceCommissionUserSummary(
                userId: base.userId,
                userName: base.userName,
                userEmail: base.userEmail,
                totalServices: base.totalServices,
                installationCount: base.installationCount,
                maintenanceCount: base.maintenanceCount,
                totalSold: base.totalSold,
                totalPoints: localPoints > 0 ? localPoints : base.totalPoints,
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            final pointsOrder = right.totalPoints.compareTo(left.totalPoints);
            if (pointsOrder != 0) return pointsOrder;
            return right.totalSold.compareTo(left.totalSold);
          });

    return AdminServiceCommissionUsersSummary(
      items: mergedItems,
      totals: AdminServiceCommissionTotals(
        totalServices: mergedItems.fold<int>(
          0,
          (sum, item) => sum + item.totalServices,
        ),
        totalInstallations: mergedItems.fold<int>(
          0,
          (sum, item) => sum + item.installationCount,
        ),
        totalMaintenances: mergedItems.fold<int>(
          0,
          (sum, item) => sum + item.maintenanceCount,
        ),
        totalSold: mergedItems.fold<double>(
          0,
          (sum, item) => sum + item.totalSold,
        ),
        totalPoints: mergedItems.fold<double>(
          0,
          (sum, item) => sum + item.totalPoints,
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
                            PopupMenuButton<_AdminServiceMenuAction>(
                              tooltip: 'Opciones',
                              onSelected: _handleMenuAction,
                              itemBuilder: (context) => [
                                const PopupMenuItem<_AdminServiceMenuAction>(
                                  value: _AdminServiceMenuAction.filters,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.date_range_rounded,
                                    label: 'Intervalo',
                                  ),
                                ),
                                const PopupMenuItem<_AdminServiceMenuAction>(
                                  value: _AdminServiceMenuAction.resetQuincena,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.calendar_month_rounded,
                                    label: 'Quincena actual',
                                  ),
                                ),
                                const PopupMenuItem<_AdminServiceMenuAction>(
                                  value: _AdminServiceMenuAction.sync,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.sync_rounded,
                                    label: 'Sincronizar',
                                  ),
                                ),
                                PopupMenuItem<_AdminServiceMenuAction>(
                                  value: _AdminServiceMenuAction.panel,
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
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumen del período',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _AdminSalesCompactStat(
                                      label: 'Servicios',
                                      value: '${_summary.totals.totalServices}',
                                      icon: Icons.assignment_turned_in_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _AdminSalesCompactStat(
                                      label: 'Instalación',
                                      value:
                                          '${_summary.totals.totalInstallations}',
                                      icon: Icons.build_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _AdminSalesCompactStat(
                                      label: 'Mantenimiento',
                                      value:
                                          '${_summary.totals.totalMaintenances}',
                                      icon: Icons.settings_suggest_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _AdminSalesCompactStat(
                                      label: 'Ventas total',
                                      value: _money(_summary.totals.totalSold),
                                      icon: Icons.payments_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _AdminSalesCompactStat(
                                      label: 'Puntos utilidad',
                                      value: _money(
                                        _summary.totals.totalPoints,
                                      ),
                                      icon: Icons.stars_rounded,
                                    ),
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
                          autoRetryCountdown: _autoRetryCountdown > 0
                              ? _autoRetryCountdown
                              : null,
                          isRetrying: _loading,
                          onRetryNow: _retryNow,
                        )
                      : visible.isEmpty
                      ? Center(
                          child: Text(
                            'No hay servicios por usuario para mostrar en este período.',
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              final accentColor = item.totalPoints >= 0
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFB91C1C);

                              return _AdminServiceUserCard(
                                summary: item,
                                accentColor: accentColor,
                                dateRangeLabel:
                                    '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                soldLabel: _money(item.totalSold),
                                pointsLabel: _money(item.totalPoints),
                                servicesCountLabel:
                                    '${item.totalServices} servicios',
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

class _AdminServiceUserDetailScreen extends ConsumerStatefulWidget {
  const _AdminServiceUserDetailScreen({
    required this.user,
    required this.initialFrom,
    required this.initialTo,
  });

  final AdminServiceCommissionUserSummary user;
  final DateTime initialFrom;
  final DateTime initialTo;

  @override
  ConsumerState<_AdminServiceUserDetailScreen> createState() =>
      _AdminServiceUserDetailScreenState();
}

class _AdminServiceUserDetailScreenState
    extends ConsumerState<_AdminServiceUserDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showHeaderPanel = true;
  UserFacingError? _error;
  List<ServiceOrderCommissionItem> _items =
      const <ServiceOrderCommissionItem>[];
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
      final repo = ref.read(serviceOrderCommissionsApiProvider);
      final fallbackRepo = _AdminServiceCommissionFallbackRepository(ref);
      List<ServiceOrderCommissionItem> items;
      try {
        final remoteItems = await repo.adminListByUser(
          from: DateTime(_from.year, _from.month, _from.day),
          to: DateTime(_to.year, _to.month, _to.day),
          userId: widget.user.userId,
        );
        final localItems = await fallbackRepo.loadUserItems(
          from: DateTime(_from.year, _from.month, _from.day),
          to: DateTime(_to.year, _to.month, _to.day),
          userId: widget.user.userId,
        );
        items = _mergeItemsWithLocal(remoteItems, localItems);
      } catch (_) {
        items = await fallbackRepo.loadUserItems(
          from: DateTime(_from.year, _from.month, _from.day),
          to: DateTime(_to.year, _to.month, _to.day),
          userId: widget.user.userId,
        );
      }
      if (!mounted) return;
      setState(() {
        _items = items..sort(_sortServicesByDateDesc);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sortServicesByDateDesc(
    ServiceOrderCommissionItem a,
    ServiceOrderCommissionItem b,
  ) {
    final aDate = a.finalizedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.finalizedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  List<ServiceOrderCommissionItem> _mergeItemsWithLocal(
    List<ServiceOrderCommissionItem> remoteItems,
    List<ServiceOrderCommissionItem> localItems,
  ) {
    final remoteById = {for (final item in remoteItems) item.id: item};
    final localById = {for (final item in localItems) item.id: item};
    final ids = <String>{...remoteById.keys, ...localById.keys};

    return ids
        .map((id) {
          final remote = remoteById[id];
          final local = localById[id];
          final base = remote ?? local!;
          final localPoints = local?.totalCommissionAmount ?? 0;
          return ServiceOrderCommissionItem(
            id: base.id,
            clientId: base.clientId,
            clientName: base.clientName,
            quotationId: base.quotationId,
            createdById: base.createdById,
            createdByName: base.createdByName,
            technicianId: base.technicianId,
            technicianName: base.technicianName,
            serviceType: base.serviceType,
            status: base.status,
            finalizedAt: base.finalizedAt,
            totalAmount: base.totalAmount,
            sellerCommissionAmount: localPoints > 0
                ? (local?.sellerCommissionAmount ?? base.sellerCommissionAmount)
                : base.sellerCommissionAmount,
            technicianCommissionAmount: localPoints > 0
                ? (local?.technicianCommissionAmount ??
                      base.technicianCommissionAmount)
                : base.technicianCommissionAmount,
            visibleCommissionAmount: localPoints > 0
                ? (local?.visibleCommissionAmount ??
                      base.visibleCommissionAmount)
                : base.visibleCommissionAmount,
            totalCommissionAmount: localPoints > 0
                ? localPoints
                : base.totalCommissionAmount,
          );
        })
        .toList(growable: false);
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
    final next = _currentAdminCommissionQuincenaRange();
    setState(() {
      _from = next.from;
      _to = next.to;
    });
    await _load();
  }

  List<ServiceOrderCommissionItem> get _visibleItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _items;

    return _items
        .where((item) {
          final dateText = item.finalizedAt == null
              ? ''
              : DateFormat(
                  'dd/MM/yyyy h:mm a',
                  'es_DO',
                ).format(item.finalizedAt!.toLocal());
          return item.clientName.toLowerCase().contains(query) ||
              item.id.toLowerCase().contains(query) ||
              item.quotationId.toLowerCase().contains(query) ||
              item.serviceType.toLowerCase().contains(query) ||
              (item.createdByName).toLowerCase().contains(query) ||
              (item.technicianName ?? '').toLowerCase().contains(query) ||
              dateText.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  AdminServiceCommissionTotals get _detailSummary {
    return AdminServiceCommissionTotals(
      totalServices: _visibleItems.length,
      totalInstallations: _visibleItems
          .where(
            (item) => item.serviceType.trim().toLowerCase() == 'instalacion',
          )
          .length,
      totalMaintenances: _visibleItems
          .where(
            (item) => item.serviceType.trim().toLowerCase() == 'mantenimiento',
          )
          .length,
      totalSold: _visibleItems.fold<double>(
        0,
        (sum, item) => sum + item.totalAmount,
      ),
      totalPoints: _visibleItems.fold<double>(
        0,
        (sum, item) => sum + item.totalCommissionAmount,
      ),
    );
  }

  String _money(double value) => formatRdCurrencyAccounting(value);

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  bool get _isQuincenaRange =>
      _rangeLooksLikeAdminCommissionQuincena(_from, _to);

  String get _activeFilterLabel => _isQuincenaRange
      ? _adminCommissionRangeLabel(_from, _to)
      : 'Intervalo personalizado';

  String _serviceTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'instalacion':
        return 'Instalación';
      case 'mantenimiento':
        return 'Mantenimiento';
      default:
        return value;
    }
  }

  void _openServiceDetail(ServiceOrderCommissionItem item) {
    final dateText = item.finalizedAt == null
        ? 'Sin fecha'
        : DateFormat(
            'dd/MM/yyyy h:mm a',
            'es_DO',
          ).format(item.finalizedAt!.toLocal());

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detalle del servicio'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Orden de servicio: ${item.id}'),
                  Text('Cotización: ${item.quotationId}'),
                  Text('Cliente: ${item.clientName}'),
                  Text('Tipo: ${_serviceTypeLabel(item.serviceType)}'),
                  Text('Fecha finalizado: $dateText'),
                  Text('Vendedor: ${item.createdByName}'),
                  Text(
                    'Técnico: ${(item.technicianName ?? '').trim().isNotEmpty ? item.technicianName! : 'No indicado'}',
                  ),
                  const Divider(height: 18),
                  Text('Número vendido: ${_money(item.totalAmount)}'),
                  Text('Puntos: ${_money(item.totalCommissionAmount)}'),
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
    final visible = _visibleItems;
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
                            hintText: 'Buscar servicio, orden o cliente',
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
                                icon: Icons.assignment_turned_in_outlined,
                                label: 'Servicios finalizados',
                                value: '${summary.totalServices}',
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.build_rounded,
                                label: 'Instalación',
                                value: '${summary.totalInstallations}',
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.settings_suggest_outlined,
                                label: 'Mantenimiento',
                                value: '${summary.totalMaintenances}',
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.payments_outlined,
                                label: 'Número vendido',
                                value: _money(summary.totalSold),
                              ),
                              _AdminSalesInfoChip(
                                icon: Icons.stars_rounded,
                                label: 'Puntos',
                                value: _money(summary.totalPoints),
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
                        'No hay servicios para este filtro.',
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
                          final item = visible[index];
                          return _AdminServiceItemCard(
                            item: item,
                            moneyText: _money,
                            typeLabel: _serviceTypeLabel(item.serviceType),
                            dateText: item.finalizedAt == null
                                ? 'Sin fecha'
                                : DateFormat(
                                    'dd/MM/yyyy h:mm a',
                                    'es_DO',
                                  ).format(item.finalizedAt!.toLocal()),
                            onTap: () => _openServiceDetail(item),
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
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20)),
        ),
      ),
    );
  }
}

class _AdminServiceUserCard extends StatelessWidget {
  const _AdminServiceUserCard({
    required this.summary,
    required this.accentColor,
    required this.dateRangeLabel,
    required this.soldLabel,
    required this.pointsLabel,
    required this.servicesCountLabel,
    required this.onTap,
  });

  final AdminServiceCommissionUserSummary summary;
  final Color accentColor;
  final String dateRangeLabel;
  final String soldLabel;
  final String pointsLabel;
  final String servicesCountLabel;
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
                          label: 'Inst.',
                          value: '${summary.installationCount}',
                        ),
                        _AdminSalesInlineChip(
                          label: 'Mant.',
                          value: '${summary.maintenanceCount}',
                        ),
                        _AdminSalesInlineChip(
                          label: 'Vendido',
                          value: soldLabel,
                        ),
                        _AdminSalesInlineChip(
                          label: 'Puntos',
                          value: pointsLabel,
                        ),
                        _AdminSalesInlineChip(
                          label: 'Servicios',
                          value: servicesCountLabel,
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

class _AdminServiceItemCard extends StatelessWidget {
  const _AdminServiceItemCard({
    required this.item,
    required this.moneyText,
    required this.typeLabel,
    required this.dateText,
    required this.onTap,
  });

  final ServiceOrderCommissionItem item;
  final String Function(double value) moneyText;
  final String typeLabel;
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
                      item.clientName.trim().isNotEmpty
                          ? item.clientName
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
                    const SizedBox(height: 4),
                    Text(
                      '$typeLabel · Orden ${item.id} · Cot. ${item.quotationId}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    moneyText(item.totalAmount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Puntos: ${moneyText(item.totalCommissionAmount)}',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
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

_AdminCommissionDateRange _currentAdminCommissionQuincenaRange([
  DateTime? reference,
]) {
  final now = reference ?? DateTime.now();
  final current = DateTime(now.year, now.month, now.day);

  if (current.day <= 14) {
    final previousMonthEnd = DateTime(current.year, current.month, 0);
    return _AdminCommissionDateRange(
      from: DateTime(
        previousMonthEnd.year,
        previousMonthEnd.month,
        previousMonthEnd.day,
      ),
      to: DateTime(current.year, current.month, 14),
    );
  }

  if (current.day <= 29) {
    return _AdminCommissionDateRange(
      from: DateTime(current.year, current.month, 15),
      to: DateTime(current.year, current.month, 29),
    );
  }

  final monthEnd = DateTime(current.year, current.month + 1, 0);
  final startDay = current.day == 30 ? 30 : monthEnd.day;
  return _AdminCommissionDateRange(
    from: DateTime(current.year, current.month, startDay),
    to: DateTime(current.year, current.month + 1, 14),
  );
}

String _adminCommissionRangeLabel(DateTime from, DateTime to) {
  if (from.day == 15 && to.day == 29) {
    return 'Quincena 15 - 29';
  }
  if (to.day == 14) {
    return 'Quincena cierre 14';
  }
  return 'Intervalo personalizado';
}

bool _rangeLooksLikeAdminCommissionQuincena(DateTime from, DateTime to) {
  return (from.day == 15 && to.day == 29) || to.day == 14;
}

class _AdminCommissionDateRange {
  const _AdminCommissionDateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;
}

class _AdminServiceCommissionFallbackRepository {
  _AdminServiceCommissionFallbackRepository(this.ref);

  final WidgetRef ref;

  Future<AdminServiceCommissionUsersSummary> loadSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final computed = await _buildComputedItems(from: from, to: to);
    final grouped = <String, _AdminUserSummaryAccumulator>{};

    for (final entry in computed) {
      final key = entry.recipientUserId.trim();
      final accumulator = grouped.putIfAbsent(
        key,
        () => _AdminUserSummaryAccumulator(
          userId: key,
          userName: entry.recipientUserName,
          userEmail: entry.recipientUserEmail,
        ),
      );
      accumulator.add(entry.item);
    }

    final items =
        grouped.values.map((entry) => entry.build()).toList(growable: false)
          ..sort((left, right) {
            final points = right.totalPoints.compareTo(left.totalPoints);
            if (points != 0) return points;
            return right.totalSold.compareTo(left.totalSold);
          });

    final totals = AdminServiceCommissionTotals(
      totalServices: computed.length,
      totalInstallations: computed
          .where(
            (entry) =>
                entry.item.serviceType.trim().toLowerCase() == 'instalacion',
          )
          .length,
      totalMaintenances: computed
          .where(
            (entry) =>
                entry.item.serviceType.trim().toLowerCase() == 'mantenimiento',
          )
          .length,
      totalSold: computed.fold<double>(
        0,
        (sum, entry) => sum + entry.item.totalAmount,
      ),
      totalPoints: computed.fold<double>(
        0,
        (sum, entry) => sum + entry.item.totalCommissionAmount,
      ),
    );

    return AdminServiceCommissionUsersSummary(items: items, totals: totals);
  }

  Future<List<ServiceOrderCommissionItem>> loadUserItems({
    required DateTime from,
    required DateTime to,
    required String userId,
  }) async {
    final computed = await _buildComputedItems(from: from, to: to);
    return computed
        .where((entry) => entry.recipientUserId == userId.trim())
        .map((entry) => entry.item)
        .toList(growable: false);
  }

  Future<List<_AdminComputedCommissionItem>> _buildComputedItems({
    required DateTime from,
    required DateTime to,
  }) async {
    final snapshot = await _loadSnapshot();
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    final filteredOrders = snapshot.orders
        .where((order) {
          if (order.status != ServiceOrderStatus.finalizado) return false;
          if (order.serviceType != ServiceOrderType.instalacion &&
              order.serviceType != ServiceOrderType.mantenimiento) {
            return false;
          }
          final finalizedAt = order.finalizedAt;
          if (finalizedAt == null) return false;
          return !finalizedAt.isBefore(start) && !finalizedAt.isAfter(end);
        })
        .toList(growable: false);

    final quotationsById = await _loadQuotationsById(filteredOrders);
    final items = <_AdminComputedCommissionItem>[];

    for (final order in filteredOrders) {
      final quotationId = (order.quotationId ?? '').trim();
      final quotation = quotationId.isEmpty
          ? null
          : quotationsById[quotationId];
      final creator = snapshot.usersById[order.createdById];
      final assignedToId = (order.assignedToId ?? '').trim();
      final technician = assignedToId.isEmpty
          ? null
          : snapshot.usersById[assignedToId];
      final recipient = _resolveRecipient(
        order: order,
        creator: creator,
        technician: technician,
      );
      final clientName =
          (order.client?.nombre ??
                  snapshot.clientsById[order.clientId]?.nombre ??
                  '')
              .trim();
      final commission = _computeCommission(
        quotation: quotation,
        recipientSource: recipient.userId == order.createdById
            ? _CommissionRecipientSource.creator
            : _CommissionRecipientSource.assignedTechnician,
      );

      items.add(
        _AdminComputedCommissionItem(
          recipientUserId: recipient.userId,
          recipientUserName: recipient.userName,
          recipientUserEmail: recipient.userEmail,
          item: ServiceOrderCommissionItem(
            id: order.id,
            clientId: order.clientId,
            clientName: clientName.isEmpty
                ? 'Cliente no especificado'
                : clientName,
            quotationId: quotationId,
            createdById: order.createdById,
            createdByName: (creator?.nombreCompleto ?? order.createdById)
                .trim(),
            technicianId: assignedToId.isEmpty ? null : assignedToId,
            technicianName: (technician?.nombreCompleto ?? '').trim().isEmpty
                ? null
                : technician!.nombreCompleto.trim(),
            serviceType: order.serviceType.apiValue,
            status: order.status.apiValue,
            finalizedAt: order.finalizedAt,
            totalAmount: commission.totalAmount,
            sellerCommissionAmount: commission.sellerCommissionAmount,
            technicianCommissionAmount: commission.technicianCommissionAmount,
            visibleCommissionAmount: commission.totalCommissionAmount,
            totalCommissionAmount: commission.totalCommissionAmount,
          ),
        ),
      );
    }

    return items;
  }

  Future<_AdminFallbackSnapshot> _loadSnapshot() async {
    final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
    final localSnapshot = await localRepository.readSnapshot();
    var orders = localSnapshot.orders.toList(growable: false);
    var clientsById = Map<String, ClienteModel>.from(localSnapshot.clientsById);
    var usersById = Map<String, UserModel>.from(localSnapshot.usersById);

    final needsRemoteOrders = orders.isEmpty;
    final needsRemoteUsers =
        usersById.isEmpty ||
        orders.any((order) {
          final assignedToId = (order.assignedToId ?? '').trim();
          return !usersById.containsKey(order.createdById) ||
              (assignedToId.isNotEmpty && !usersById.containsKey(assignedToId));
        });

    if (needsRemoteOrders || needsRemoteUsers) {
      try {
        if (needsRemoteOrders) {
          orders = await ref.read(serviceOrdersApiProvider).listOrders();
        }
        if (needsRemoteUsers) {
          final users = await ref
              .read(usersRepositoryProvider)
              .getAllUsers(skipLoader: true);
          usersById = {for (final user in users) user.id: user};
        }
        final mergedClientsById = <String, ClienteModel>{...clientsById};
        for (final order in orders) {
          final client = order.client;
          if (client != null) {
            mergedClientsById[client.id] = client;
          }
        }
        clientsById = mergedClientsById;
        if (orders.isNotEmpty) {
          await localRepository.saveSnapshot(
            orders: orders,
            clientsById: clientsById,
            usersById: usersById,
          );
        }
      } catch (_) {
        // Preserve local snapshot when background refresh is unavailable.
      }
    }

    return _AdminFallbackSnapshot(
      orders: orders,
      clientsById: clientsById,
      usersById: usersById,
    );
  }

  Future<Map<String, CotizacionModel>> _loadQuotationsById(
    List<ServiceOrderModel> orders,
  ) async {
    final repository = ref.read(cotizacionesRepositoryProvider);
    final quotationIds = orders
        .map((order) => (order.quotationId ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final entries = await Future.wait(
      quotationIds.map((id) async {
        final cached = await repository.getCachedById(id);
        if (cached != null && _quotationHasUtilityData(cached)) {
          return MapEntry(id, cached);
        }
        try {
          final remote = await repository.getByIdAndCache(id);
          return MapEntry(id, remote);
        } catch (_) {
          return null;
        }
      }),
    );

    return {
      for (final entry in entries)
        if (entry != null) entry.key: entry.value,
    };
  }

  _AdminRecipient _resolveRecipient({
    required ServiceOrderModel order,
    required UserModel? creator,
    required UserModel? technician,
  }) {
    final assignedToId = (order.assignedToId ?? '').trim();
    if (creator?.appRole.isTechnician == true && assignedToId.isNotEmpty) {
      return _AdminRecipient(
        userId: assignedToId,
        userName: (technician?.nombreCompleto ?? assignedToId).trim(),
        userEmail: (technician?.email ?? '').trim(),
      );
    }

    return _AdminRecipient(
      userId: order.createdById,
      userName: (creator?.nombreCompleto ?? order.createdById).trim(),
      userEmail: (creator?.email ?? '').trim(),
    );
  }

  bool _quotationHasUtilityData(CotizacionModel quotation) {
    if (quotation.totalProfit != null) return true;
    if (quotation.totalCost != null) return true;
    if (quotation.items.isEmpty) return false;
    return quotation.items.every(
      (item) =>
          item.subtotalCostSnapshot != null || item.tracedCostUnit != null,
    );
  }

  _LocalCommissionAmounts _computeCommission({
    required CotizacionModel? quotation,
    required _CommissionRecipientSource recipientSource,
  }) {
    if (quotation == null) {
      return const _LocalCommissionAmounts(
        totalAmount: 0,
        sellerCommissionAmount: 0,
        technicianCommissionAmount: 0,
        totalCommissionAmount: 0,
      );
    }

    if (quotation.items.isEmpty) {
      return _LocalCommissionAmounts(
        totalAmount: quotation.total,
        sellerCommissionAmount: 0,
        technicianCommissionAmount: 0,
        totalCommissionAmount: 0,
      );
    }

    var missingCostItemsCount = 0;
    var totalCost = quotation.totalCost ?? 0.0;
    if (quotation.totalCost == null) {
      totalCost = 0;
      for (final item in quotation.items) {
        final subtotalCost = item.subtotalCostSnapshot;
        final costUnit = item.tracedCostUnit;
        if (subtotalCost != null) {
          totalCost += subtotalCost;
          continue;
        }
        if (costUnit == null) {
          missingCostItemsCount += 1;
          continue;
        }
        totalCost += costUnit * item.qty;
      }
    }

    if (missingCostItemsCount > 0) {
      return _LocalCommissionAmounts(
        totalAmount: quotation.total,
        sellerCommissionAmount: 0,
        technicianCommissionAmount: 0,
        totalCommissionAmount: 0,
      );
    }

    final totalProfit = quotation.totalProfit ?? (quotation.total - totalCost);
    final operationalExpenseAmount = totalProfit > 0 ? totalProfit * 0.2 : 0;
    final totalCommissionAmount =
        (totalProfit - operationalExpenseAmount).clamp(0, double.infinity)
            as double;
    final sellerCommissionAmount =
        recipientSource == _CommissionRecipientSource.creator
        ? totalCommissionAmount
        : 0.0;
    final technicianCommissionAmount =
        recipientSource == _CommissionRecipientSource.assignedTechnician
        ? totalCommissionAmount
        : 0.0;

    return _LocalCommissionAmounts(
      totalAmount: quotation.total,
      sellerCommissionAmount: sellerCommissionAmount,
      technicianCommissionAmount: technicianCommissionAmount,
      totalCommissionAmount: totalCommissionAmount,
    );
  }
}

enum _CommissionRecipientSource { creator, assignedTechnician }

class _AdminFallbackSnapshot {
  const _AdminFallbackSnapshot({
    required this.orders,
    required this.clientsById,
    required this.usersById,
  });

  final List<ServiceOrderModel> orders;
  final Map<String, ClienteModel> clientsById;
  final Map<String, UserModel> usersById;
}

class _AdminComputedCommissionItem {
  const _AdminComputedCommissionItem({
    required this.recipientUserId,
    required this.recipientUserName,
    required this.recipientUserEmail,
    required this.item,
  });

  final String recipientUserId;
  final String recipientUserName;
  final String recipientUserEmail;
  final ServiceOrderCommissionItem item;
}

class _AdminRecipient {
  const _AdminRecipient({
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  final String userId;
  final String userName;
  final String userEmail;
}

class _LocalCommissionAmounts {
  const _LocalCommissionAmounts({
    required this.totalAmount,
    required this.sellerCommissionAmount,
    required this.technicianCommissionAmount,
    required this.totalCommissionAmount,
  });

  final double totalAmount;
  final double sellerCommissionAmount;
  final double technicianCommissionAmount;
  final double totalCommissionAmount;
}

class _AdminUserSummaryAccumulator {
  _AdminUserSummaryAccumulator({
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  final String userId;
  final String userName;
  final String userEmail;
  int totalServices = 0;
  int installationCount = 0;
  int maintenanceCount = 0;
  double totalSold = 0;
  double totalPoints = 0;

  void add(ServiceOrderCommissionItem item) {
    totalServices += 1;
    if (item.serviceType.trim().toLowerCase() == 'instalacion') {
      installationCount += 1;
    }
    if (item.serviceType.trim().toLowerCase() == 'mantenimiento') {
      maintenanceCount += 1;
    }
    totalSold += item.totalAmount;
    totalPoints += item.totalCommissionAmount;
  }

  AdminServiceCommissionUserSummary build() {
    return AdminServiceCommissionUserSummary(
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      totalServices: totalServices,
      installationCount: installationCount,
      maintenanceCount: maintenanceCount,
      totalSold: totalSold,
      totalPoints: totalPoints,
    );
  }
}
