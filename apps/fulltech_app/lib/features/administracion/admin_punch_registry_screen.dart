import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../ponche/data/punch_repository.dart';
import '../ponche/models/attendance_models.dart';

enum _AdminRegistryMenuAction { filters, sync, panel }

enum _UserDetailDatePreset { hoy, manana, quincena, mes, personalizado }

class AdminPunchRegistryScreen extends ConsumerStatefulWidget {
  const AdminPunchRegistryScreen({super.key});

  @override
  ConsumerState<AdminPunchRegistryScreen> createState() =>
      _AdminPunchRegistryScreenState();
}

class _AdminPunchRegistryScreenState
    extends ConsumerState<AdminPunchRegistryScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showSummaryPanel = true;
  UserFacingError? _error;
  AttendanceSummaryModel? _summary;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
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
      final summary = await ref
          .read(punchRepositoryProvider)
          .fetchAttendanceSummary(
            from: DateTime(_from.year, _from.month, _from.day),
            to: DateTime(_to.year, _to.month, _to.day),
          );
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

  Future<void> _handleMenuAction(_AdminRegistryMenuAction action) async {
    switch (action) {
      case _AdminRegistryMenuAction.filters:
        await _pickDateRange();
        break;
      case _AdminRegistryMenuAction.sync:
        await _load();
        break;
      case _AdminRegistryMenuAction.panel:
        if (!mounted) return;
        setState(() => _showSummaryPanel = !_showSummaryPanel);
        break;
    }
  }

  List<AttendanceUserSummary> get _visibleUsers {
    final users = _summary?.users ?? const <AttendanceUserSummary>[];
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return users;

    return users
        .where((item) {
          return item.user.nombreCompleto.toLowerCase().contains(query) ||
              item.user.email.toLowerCase().contains(query) ||
              item.user.role.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openUserDetail(AttendanceUserSummary summary) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdminPunchUserDetailScreen(
          user: summary.user,
          initialFrom: _from,
          initialTo: _to,
        ),
      ),
    );
  }

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleUsers;
    final summary = _summary;

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
                            PopupMenuButton<_AdminRegistryMenuAction>(
                              tooltip: 'Opciones',
                              onSelected: _handleMenuAction,
                              itemBuilder: (context) => [
                                const PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.filters,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.tune_rounded,
                                    label: 'Filtro',
                                  ),
                                ),
                                const PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.sync,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.sync_rounded,
                                    label: 'Sincronizar',
                                  ),
                                ),
                                PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.panel,
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
                              icon: Icons.tune_rounded,
                              tooltip: 'Filtro',
                              onTap: _pickDateRange,
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
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                                'Ponches por usuario',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _AdminPunchInfoChip(
                                    icon: Icons.group_outlined,
                                    label: 'Usuarios',
                                    value: '${visible.length}',
                                  ),
                                  _AdminPunchInfoChip(
                                    icon: Icons.warning_amber_rounded,
                                    label: 'Incidentes',
                                    value: '${summary?.totals.tardyCount ?? 0}',
                                  ),
                                  _AdminPunchInfoChip(
                                    icon: Icons.timelapse_outlined,
                                    label: 'Horas',
                                    value: _formatMinutes(
                                      summary?.totals.workedMinutes ?? 0,
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
                            'No hay usuarios con ponches para mostrar en este período.',
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
                              final balance = item.aggregate.balanceMinutes;
                              final accentColor = balance >= 0
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFB91C1C);

                              return _AdminPunchUserCard(
                                summary: item,
                                accentColor: accentColor,
                                dateRangeLabel:
                                    '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                workedLabel: _formatMinutes(
                                  item.aggregate.workedMinutes,
                                ),
                                balanceLabel: _formatMinutes(balance),
                                incidentLabel:
                                    '${item.aggregate.incidentsCount} incidentes',
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

class _AdminPunchUserDetailScreen extends ConsumerStatefulWidget {
  const _AdminPunchUserDetailScreen({
    required this.user,
    required this.initialFrom,
    required this.initialTo,
  });

  final AttendanceUser user;
  final DateTime initialFrom;
  final DateTime initialTo;

  @override
  ConsumerState<_AdminPunchUserDetailScreen> createState() =>
      _AdminPunchUserDetailScreenState();
}

class _AdminPunchUserDetailScreenState
    extends ConsumerState<_AdminPunchUserDetailScreen> {
  static const double _desktopBreakpoint = 860;

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  UserFacingError? _error;
  AttendanceDetailModel? _detail;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  PunchType? _selectedType;
  _UserDetailDatePreset _preset = _UserDetailDatePreset.quincena;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
    _applyPreset(_UserDetailDatePreset.quincena, reload: false);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(_UserDetailDatePreset preset, {bool reload = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime from;
    DateTime to;

    switch (preset) {
      case _UserDetailDatePreset.hoy:
        from = today;
        to = today;
        break;
      case _UserDetailDatePreset.manana:
        from = today.add(const Duration(days: 1));
        to = today.add(const Duration(days: 1));
        break;
      case _UserDetailDatePreset.quincena:
        if (today.day <= 15) {
          from = DateTime(today.year, today.month, 1);
          to = DateTime(today.year, today.month, 15);
        } else {
          final lastDay = DateTime(today.year, today.month + 1, 0).day;
          from = DateTime(today.year, today.month, 16);
          to = DateTime(today.year, today.month, lastDay);
        }
        break;
      case _UserDetailDatePreset.mes:
        from = DateTime(today.year, today.month, 1);
        to = DateTime(today.year, today.month + 1, 0);
        break;
      case _UserDetailDatePreset.personalizado:
        // keep existing _from / _to
        setState(() => _preset = preset);
        return;
    }

    setState(() {
      _preset = preset;
      _from = from;
      _to = to;
    });

    if (reload) unawaited(_load());
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
      final detail = await ref
          .read(punchRepositoryProvider)
          .fetchAttendanceDetail(
            widget.user.id,
            from: DateTime(_from.year, _from.month, _from.day),
            to: DateTime(_to.year, _to.month, _to.day),
          );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _UserDetailDatePreset.personalizado;
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  String _dateOnlyText(DateTime value) =>
      DateFormat('dd/MM/yyyy', 'es_DO').format(value);

  String _dateTimeText(DateTime value) =>
      DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(value.toLocal());

  String _dateLabelFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today)
      return 'Hoy, ${DateFormat('d MMMM yyyy', 'es_DO').format(date)}';
    if (d == yesterday)
      return 'Ayer, ${DateFormat('d MMMM yyyy', 'es_DO').format(date)}';
    return DateFormat('EEEE, d MMMM yyyy', 'es_DO').format(date);
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remaining = absolute % 60;
    return '$sign${hours}h ${remaining.toString().padLeft(2, '0')}m';
  }

  List<PunchModel> get _visiblePunches {
    final detail = _detail;
    if (detail == null) return const <PunchModel>[];
    final query = _searchCtrl.text.trim().toLowerCase();
    final rows = [...detail.punches]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows
        .where((item) {
          if (_selectedType != null && item.type != _selectedType) return false;
          if (query.isEmpty) return true;
          return item.type.label.toLowerCase().contains(query) ||
              _dateTimeText(item.timestamp).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<_PunchDayGroup> get _visibleDayGroups {
    final buckets = <DateTime, List<PunchModel>>{};
    for (final punch in _visiblePunches) {
      final day = DateTime(
        punch.timestamp.year,
        punch.timestamp.month,
        punch.timestamp.day,
      );
      buckets.putIfAbsent(day, () => <PunchModel>[]).add(punch);
    }
    final groups =
        buckets.entries
            .map((entry) {
              final punches = [...entry.value]
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
              return _PunchDayGroup(date: entry.key, punches: punches);
            })
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) return _buildDesktopLayout();
    return _buildMobileLayout();
  }

  // ── DESKTOP ──────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleDayGroups;
    final detail = _detail;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            // ── Top bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.nombreCompleto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          widget.user.role.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CompactTopActionButton(
                    icon: Icons.sync_rounded,
                    tooltip: 'Sincronizar',
                    onTap: _load,
                  ),
                ],
              ),
            ),
            // ── Body: list + sidebar ─────────────────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: punches list
                  Expanded(
                    child: _error != null
                        ? ProfessionalRecoveryCard(
                            error: _error!,
                            autoRetryCountdown: null,
                            isRetrying: _loading,
                            onRetryNow: _load,
                          )
                        : detail == null && !_loading
                        ? const SizedBox.shrink()
                        : visible.isEmpty && !_loading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.punch_clock_outlined,
                                  size: 48,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Sin ponches para este filtro',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 4, 8, 32),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final group = visible[index];
                                return _AdminPunchDaySection(
                                  dateLabel: _dateLabelFor(group.date),
                                  punches: group.punches,
                                  dateTextBuilder: _dateTimeText,
                                );
                              },
                            ),
                          ),
                  ),
                  // Right: fixed sidebar
                  _UserDetailSidebar(
                    user: widget.user,
                    detail: detail,
                    from: _from,
                    to: _to,
                    preset: _preset,
                    selectedType: _selectedType,
                    totalGroups: visible.length,
                    onPresetChanged: _applyPreset,
                    onPickCustomRange: _pickCustomRange,
                    onTypeChanged: (type) =>
                        setState(() => _selectedType = type),
                    formatMinutes: _formatMinutes,
                    dateOnlyText: _dateOnlyText,
                    searchCtrl: _searchCtrl,
                    onSearch: () => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── MOBILE ───────────────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = _detail;
    final visible = _visibleDayGroups;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                  _CompactTopActionButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'Filtros',
                    onTap: _showMobileFiltersSheet,
                  ),
                  const SizedBox(width: 6),
                  _CompactTopActionButton(
                    icon: Icons.sync_rounded,
                    tooltip: 'Sincronizar',
                    onTap: _load,
                  ),
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
                  : detail == null
                  ? const SizedBox.shrink()
                  : visible.isEmpty
                  ? Center(
                      child: Text(
                        'No hay ponches para este filtro.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final group = visible[index];
                          return _AdminPunchDaySection(
                            dateLabel: _dateLabelFor(group.date),
                            punches: group.punches,
                            dateTextBuilder: _dateTimeText,
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

  Future<void> _showMobileFiltersSheet() async {
    DateTime tempFrom = _from;
    DateTime tempTo = _to;
    PunchType? tempType = _selectedType;
    _UserDetailDatePreset tempPreset = _preset;
    bool applied = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModal) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            void triggerPreset(_UserDetailDatePreset p) {
              DateTime from;
              DateTime to;
              switch (p) {
                case _UserDetailDatePreset.hoy:
                  from = today;
                  to = today;
                  break;
                case _UserDetailDatePreset.manana:
                  from = today.add(const Duration(days: 1));
                  to = today.add(const Duration(days: 1));
                  break;
                case _UserDetailDatePreset.quincena:
                  if (today.day <= 15) {
                    from = DateTime(today.year, today.month, 1);
                    to = DateTime(today.year, today.month, 15);
                  } else {
                    final last = DateTime(today.year, today.month + 1, 0).day;
                    from = DateTime(today.year, today.month, 16);
                    to = DateTime(today.year, today.month, last);
                  }
                  break;
                case _UserDetailDatePreset.mes:
                  from = DateTime(today.year, today.month, 1);
                  to = DateTime(today.year, today.month + 1, 0);
                  break;
                case _UserDetailDatePreset.personalizado:
                  from = tempFrom;
                  to = tempTo;
                  break;
              }
              setModal(() {
                tempPreset = p;
                tempFrom = from;
                tempTo = to;
              });
            }

            Future<void> pickRange() async {
              final picked = await showDateRangePicker(
                context: ctx,
                initialDateRange: DateTimeRange(start: tempFrom, end: tempTo),
                firstDate: DateTime.now().subtract(
                  const Duration(days: 365 * 3),
                ),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked == null) return;
              setModal(() {
                tempPreset = _UserDetailDatePreset.personalizado;
                tempFrom = DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                );
                tempTo = DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day,
                );
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtros',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Período',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _UserDetailDatePreset.values.map((p) {
                      return _DatePresetChip(
                        label: _presetLabel(p),
                        selected: tempPreset == p,
                        onTap: () => p == _UserDetailDatePreset.personalizado
                            ? pickRange()
                            : triggerPreset(p),
                      );
                    }).toList(),
                  ),
                  if (tempPreset == _UserDetailDatePreset.personalizado) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: pickRange,
                      icon: const Icon(Icons.date_range_rounded, size: 16),
                      label: Text(
                        '${DateFormat('dd/MM/yy').format(tempFrom)} - ${DateFormat('dd/MM/yy').format(tempTo)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        textStyle: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Tipo de ponche',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AdminTypeFilterChip(
                        label: 'Todos',
                        selected: tempType == null,
                        onTap: () => setModal(() => tempType = null),
                      ),
                      ...PunchType.values.map(
                        (type) => _AdminTypeFilterChip(
                          label: type.label,
                          selected: tempType == type,
                          onTap: () => setModal(() => tempType = type),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        applied = true;
                        Navigator.of(sheetCtx).pop();
                      },
                      child: const Text('Aplicar filtros'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (applied) {
      setState(() {
        _preset = tempPreset;
        _from = tempFrom;
        _to = tempTo;
        _selectedType = tempType;
      });
      await _load();
    }
  }
}

// ── Desktop sidebar ───────────────────────────────────────────────────────────

class _UserDetailSidebar extends StatelessWidget {
  const _UserDetailSidebar({
    required this.user,
    required this.detail,
    required this.from,
    required this.to,
    required this.preset,
    required this.selectedType,
    required this.totalGroups,
    required this.onPresetChanged,
    required this.onPickCustomRange,
    required this.onTypeChanged,
    required this.formatMinutes,
    required this.dateOnlyText,
    required this.searchCtrl,
    required this.onSearch,
  });

  final AttendanceUser user;
  final AttendanceDetailModel? detail;
  final DateTime from;
  final DateTime to;
  final _UserDetailDatePreset preset;
  final PunchType? selectedType;
  final int totalGroups;
  final void Function(_UserDetailDatePreset) onPresetChanged;
  final VoidCallback onPickCustomRange;
  final void Function(PunchType?) onTypeChanged;
  final String Function(int) formatMinutes;
  final String Function(DateTime) dateOnlyText;
  final TextEditingController searchCtrl;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── User info ──────────────────────────────────────────
            _SidebarSection(
              title: 'Empleado',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          _initials(user.nombreCompleto),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.nombreCompleto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              user.role.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 10),
                    _SidebarStatRow(
                      icon: Icons.punch_clock_outlined,
                      label: 'Total ponches',
                      value: '${detail!.punches.length}',
                    ),
                    const SizedBox(height: 5),
                    _SidebarStatRow(
                      icon: Icons.timelapse_outlined,
                      label: 'Horas trabajadas',
                      value: formatMinutes(detail!.totals.workedMinutes),
                    ),
                    const SizedBox(height: 5),
                    _SidebarStatRow(
                      icon: Icons.calendar_month_rounded,
                      label: 'Días con ponches',
                      value: '$totalGroups',
                    ),
                    if (detail!.totals.balanceMinutes != 0) ...[
                      const SizedBox(height: 5),
                      _SidebarStatRow(
                        icon: Icons.balance_rounded,
                        label: 'Balance',
                        value: formatMinutes(detail!.totals.balanceMinutes),
                        valueColor: detail!.totals.balanceMinutes >= 0
                            ? const Color(0xFF0F766E)
                            : const Color(0xFFDC2626),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Date presets ───────────────────────────────────────
            _SidebarSection(
              title: 'Período',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._UserDetailDatePreset.values.map((p) {
                    final isSelected = preset == p;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarPresetTile(
                        label: _presetLabel(p),
                        icon: _presetIcon(p),
                        selected: isSelected,
                        onTap: () => p == _UserDetailDatePreset.personalizado
                            ? onPickCustomRange()
                            : onPresetChanged(p),
                      ),
                    );
                  }),
                  if (preset == _UserDetailDatePreset.personalizado)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.date_range_rounded,
                              size: 13,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${DateFormat('dd/MM/yy').format(from)} → ${DateFormat('dd/MM/yy').format(to)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Type filter ────────────────────────────────────────
            _SidebarSection(
              title: 'Tipo de ponche',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarPresetTile(
                      label: 'Todos',
                      icon: Icons.all_inclusive_rounded,
                      selected: selectedType == null,
                      onTap: () => onTypeChanged(null),
                    ),
                  ),
                  ...PunchType.values.map(
                    (type) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarPresetTile(
                        label: type.label,
                        icon: _iconFor(type),
                        selected: selectedType == type,
                        onTap: () => onTypeChanged(type),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Search ─────────────────────────────────────────────
            _SidebarSection(
              title: 'Buscar',
              child: TextField(
                controller: searchCtrl,
                onChanged: (_) => onSearch(),
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Tipo o fecha...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: scheme.surfaceContainerLowest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
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

// ── Sidebar helpers ───────────────────────────────────────────────────────────

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SidebarPresetTile extends StatelessWidget {
  const _SidebarPresetTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 14, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarStatRow extends StatelessWidget {
  const _SidebarStatRow({
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ── Helper chips / labels ─────────────────────────────────────────────────────

class _DatePresetChip extends StatelessWidget {
  const _DatePresetChip({
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
      color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

String _presetLabel(_UserDetailDatePreset p) {
  switch (p) {
    case _UserDetailDatePreset.hoy:
      return 'Hoy';
    case _UserDetailDatePreset.manana:
      return 'Mañana';
    case _UserDetailDatePreset.quincena:
      return 'Esta quincena';
    case _UserDetailDatePreset.mes:
      return 'Este mes';
    case _UserDetailDatePreset.personalizado:
      return 'Personalizado';
  }
}

IconData _presetIcon(_UserDetailDatePreset p) {
  switch (p) {
    case _UserDetailDatePreset.hoy:
      return Icons.today_rounded;
    case _UserDetailDatePreset.manana:
      return Icons.event_rounded;
    case _UserDetailDatePreset.quincena:
      return Icons.date_range_rounded;
    case _UserDetailDatePreset.mes:
      return Icons.calendar_month_rounded;
    case _UserDetailDatePreset.personalizado:
      return Icons.tune_rounded;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

IconData _iconFor(PunchType type) {
  return switch (type) {
    PunchType.entradaLabor => Icons.login,
    PunchType.salidaLabor => Icons.exit_to_app,
    PunchType.salidaPermiso => Icons.meeting_room_outlined,
    PunchType.entradaPermiso => Icons.door_back_door,
    PunchType.salidaAlmuerzo => Icons.fastfood,
    PunchType.entradaAlmuerzo => Icons.restaurant,
  };
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

class _AdminPunchUserCard extends StatelessWidget {
  const _AdminPunchUserCard({
    required this.summary,
    required this.accentColor,
    required this.dateRangeLabel,
    required this.workedLabel,
    required this.balanceLabel,
    required this.incidentLabel,
    required this.onTap,
  });

  final AttendanceUserSummary summary;
  final Color accentColor;
  final String dateRangeLabel;
  final String workedLabel;
  final String balanceLabel;
  final String incidentLabel;
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
                height: 46,
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
                      summary.user.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _AdminMiniLabel(text: summary.user.role.toUpperCase()),
                        _AdminMiniLabel(text: workedLabel),
                        _AdminMiniLabel(text: balanceLabel, color: accentColor),
                        _AdminMiniLabel(text: incidentLabel),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateRangeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
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

class _AdminPunchDaySection extends StatelessWidget {
  const _AdminPunchDaySection({
    required this.dateLabel,
    required this.punches,
    required this.dateTextBuilder,
  });

  final String dateLabel;
  final List<PunchModel> punches;
  final String Function(DateTime value) dateTextBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Day header ─────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: Text(
                _capitalize(dateLabel),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${punches.length} ponche${punches.length != 1 ? 's' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── Punch cards ────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: List.generate(punches.length, (index) {
              final punch = punches[index];
              final isLast = index == punches.length - 1;
              return Column(
                children: [
                  _AdminPunchLineItem(
                    punch: punch,
                    dateText: dateTextBuilder(punch.timestamp),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 44,
                      color: scheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _AdminPunchLineItem extends StatelessWidget {
  const _AdminPunchLineItem({required this.punch, required this.dateText});

  final PunchModel punch;
  final String dateText;

  static Color _colorFor(PunchType type) {
    return switch (type) {
      PunchType.entradaLabor => const Color(0xFF2563EB),
      PunchType.entradaPermiso => const Color(0xFF0891B2),
      PunchType.entradaAlmuerzo => const Color(0xFF059669),
      PunchType.salidaLabor => const Color(0xFF7C3AED),
      PunchType.salidaPermiso => const Color(0xFFD97706),
      PunchType.salidaAlmuerzo => const Color(0xFFEA580C),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _colorFor(punch.type);
    final timeStr = DateFormat(
      'h:mm a',
      'es_DO',
    ).format(punch.timestamp.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Colored type indicator
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(_iconFor(punch.type), size: 16, color: color),
          ),
          const SizedBox(width: 10),
          // Type + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  punch.type.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  DateFormat(
                    'dd/MM/yyyy',
                    'es_DO',
                  ).format(punch.timestamp.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Time badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timeStr,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminPunchInfoChip extends StatelessWidget {
  const _AdminPunchInfoChip({
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.24),
        ),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
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

class _AdminMiniLabel extends StatelessWidget {
  const _AdminMiniLabel({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: effectiveColor,
      ),
    );
  }
}

class _AdminTypeFilterChip extends StatelessWidget {
  const _AdminTypeFilterChip({
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
      color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PunchDayGroup {
  const _PunchDayGroup({required this.date, required this.punches});

  final DateTime date;
  final List<PunchModel> punches;
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
