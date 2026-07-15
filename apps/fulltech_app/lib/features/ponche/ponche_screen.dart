import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/punch_model.dart';
import './application/punch_controller.dart';
import './data/punch_repository.dart';
import './models/attendance_models.dart';

enum _DesktopPunchDatePreset { hoy, semana, quincena, fecha, rango }

class PoncheScreen extends ConsumerStatefulWidget {
  const PoncheScreen({super.key});

  @override
  ConsumerState<PoncheScreen> createState() => _PoncheScreenState();
}

class _PoncheScreenState extends ConsumerState<PoncheScreen> {
  static const double _desktopBreakpoint = 1000;

  Future<AttendanceDetailModel>? _attendanceFuture;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  _DesktopPunchDatePreset _datePreset = _DesktopPunchDatePreset.hoy;
  DateTime? _specificDate;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _attendanceFuture = _loadAttendanceDetail();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<AttendanceDetailModel> _loadAttendanceDetail() {
    return ref.read(punchRepositoryProvider).fetchMyAttendanceDetail();
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  Future<void> _refreshAttendance() async {
    await ref.read(punchControllerProvider.notifier).load();
    setState(() {
      _attendanceFuture = _loadAttendanceDetail();
    });
    await _attendanceFuture;
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  void _showPunchOptions(PunchState state) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '¿Qué deseas registrar?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...PunchType.values.map(
                (type) => ListTile(
                  leading: Icon(_iconFor(type), color: AppTheme.primaryColor),
                  title: Text(type.label),
                  onTap: state.creating
                      ? null
                      : () {
                          Navigator.pop(context);
                          _handlePunch(type);
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _openHistoryScreen() {
    context.push(Routes.poncheHistorial);
  }

  Future<void> _handlePunch(PunchType type) async {
    try {
      final punch = await ref
          .read(punchControllerProvider.notifier)
          .register(type);
      setState(() {
        _attendanceFuture = _loadAttendanceDetail();
      });
      if (!mounted) return;
      final time = DateFormat(
        'h:mm a',
        'es_DO',
      ).format(punch.timestamp.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ponche "${type.label}" registrado a las $time'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudo registrar el ponche';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final punchState = ref.watch(punchControllerProvider);
    final isDesktop = _isDesktop(context);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: const CustomAppBar(
        title: 'Ponche',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: isDesktop
          ? _buildDesktopTab(punchState)
          : _buildUserTab(punchState),
    );
  }

  Widget _buildDesktopTab(PunchState state) {
    final lastPunch = state.items.isNotEmpty ? state.items.first : null;

    return FutureBuilder<AttendanceDetailModel>(
      future: _attendanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          final message = snapshot.hasError
              ? 'No se pudo cargar el detalle de asistencia.'
              : 'No hay información de asistencia disponible.';
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _DesktopPunchEmptyState(
                  icon: Icons.timer_off_outlined,
                  title: 'Asistencia no disponible',
                  message: message,
                  actionLabel: 'Reintentar',
                  onAction: _refreshAttendance,
                ),
              ),
            ),
          );
        }

        final detail = snapshot.data!;
        final filterRange = _selectedDesktopRange();
        final filteredDays = detail.days
            .where((day) {
              final date = DateTime.tryParse('${day.date}T00:00:00');
              if (date == null) return false;
              return !date.isBefore(filterRange.start) &&
                  !date.isAfter(filterRange.end);
            })
            .toList(growable: false);
        final filteredPunches =
            detail.punches
                .where((punch) {
                  final local = punch.timestamp.toLocal();
                  final day = DateTime(local.year, local.month, local.day);
                  return !day.isBefore(filterRange.start) &&
                      !day.isAfter(filterRange.end);
                })
                .toList(growable: false)
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final totals = _aggregateAttendanceDays(filteredDays);
        final todayDay = _findAttendanceDay(detail.days, _now);
        final status = _resolveDesktopStatus(todayDay, lastPunch);
        final workedToday = _workedMinutesForToday(todayDay);
        final expectedToday = (todayDay?.expectedWorkMinutes ?? (8 * 60)).clamp(
          0,
          1 << 30,
        );
        final remainingToday = expectedToday > workedToday
            ? expectedToday - workedToday
            : 0;
        final progress = expectedToday <= 0
            ? 0.0
            : (workedToday / expectedToday).clamp(0.0, 1.0);
        final entryText = todayDay?.entry == null
            ? 'Pendiente'
            : DateFormat('h:mm a', 'es_DO').format(todayDay!.entry!.toLocal());
        final exitText = todayDay?.exit == null
            ? 'Pendiente'
            : DateFormat('h:mm a', 'es_DO').format(todayDay!.exit!.toLocal());
        final compliance = (filteredDays.isEmpty || totals.workedMinutes <= 0)
            ? 0.0
            : (totals.workedMinutes /
                      filteredDays.fold<int>(
                        0,
                        (sum, day) => sum + day.expectedWorkMinutes,
                      ))
                  .clamp(0.0, 1.0);
        final completedDays = filteredDays
            .where((day) => !day.incomplete && day.balanceMinutes >= 0)
            .length;
        final delayedDays = filteredDays
            .where((day) => day.tardinessMinutes > 0)
            .length;
        final incompleteDays = filteredDays
            .where((day) => day.incomplete)
            .length;

        return Container(
          color: const Color(0xFFF4F7FB),
          child: RefreshIndicator(
            onRefresh: _refreshAttendance,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              children: [
                _PunchHeaderSection(
                  now: _now,
                  status: status,
                  lastPunch: lastPunch,
                  creating: state.creating,
                  onPunch: state.creating
                      ? null
                      : () => _showPunchOptions(state),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  _DesktopPunchErrorBanner(message: state.error!),
                ],
                const SizedBox(height: 18),
                _PunchSummaryCards(
                  cards: [
                    _PunchSummaryCardData(
                      label: 'Entrada',
                      value: entryText,
                      helper: 'Registro de hoy',
                      icon: Icons.login,
                      accent: const Color(0xFF1D4ED8),
                    ),
                    _PunchSummaryCardData(
                      label: 'Salida',
                      value: exitText,
                      helper: 'Cierre de jornada',
                      icon: Icons.logout,
                      accent: const Color(0xFF9333EA),
                    ),
                    _PunchSummaryCardData(
                      label: 'Trabajado hoy',
                      value: _formatMinutes(workedToday),
                      helper: 'Tiempo acumulado',
                      icon: Icons.timelapse_outlined,
                      accent: const Color(0xFF0F766E),
                    ),
                    _PunchSummaryCardData(
                      label: 'Tiempo faltante',
                      value: _formatMinutes(remainingToday),
                      helper: remainingToday > 0
                          ? 'Para completar la jornada'
                          : 'Objetivo cumplido',
                      icon: Icons.hourglass_bottom_outlined,
                      accent: remainingToday > 0
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF15803D),
                    ),
                    _PunchSummaryCardData(
                      label: 'Estado del horario',
                      value: status.label,
                      helper: status.description,
                      icon: status.icon,
                      accent: status.color,
                    ),
                    _PunchSummaryCardData(
                      label: 'Horas del período',
                      value: _formatMinutes(totals.workedMinutes),
                      helper: _desktopRangeLabel(filterRange),
                      icon: Icons.calendar_view_week_outlined,
                      accent: const Color(0xFF334155),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 1360;
                    final left = _PunchActionPanel(
                      status: status,
                      workedToday: workedToday,
                      expectedToday: expectedToday,
                      remainingToday: remainingToday,
                      progress: progress,
                      today: todayDay,
                      lastPunch: lastPunch,
                      creating: state.creating,
                      onPunch: state.creating
                          ? null
                          : () => _showPunchOptions(state),
                    );
                    final right = Column(
                      children: [
                        _PunchCompliancePanel(
                          compliance: compliance,
                          totals: totals,
                          completedDays: completedDays,
                          delayedDays: delayedDays,
                          incompleteDays: incompleteDays,
                        ),
                        const SizedBox(height: 16),
                        _PunchRecentActivityPanel(
                          punches: filteredPunches.take(6).toList(),
                        ),
                      ],
                    );

                    if (!twoColumns) {
                      return Column(
                        children: [left, const SizedBox(height: 16), right],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: left),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: right),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _PunchHistorySection(
                  preset: _datePreset,
                  rangeLabel: _desktopRangeLabel(filterRange),
                  customRange: _customRange,
                  specificDate: _specificDate,
                  days: filteredDays,
                  onPresetChanged: (preset) async {
                    if (preset == _DesktopPunchDatePreset.fecha) {
                      await _pickSpecificDate();
                      return;
                    }
                    if (preset == _DesktopPunchDatePreset.rango) {
                      await _pickCustomRange();
                      return;
                    }
                    setState(() => _datePreset = preset);
                  },
                  onPickSpecificDate: _pickSpecificDate,
                  onPickRange: _pickCustomRange,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserTab(PunchState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastPunch = state.items.isNotEmpty ? state.items.first : null;
    final statusLabel = _statusLabelFrom(lastPunch);
    final statusColor = _statusColorFrom(lastPunch);
    final statusIcon = _statusIconFrom(lastPunch);
    final chipForeground = statusColor.computeLuminance() > 0.70
        ? Colors.black87
        : statusColor;

    final timeString = DateFormat('h:mm a', 'es_DO').format(_now);
    final dateString = DateFormat("EEEE, d 'de' MMMM", 'es_DO').format(_now);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.surface, scheme.surfaceContainerLowest],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Error banner ──────────────────────────────
                  if (state.error != null) ...[
                    Card(
                      color: scheme.errorContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: scheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Live clock ────────────────────────────────
                  Text(
                    timeString,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateString,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Status card ───────────────────────────────
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(statusIcon, color: chipForeground, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                statusLabel,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lastPunch != null
                                ? 'Último: ${lastPunch.type.label} · ${DateFormat('h:mm a', 'es_DO').format(lastPunch.timestamp.toLocal())}'
                                : 'Sin registros hoy',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── PONCHAR button ────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 66,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(33),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      onPressed: state.creating
                          ? null
                          : () => _showPunchOptions(state),
                      child: state.creating
                          ? SizedBox(
                              height: 26,
                              width: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Text('PONCHAR'),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── History link ──────────────────────────────
                  TextButton.icon(
                    onPressed: _openHistoryScreen,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                    ),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Ver historial completo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTimeRange _selectedDesktopRange() {
    final now = DateTime(_now.year, _now.month, _now.day);
    switch (_datePreset) {
      case _DesktopPunchDatePreset.hoy:
        return DateTimeRange(start: now, end: now);
      case _DesktopPunchDatePreset.semana:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 6)),
        );
      case _DesktopPunchDatePreset.quincena:
        if (now.day <= 15) {
          return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, 15),
          );
        }
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        return DateTimeRange(
          start: DateTime(now.year, now.month, 16),
          end: DateTime(now.year, now.month, lastDay),
        );
      case _DesktopPunchDatePreset.fecha:
        final specific = _specificDate ?? now;
        final normalized = DateTime(
          specific.year,
          specific.month,
          specific.day,
        );
        return DateTimeRange(start: normalized, end: normalized);
      case _DesktopPunchDatePreset.rango:
        if (_customRange != null) {
          return DateTimeRange(
            start: DateTime(
              _customRange!.start.year,
              _customRange!.start.month,
              _customRange!.start.day,
            ),
            end: DateTime(
              _customRange!.end.year,
              _customRange!.end.month,
              _customRange!.end.day,
            ),
          );
        }
        return DateTimeRange(start: now, end: now);
    }
  }

  Future<void> _pickSpecificDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? _now,
      firstDate: DateTime(_now.year - 1),
      lastDate: DateTime(_now.year + 1),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _specificDate = picked;
      _datePreset = _DesktopPunchDatePreset.fecha;
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange,
      firstDate: DateTime(_now.year - 1),
      lastDate: DateTime(_now.year + 1),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _datePreset = _DesktopPunchDatePreset.rango;
    });
  }

  AttendanceAggregateMetrics _aggregateAttendanceDays(
    List<AttendanceDayMetrics> days,
  ) {
    var tardinessMinutes = 0;
    var earlyLeaveMinutes = 0;
    var notWorkedMinutes = 0;
    var workedMinutes = 0;
    var favorableMinutes = 0;
    var unfavorableMinutes = 0;
    var balanceMinutes = 0;
    var incompleteDays = 0;
    var incidentsCount = 0;

    for (final day in days) {
      tardinessMinutes += day.tardinessMinutes;
      earlyLeaveMinutes += day.earlyLeaveMinutes;
      notWorkedMinutes += day.notWorkedMinutes;
      workedMinutes += day.workedMinutesNet ?? 0;
      favorableMinutes += day.favorableMinutes;
      unfavorableMinutes += day.unfavorableMinutes;
      balanceMinutes += day.balanceMinutes;
      if (day.incomplete) incompleteDays += 1;
      incidentsCount += day.incidents.length;
    }

    return AttendanceAggregateMetrics(
      tardinessMinutes: tardinessMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
      notWorkedMinutes: notWorkedMinutes,
      workedMinutes: workedMinutes,
      favorableMinutes: favorableMinutes,
      unfavorableMinutes: unfavorableMinutes,
      balanceMinutes: balanceMinutes,
      incompleteDays: incompleteDays,
      incidentsCount: incidentsCount,
    );
  }

  AttendanceDayMetrics? _findAttendanceDay(
    List<AttendanceDayMetrics> days,
    DateTime date,
  ) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    for (final day in days) {
      if (day.date == key) return day;
    }
    return null;
  }

  int _workedMinutesForToday(AttendanceDayMetrics? today) {
    if (today == null) return 0;
    if (today.workedMinutesNet != null) return today.workedMinutesNet!;
    if (today.entry == null) return 0;
    final nowLocal = _now.toLocal();
    final diff = nowLocal.difference(today.entry!.toLocal()).inMinutes;
    return diff.clamp(0, 1 << 30);
  }

  _PunchStatusVisual _resolveDesktopStatus(
    AttendanceDayMetrics? today,
    PunchModel? lastPunch,
  ) {
    if (today == null && lastPunch == null) {
      return const _PunchStatusVisual(
        label: 'Entrada pendiente',
        description: 'Aún no has iniciado tu jornada de hoy.',
        color: Color(0xFF64748B),
        icon: Icons.schedule_outlined,
      );
    }

    if (today != null) {
      if (today.incomplete && today.entry != null && today.exit == null) {
        if (today.tardinessMinutes > 0) {
          return const _PunchStatusVisual(
            label: 'Retraso',
            description: 'Entraste tarde, pero tu jornada sigue activa.',
            color: Color(0xFFEA580C),
            icon: Icons.warning_amber_rounded,
          );
        }
        return const _PunchStatusVisual(
          label: 'En jornada',
          description: 'Tu jornada está activa y aún no ha sido cerrada.',
          color: Color(0xFF16A34A),
          icon: Icons.play_circle_outline,
        );
      }
      if (today.entry == null) {
        return const _PunchStatusVisual(
          label: 'Entrada pendiente',
          description: 'No se ha registrado una entrada laboral para hoy.',
          color: Color(0xFF64748B),
          icon: Icons.assignment_late_outlined,
        );
      }
      if (today.exit != null &&
          !today.incomplete &&
          today.balanceMinutes >= 0) {
        return const _PunchStatusVisual(
          label: 'Jornada completada',
          description: 'Ya cumpliste tu jornada esperada para hoy.',
          color: Color(0xFF15803D),
          icon: Icons.verified_outlined,
        );
      }
      if (today.exit != null && today.balanceMinutes < 0) {
        return const _PunchStatusVisual(
          label: 'Pendiente',
          description: 'Tienes horas pendientes por compensar hoy.',
          color: Color(0xFFDC2626),
          icon: Icons.pending_actions_outlined,
        );
      }
    }

    switch (lastPunch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return const _PunchStatusVisual(
          label: 'En jornada',
          description:
              'Tu último movimiento indica que estás dentro de jornada.',
          color: Color(0xFF16A34A),
          icon: Icons.login,
        );
      case PunchType.salidaLabor:
        return const _PunchStatusVisual(
          label: 'Fuera de jornada',
          description: 'Tu jornada fue cerrada con una salida laboral.',
          color: Color(0xFF334155),
          icon: Icons.logout,
        );
      case PunchType.salidaAlmuerzo:
        return const _PunchStatusVisual(
          label: 'En almuerzo',
          description: 'Actualmente tienes una salida de almuerzo abierta.',
          color: Color(0xFFF59E0B),
          icon: Icons.fastfood_outlined,
        );
      case PunchType.salidaPermiso:
        return const _PunchStatusVisual(
          label: 'En permiso',
          description: 'Existe una salida por permiso pendiente de retorno.',
          color: Color(0xFF7C3AED),
          icon: Icons.meeting_room_outlined,
        );
      case null:
        return const _PunchStatusVisual(
          label: 'Fuera de jornada',
          description: 'Sin registros recientes en el historial.',
          color: Color(0xFF64748B),
          icon: Icons.circle_outlined,
        );
    }
  }

  String _desktopRangeLabel(DateTimeRange range) {
    final sameDay =
        range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day;
    if (sameDay) {
      return DateFormat('dd/MM/yyyy').format(range.start);
    }
    return '${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}';
  }

  IconData _statusIconFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Icons.login;
      case PunchType.salidaLabor:
        return Icons.exit_to_app;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Icons.pause_circle_filled;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _statusColorFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Colors.green;
      case PunchType.salidaLabor:
        return Colors.red;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Colors.orange;
      default:
        return Colors.white;
    }
  }

  String _statusLabelFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return 'En jornada';
      case PunchType.salidaLabor:
        return 'Fuera';
      case PunchType.salidaAlmuerzo:
        return 'En almuerzo';
      case PunchType.salidaPermiso:
        return 'En permiso';
      default:
        return 'Fuera';
    }
  }
}

class PunchHistoryScreen extends ConsumerStatefulWidget {
  const PunchHistoryScreen({super.key});

  @override
  ConsumerState<PunchHistoryScreen> createState() => _PunchHistoryScreenState();
}

class _PunchHistoryScreenState extends ConsumerState<PunchHistoryScreen> {
  Future<AttendanceDetailModel>? _attendanceFuture;

  @override
  void initState() {
    super.initState();
    _attendanceFuture = _loadAttendanceDetail();
  }

  Future<AttendanceDetailModel> _loadAttendanceDetail() {
    return ref.read(punchRepositoryProvider).fetchMyAttendanceDetail();
  }

  Future<void> _refreshAttendance() async {
    setState(() {
      _attendanceFuture = _loadAttendanceDetail();
    });
    await _attendanceFuture;
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  Color _balanceColor(int minutes) {
    if (minutes > 0) return Colors.green.shade700;
    if (minutes < 0) return Colors.red.shade700;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: CustomAppBar(
        title: 'Historial de ponches',
        fallbackRoute: Routes.ponche,
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refreshAttendance,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAttendance,
        child: FutureBuilder<AttendanceDetailModel>(
          future: _attendanceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  _DesktopPunchEmptyState(
                    icon: Icons.history_toggle_off_outlined,
                    title: 'Historial no disponible',
                    message: 'No se pudo cargar el balance de horas.',
                    actionLabel: 'Reintentar',
                    onAction: _refreshAttendance,
                  ),
                ],
              );
            }

            final detail = snapshot.data!;
            final totals = detail.totals;
            final balanceColor = _balanceColor(totals.balanceMinutes);
            final recentPunches = detail.punches
                .take(20)
                .toList(growable: false);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen del historial',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Consulta todos tus balances, jornadas y registros recientes en una vista completa.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _AttendanceSummaryTile(
                                label: 'Horas a favor',
                                value: _formatMinutes(totals.favorableMinutes),
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _AttendanceSummaryTile(
                                label: 'Horas en contra',
                                value: _formatMinutes(
                                  totals.unfavorableMinutes,
                                ),
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _AttendanceSummaryTile(
                                label: 'Balance neto',
                                value: _formatMinutes(totals.balanceMinutes),
                                color: balanceColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _AttendanceSummaryTile(
                                label: 'Horas laboradas',
                                value: _formatMinutes(totals.workedMinutes),
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Balance por día',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        if (detail.days.isEmpty && recentPunches.isEmpty)
                          const _DesktopPunchEmptyState(
                            icon: Icons.history_toggle_off_outlined,
                            title: 'Aún no hay ponches registrados',
                            message:
                                'Cuando existan registros de jornada aparecerán aquí en pantalla completa.',
                          )
                        else ...[
                          ...detail.days.map(
                            (day) => _AttendanceDayCard(
                              day: day,
                              formatMinutes: _formatMinutes,
                              balanceColor: _balanceColor(day.balanceMinutes),
                            ),
                          ),
                          if (recentPunches.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Últimos registros',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            ...recentPunches.map(
                              (punch) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _iconFor(punch.type),
                                  color: AppTheme.primaryColor,
                                ),
                                title: Text(punch.type.label),
                                subtitle: Text(
                                  DateFormat(
                                    'dd/MM/yyyy · h:mm a',
                                    'es_DO',
                                  ).format(punch.timestamp.toLocal()),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
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

class _AttendanceSummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AttendanceSummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _AttendanceDayCard extends StatelessWidget {
  final AttendanceDayMetrics day;
  final String Function(int minutes) formatMinutes;
  final Color balanceColor;

  const _AttendanceDayCard({
    required this.day,
    required this.formatMinutes,
    required this.balanceColor,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = day.date.isEmpty
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(DateTime.parse(day.date));
    final entryText = day.entry == null
        ? '---'
        : DateFormat('h:mm a', 'es_DO').format(day.entry!.toLocal());
    final exitText = day.exit == null
        ? '---'
        : DateFormat('h:mm a', 'es_DO').format(day.exit!.toLocal());
    final label = day.balanceMinutes > 0
        ? 'A favor'
        : day.balanceMinutes < 0
        ? 'En contra'
        : 'Al día';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dateText,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: balanceColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$label: ${formatMinutes(day.balanceMinutes)}',
                    style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Entrada: $entryText · Salida: $exitText'),
            const SizedBox(height: 4),
            Text(
              'Laborado: ${formatMinutes(day.workedMinutesNet ?? 0)} · A favor: ${formatMinutes(day.favorableMinutes)} · En contra: ${formatMinutes(day.unfavorableMinutes)}',
            ),
            if (day.tardinessMinutes > 0 || day.earlyLeaveMinutes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tardanza: ${formatMinutes(day.tardinessMinutes)} · Salida temprana: ${formatMinutes(day.earlyLeaveMinutes)}',
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
            if (day.incomplete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Jornada incompleta',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PunchStatusVisual {
  const _PunchStatusVisual({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
  });

  final String label;
  final String description;
  final Color color;
  final IconData icon;
}

class _DesktopPunchErrorBanner extends StatelessWidget {
  const _DesktopPunchErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchHeaderSection extends StatelessWidget {
  const _PunchHeaderSection({
    required this.now,
    required this.status,
    required this.lastPunch,
    required this.creating,
    required this.onPunch,
  });

  final DateTime now;
  final _PunchStatusVisual status;
  final PunchModel? lastPunch;
  final bool creating;
  final VoidCallback? onPunch;

  @override
  Widget build(BuildContext context) {
    final rawDateText = DateFormat('dd MMM yyyy', 'es').format(now);
    final dateParts = rawDateText.split(' ');
    final dateText = dateParts.length >= 3
        ? '${dateParts[0]} ${dateParts[1][0].toUpperCase()}${dateParts[1].substring(1)} ${dateParts[2]}'
        : rawDateText;
    final timeText = DateFormat('h:mm a', 'es_DO').format(now);
    final recentPunch = lastPunch;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showPill = constraints.maxWidth >= 1240;
          final showLastPunch = constraints.maxWidth >= 1180;
          final showDescription = constraints.maxWidth >= 1440;
          final compactCta = constraints.maxWidth < 1120;

          final metaText = '$dateText · $timeText';

          final pill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Control de asistencia y jornada',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          final title = Text(
            'Ponche',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          );

          final meta = Flexible(
            child: Text(
              metaText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
              ),
            ),
          );

          final left = Row(
            children: [
              if (showPill) ...[pill, const SizedBox(width: 12)],
              title,
              const SizedBox(width: 12),
              meta,
            ],
          );

          final lastPunchText = recentPunch == null
              ? 'Sin registro reciente'
              : 'Último: ${recentPunch.type.label} · ${DateFormat('dd/MM · h:mm a', 'es_DO').format(recentPunch.timestamp.toLocal())}';

          final right = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PunchStatusBadge(status: status),
                if (showDescription) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      status.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (showLastPunch) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      lastPunchText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onPunch,
                  icon: creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.touch_app_outlined, size: 18),
                  label: Text(
                    creating
                        ? 'Registrando...'
                        : compactCta
                        ? 'Ponchar'
                        : 'Ponchar ahora',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );

          return Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              right,
            ],
          );
        },
      ),
    );
  }
}

class _PunchStatusBadge extends StatelessWidget {
  const _PunchStatusBadge({required this.status});

  final _PunchStatusVisual status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchSummaryCardData {
  const _PunchSummaryCardData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color accent;
}

class _PunchSummaryCards extends StatelessWidget {
  const _PunchSummaryCards({required this.cards});

  final List<_PunchSummaryCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1600
            ? 6
            : constraints.maxWidth >= 1200
            ? 3
            : 2;
        final spacing = 14.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width.clamp(220.0, 360.0),
                  child: _PunchSummaryCard(card: card),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _PunchSummaryCard extends StatelessWidget {
  const _PunchSummaryCard({required this.card});

  final _PunchSummaryCardData card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: card.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(card.icon, color: card.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(
                  card.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
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

class _PunchActionPanel extends StatelessWidget {
  const _PunchActionPanel({
    required this.status,
    required this.workedToday,
    required this.expectedToday,
    required this.remainingToday,
    required this.progress,
    required this.today,
    required this.lastPunch,
    required this.creating,
    required this.onPunch,
  });

  final _PunchStatusVisual status;
  final int workedToday;
  final int expectedToday;
  final int remainingToday;
  final double progress;
  final AttendanceDayMetrics? today;
  final PunchModel? lastPunch;
  final bool creating;
  final VoidCallback? onPunch;

  @override
  Widget build(BuildContext context) {
    final progressLabel =
        'Has completado ${_formatMinutesInline(workedToday)} de ${_formatMinutesInline(expectedToday)}';
    final message = remainingToday <= 0
        ? 'Jornada del día completada. Buen trabajo.'
        : 'Te faltan ${_formatMinutesInline(remainingToday)} para alcanzar la jornada esperada.';
    final recentPunch = lastPunch;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel central de jornada',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              _PunchStatusBadgeOnLight(status: status),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0F2FE), Color(0xFFF8FAFC)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progressLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 14,
                    backgroundColor: const Color(0xFFDBEAFE),
                    color: status.color,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: remainingToday <= 0
                        ? const Color(0xFF166534)
                        : const Color(0xFF9A3412),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PunchMiniMetric(
                label: 'Último registro',
                value: recentPunch == null
                    ? 'Sin datos'
                    : '${recentPunch.type.label} · ${DateFormat('h:mm a', 'es_DO').format(recentPunch.timestamp.toLocal())}',
              ),
              _PunchMiniMetric(
                label: 'Entrada de hoy',
                value: today?.entry == null
                    ? 'Pendiente'
                    : DateFormat(
                        'h:mm a',
                        'es_DO',
                      ).format(today!.entry!.toLocal()),
              ),
              _PunchMiniMetric(
                label: 'Salida de hoy',
                value: today?.exit == null
                    ? 'Pendiente'
                    : DateFormat(
                        'h:mm a',
                        'es_DO',
                      ).format(today!.exit!.toLocal()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPunch,
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fingerprint),
              label: Text(creating ? 'Procesando...' : 'Registrar ponche'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchCompliancePanel extends StatelessWidget {
  const _PunchCompliancePanel({
    required this.compliance,
    required this.totals,
    required this.completedDays,
    required this.delayedDays,
    required this.incompleteDays,
  });

  final double compliance;
  final AttendanceAggregateMetrics totals;
  final int completedDays;
  final int delayedDays;
  final int incompleteDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cumplimiento horario',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Entiende rápido cómo va tu balance de horario, retrasos y días cumplidos.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          _PunchCircularCompliance(value: compliance),
          const SizedBox(height: 16),
          _PunchMetricBar(
            label: 'Horas trabajadas',
            value: _formatMinutesInline(totals.workedMinutes),
            progress: compliance,
            color: const Color(0xFF1D4ED8),
          ),
          const SizedBox(height: 12),
          _PunchMetricBar(
            label: 'Balance neto',
            value: _formatMinutesInline(totals.balanceMinutes),
            progress: totals.balanceMinutes >= 0 ? 1 : 0.45,
            color: totals.balanceMinutes >= 0
                ? const Color(0xFF15803D)
                : const Color(0xFFDC2626),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PunchInfoTile(label: 'Días cumplidos', value: '$completedDays'),
              _PunchInfoTile(label: 'Días con retraso', value: '$delayedDays'),
              _PunchInfoTile(label: 'Incompletos', value: '$incompleteDays'),
              _PunchInfoTile(
                label: 'Incidencias',
                value: '${totals.incidentsCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PunchRecentActivityPanel extends StatelessWidget {
  const _PunchRecentActivityPanel({required this.punches});

  final List<PunchModel> punches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actividad reciente',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (punches.isEmpty)
            Text(
              'No hay movimientos recientes en el rango filtrado.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            )
          else
            ...punches.map(
              (punch) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFDBEAFE),
                  child: Icon(
                    _iconFor(punch.type),
                    color: const Color(0xFF1D4ED8),
                  ),
                ),
                title: Text(punch.type.label),
                subtitle: Text(
                  DateFormat(
                    'dd/MM/yyyy · h:mm a',
                    'es_DO',
                  ).format(punch.timestamp.toLocal()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PunchHistorySection extends StatelessWidget {
  const _PunchHistorySection({
    required this.preset,
    required this.rangeLabel,
    required this.customRange,
    required this.specificDate,
    required this.days,
    required this.onPresetChanged,
    required this.onPickSpecificDate,
    required this.onPickRange,
  });

  final _DesktopPunchDatePreset preset;
  final String rangeLabel;
  final DateTimeRange? customRange;
  final DateTime? specificDate;
  final List<AttendanceDayMetrics> days;
  final ValueChanged<_DesktopPunchDatePreset> onPresetChanged;
  final VoidCallback onPickSpecificDate;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historial de asistencia',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Filtra y revisa tus registros de jornada, horas trabajadas y observaciones del período seleccionado.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in _DesktopPunchDatePreset.values)
                ChoiceChip(
                  selected: preset == item,
                  label: Text(_presetLabel(item)),
                  onSelected: (_) => onPresetChanged(item),
                ),
              OutlinedButton.icon(
                onPressed: onPickSpecificDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  specificDate == null
                      ? 'Fecha específica'
                      : DateFormat('dd/MM/yyyy').format(specificDate!),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onPickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  customRange == null
                      ? 'Rango personalizado'
                      : '${DateFormat('dd/MM').format(customRange!.start)} - ${DateFormat('dd/MM').format(customRange!.end)}',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rangeLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _PunchHistoryTableHeader(),
          const SizedBox(height: 10),
          if (days.isEmpty)
            const _DesktopPunchEmptyState(
              icon: Icons.history_toggle_off_outlined,
              title: 'Sin registros en este período',
              message:
                  'Prueba otro filtro para revisar días anteriores o amplía el rango de consulta.',
            )
          else
            ...days.map((day) => _PunchHistoryRow(day: day)),
        ],
      ),
    );
  }

  String _presetLabel(_DesktopPunchDatePreset preset) {
    switch (preset) {
      case _DesktopPunchDatePreset.hoy:
        return 'Hoy';
      case _DesktopPunchDatePreset.semana:
        return 'Esta semana';
      case _DesktopPunchDatePreset.quincena:
        return 'Quincena';
      case _DesktopPunchDatePreset.fecha:
        return 'Fecha';
      case _DesktopPunchDatePreset.rango:
        return 'Rango';
    }
  }
}

class _PunchHistoryTableHeader extends StatelessWidget {
  const _PunchHistoryTableHeader();

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.labelLarge!.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w800,
      ),
      child: const Row(
        children: [
          Expanded(flex: 20, child: Text('Fecha')),
          Expanded(flex: 14, child: Text('Entrada')),
          Expanded(flex: 14, child: Text('Salida')),
          Expanded(flex: 14, child: Text('Laborado')),
          Expanded(flex: 16, child: Text('Estado')),
          Expanded(flex: 22, child: Text('Observaciones')),
        ],
      ),
    );
  }
}

class _PunchHistoryRow extends StatelessWidget {
  const _PunchHistoryRow({required this.day});

  final AttendanceDayMetrics day;

  @override
  Widget build(BuildContext context) {
    final status = _statusForDay(day);
    final date = DateTime.tryParse('${day.date}T00:00:00');
    final observations = <String>[];
    if (day.tardinessMinutes > 0) {
      observations.add('Retraso ${_formatMinutesInline(day.tardinessMinutes)}');
    }
    if (day.earlyLeaveMinutes > 0) {
      observations.add(
        'Salida temprana ${_formatMinutesInline(day.earlyLeaveMinutes)}',
      );
    }
    if (day.incomplete) observations.add('Registro incompleto');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 20,
            child: Text(
              date == null ? day.date : DateFormat('dd/MM/yyyy').format(date),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              day.entry == null
                  ? 'Pendiente'
                  : DateFormat('h:mm a', 'es_DO').format(day.entry!.toLocal()),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              day.exit == null
                  ? 'Pendiente'
                  : DateFormat('h:mm a', 'es_DO').format(day.exit!.toLocal()),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(_formatMinutesInline(day.workedMinutesNet ?? 0)),
          ),
          Expanded(
            flex: 16,
            child: _PunchDayStatusBadge(status: status.$1, color: status.$2),
          ),
          Expanded(
            flex: 22,
            child: Text(
              observations.isEmpty
                  ? 'Sin observaciones'
                  : observations.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchDayStatusBadge extends StatelessWidget {
  const _PunchDayStatusBadge({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PunchStatusBadgeOnLight extends StatelessWidget {
  const _PunchStatusBadgeOnLight({required this.status});

  final _PunchStatusVisual status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, color: status.color, size: 18),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchMiniMetric extends StatelessWidget {
  const _PunchMiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PunchCircularCompliance extends StatelessWidget {
  const _PunchCircularCompliance({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 10,
                backgroundColor: const Color(0xFFE2E8F0),
                color: const Color(0xFF1D4ED8),
              ),
              Center(
                child: Text(
                  '${(value * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Porcentaje de cumplimiento del período seleccionado.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _PunchMetricBar extends StatelessWidget {
  const _PunchMetricBar({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: const Color(0xFFE2E8F0),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PunchInfoTile extends StatelessWidget {
  const _PunchInfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DesktopPunchEmptyState extends StatelessWidget {
  const _DesktopPunchEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: const Color(0xFF0284C7)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _formatMinutesInline(int minutes) {
  final sign = minutes < 0 ? '-' : '';
  final absolute = minutes.abs();
  final hours = absolute ~/ 60;
  final remainingMinutes = absolute % 60;
  return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
}

(String, Color) _statusForDay(AttendanceDayMetrics day) {
  if (day.isWeekend) return ('Libre', const Color(0xFF64748B));
  if (day.incomplete && day.entry != null && day.exit == null) {
    return ('En jornada', const Color(0xFF16A34A));
  }
  if (day.incomplete) return ('Incompleto', const Color(0xFFDC2626));
  if (day.tardinessMinutes > 0) return ('Retraso', const Color(0xFFEA580C));
  if (day.balanceMinutes >= 0) return ('Cumplida', const Color(0xFF15803D));
  return ('Pendiente', const Color(0xFFB91C1C));
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
