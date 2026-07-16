import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/debug/trace_log.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/user/data/users_repository.dart';
import 'application/nomina_controller.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

typedef _PayrollPeriodRow = ({
  PayrollEmployee employee,
  PayrollTotals totals,
  PayrollPaymentRecord paymentStatus,
});

class _PayrollBulkSendProgress {
  const _PayrollBulkSendProgress({
    required this.processed,
    required this.total,
    required this.currentEmployee,
  });

  final int processed;
  final int total;
  final String currentEmployee;

  double get value => total <= 0 ? 0 : processed / total;
}

class NominaScreen extends ConsumerStatefulWidget {
  const NominaScreen({super.key});

  @override
  ConsumerState<NominaScreen> createState() => _NominaScreenState();
}

class _NominaScreenState extends ConsumerState<NominaScreen> {
  bool _showEmployeesSection = false;
  bool _sendingPayrollToAll = false;

  Widget _buildDesktopAdminBody(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final openPeriod = state.openPeriod;
    final activePayrollEmployees = state.employees
        .where((employee) => employee.activo)
        .toList(growable: false);
    final activeEmployees = activePayrollEmployees.length;
    final payrollBase = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.salarioBaseQuincenal,
    );
    final payrollQuota = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.cuotaMinima,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Main scrollable content ──────────────────────────────────────────
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF2F5F8),
            child: RefreshIndicator(
              onRefresh: ref.read(nominaHomeControllerProvider.notifier).load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.error != null) ...[
                      _NominaErrorBanner(message: state.error!),
                      const SizedBox(height: 10),
                    ],
                    _NominaDesktopEmployeePanel(
                      employees: activePayrollEmployees,
                      loading: state.loading,
                      onAdd: () => _showEmployeeDialog(context, ref),
                      onManage: (e) =>
                          _showEmployeePayrollDialog(context, ref, e),
                      onEdit: (e) =>
                          _showEmployeeDialog(context, ref, employee: e),
                      onDelete: (e) => _confirmDeleteEmployee(context, ref, e),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ── Right sidebar ────────────────────────────────────────────────────
        _NominaDesktopSidebar(
          openPeriod: openPeriod,
          totalAbierto: state.openPeriodTotal ?? 0,
          payrollBase: payrollBase,
          payrollQuota: payrollQuota,
          activeEmployees: activeEmployees,
          money: money,
          loading: state.loading,
          sendingToAll: _sendingPayrollToAll,
          onHistory: state.loading
              ? null
              : () => _openPayrollHistoryDialog(context, ref, state),
          onTotals: state.loading
              ? null
              : () => _openOpenPeriodTotalsDialog(context, ref, state),
          onPdf: state.loading
              ? null
              : () => _exportOpenPeriodPdf(context, ref, state),
          onSendAll: state.loading || _sendingPayrollToAll || openPeriod == null
              ? null
              : () => _sendOpenPeriodPayrollToAll(context, ref, state),
          onAddEmployee: () => _showEmployeeDialog(context, ref),
          onClosePeriod: openPeriod == null
              ? null
              : () => _confirmClosePeriod(context, ref, openPeriod),
          onCreatePeriod: openPeriod == null
              ? () => _showCreatePeriodDialog(context, ref)
              : null,
        ),
      ],
    );
  }

  Widget _buildMobileAdminBody(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final openPeriod = state.openPeriod;
    final activePayrollEmployees = state.employees
        .where((employee) => employee.activo)
        .toList(growable: false);
    final activeEmployees = activePayrollEmployees.length;
    final payrollBase = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.salarioBaseQuincenal,
    );
    final payrollQuota = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.cuotaMinima,
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF6F8), Color(0xFFF5F8FB), Color(0xFFF5F8FB)],
          stops: [0, 0.22, 0.22],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: ref.read(nominaHomeControllerProvider.notifier).load,
        child: state.loading && state.periods.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                    children: [
                      _NominaPremiumHeroCard(
                        title:
                            openPeriod?.title ?? 'Nomina sin quincena abierta',
                        range: openPeriod == null
                            ? 'Abre una quincena para comenzar'
                            : '${DateFormat('dd/MM/yyyy').format(openPeriod.startDate)} - ${DateFormat('dd/MM/yyyy').format(openPeriod.endDate)}',
                        totalLabel: money.format(state.openPeriodTotal ?? 0),
                        activeEmployees: activeEmployees,
                        onHistory: state.loading
                            ? null
                            : () => _openPayrollHistoryDialog(
                                context,
                                ref,
                                state,
                              ),
                        onTotals: state.loading
                            ? null
                            : () => _openOpenPeriodTotalsDialog(
                                context,
                                ref,
                                state,
                              ),
                        onPdf: state.loading
                            ? null
                            : () => _exportOpenPeriodPdf(context, ref, state),
                        onSendAllPayroll:
                            state.loading ||
                                _sendingPayrollToAll ||
                                openPeriod == null
                            ? null
                            : () => _sendOpenPeriodPayrollToAll(
                                context,
                                ref,
                                state,
                              ),
                        onAddEmployee: () => _showEmployeeDialog(context, ref),
                        onClosePeriod: openPeriod == null
                            ? null
                            : () =>
                                  _confirmClosePeriod(context, ref, openPeriod),
                        onCreatePeriod: openPeriod == null
                            ? () => _showCreatePeriodDialog(context, ref)
                            : null,
                        compact: true,
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        _NominaErrorBanner(message: state.error!),
                      ],
                      const SizedBox(height: 10),
                      _NominaPrimaryBoard(
                        openPeriod: openPeriod,
                        totalAbierto: state.openPeriodTotal ?? 0,
                        payrollBase: payrollBase,
                        payrollQuota: payrollQuota,
                        activeEmployees: activeEmployees,
                        money: money,
                        compact: true,
                      ),
                      const SizedBox(height: 10),
                      _NominaUsersSectionCard(
                        expanded: _showEmployeesSection,
                        employees: activePayrollEmployees,
                        onToggle: () => setState(
                          () => _showEmployeesSection = !_showEmployeesSection,
                        ),
                        onAdd: () => _showEmployeeDialog(context, ref),
                        child: activePayrollEmployees.isEmpty
                            ? _NominaEmptyState(
                                icon: Icons.groups_outlined,
                                title: 'No hay usuarios en nomina',
                                message:
                                    'Agrega un usuario nuevo cuando lo necesites.',
                                actionLabel: 'Agregar usuario',
                                onAction: () =>
                                    _showEmployeeDialog(context, ref),
                              )
                            : Column(
                                children: activePayrollEmployees
                                    .map(
                                      (employee) => _EmployeeCard(
                                        employee: employee,
                                        onManage: () =>
                                            _showEmployeePayrollDialog(
                                              context,
                                              ref,
                                              employee,
                                            ),
                                        onEdit: () => _showEmployeeDialog(
                                          context,
                                          ref,
                                          employee: employee,
                                        ),
                                        onDelete: () => _confirmDeleteEmployee(
                                          context,
                                          ref,
                                          employee,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nominaTheme = theme.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF2F5F8),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: scheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: theme.dialogTheme.copyWith(backgroundColor: scheme.surface),
    );

    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isAdmin = currentUser?.role == 'ADMIN';
    final isDesktop = MediaQuery.sizeOf(context).width >= 1240;

    if (!isAdmin) {
      return Theme(
        data: nominaTheme,
        child: Scaffold(
          appBar: const CustomAppBar(
            title: 'Nómina',
            showLogo: false,
            showDepartmentLabel: false,
          ),
          drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 46,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Este módulo es solo para administración',
                    style: TextStyle(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.misPagos),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Ir a Mis Pagos'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final state = ref.watch(nominaHomeControllerProvider);
    final controller = ref.read(nominaHomeControllerProvider.notifier);

    return Theme(
      data: nominaTheme,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Nómina',
          showLogo: false,
          showDepartmentLabel: false,
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: state.loading ? null : controller.load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Nueva quincena',
              onPressed: () => _showCreatePeriodDialog(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
        floatingActionButton: null,
        body: isDesktop
            ? _buildDesktopAdminBody(context, ref, state)
            : _buildMobileAdminBody(context, ref, state),
      ),
    );
  }

  Future<void> _confirmDeleteEmployee(
    BuildContext context,
    WidgetRef ref,
    PayrollEmployee employee,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar de nómina'),
        content: Text(
          '¿Deseas eliminar a "${employee.nombre}" de nómina?\n\n'
          'Esto no elimina el usuario de la app, solo lo quita del módulo de nómina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .deleteEmployee(employee.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empleado eliminado de nómina')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Future<List<_PayrollPeriodRow>> _loadOpenPeriodRows(
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) return const [];

    final repo = ref.read(nominaRepositoryProvider);
    final employees =
        state.employees
            .where((employee) => employee.activo)
            .toList(growable: false)
          ..sort((a, b) => a.nombre.compareTo(b.nombre));

    final rows = <_PayrollPeriodRow>[];
    final statuses = await repo.listPaymentStatuses(periodId: open.id);
    final statusesByEmployee = {
      for (final status in statuses) status.employeeId: status,
    };
    for (final employee in employees) {
      final totals = await repo.computeTotals(open.id, employee.id);
      rows.add((
        employee: employee,
        totals: totals,
        paymentStatus:
            statusesByEmployee[employee.id] ??
            PayrollPaymentRecord.draft(
              periodId: open.id,
              employeeId: employee.id,
            ),
      ));
    }
    return rows;
  }

  Future<List<_PayrollPeriodRow>> _loadRowsForPeriod(
    WidgetRef ref,
    NominaHomeState state,
    PayrollPeriod period,
  ) async {
    final repo = ref.read(nominaRepositoryProvider);
    final employees = [...state.employees]
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    final statuses = await repo.listPaymentStatuses(periodId: period.id);
    final statusesByEmployee = {
      for (final status in statuses) status.employeeId: status,
    };
    final rows = <_PayrollPeriodRow>[];
    for (final employee in employees) {
      final totals = await repo.computeTotals(period.id, employee.id);
      rows.add((
        employee: employee,
        totals: totals,
        paymentStatus:
            statusesByEmployee[employee.id] ??
            PayrollPaymentRecord.draft(
              periodId: period.id,
              employeeId: employee.id,
            ),
      ));
    }
    return rows;
  }

  Future<void> _openPayrollHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final pastPeriods = state.periods.where((p) => !p.isOpen).toList();

    if (pastPeriods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quincenas pasadas para mostrar')),
      );
      return;
    }

    final repo = ref.read(nominaRepositoryProvider);
    final historyItems = <_PayrollHistoryPeriodSummary>[];
    for (final period in pastPeriods) {
      final total = await repo.computePeriodTotalAllEmployees(period.id);
      historyItems.add(
        _PayrollHistoryPeriodSummary(period: period, total: total),
      );
    }
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => _PayrollHistoryFullScreen(
          items: historyItems,
          onOpenDetails: (period) =>
              _openPastPeriodDetailsDialog(routeContext, ref, state, period),
          onEditPayroll: (dialogContext, period, row) =>
              _showEmployeePayrollDialog(
                dialogContext,
                ref,
                row.employee,
                periodOverride: period,
                paidLocked: row.paymentStatus.isPaid,
              ),
          onSendPayroll: (dialogContext, period, row) => _sendPayrollToWhatsApp(
            dialogContext,
            ref,
            period: period,
            employee: row.employee,
            totals: row.totals,
          ),
          onSchedulePayroll: (dialogContext, period, row) =>
              _schedulePayrollToWhatsApp(
                dialogContext,
                ref,
                period: period,
                employee: row.employee,
                totals: row.totals,
              ),
          onPreviewPayroll: (dialogContext, period, row) =>
              _previewEmployeePayrollPdf(
                dialogContext,
                ref,
                period: period,
                employee: row.employee,
                totals: row.totals,
              ),
        ),
      ),
    );
  }

  Future<void> _openPastPeriodDetailsDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
    PayrollPeriod period,
  ) async {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final repo = ref.read(nominaRepositoryProvider);
    final rows = await _loadRowsForPeriod(ref, state, period);
    if (!context.mounted) return;

    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => _PayrollPeriodDetailsScreen(
          period: period,
          rows: rows,
          totalPagar: totalPagar,
          onOpenPdf: () =>
              _openOpenPeriodPdfPreviewDialog(routeContext, period, rows),
          onSendPayroll: (row) => _sendPayrollToWhatsApp(
            routeContext,
            ref,
            period: period,
            employee: row.employee,
            totals: row.totals,
          ),
          onSchedulePayroll: (row) => _schedulePayrollToWhatsApp(
            routeContext,
            ref,
            period: period,
            employee: row.employee,
            totals: row.totals,
          ),
          onPreviewPayroll: (row) => _previewEmployeePayrollPdf(
            routeContext,
            ref,
            period: period,
            employee: row.employee,
            totals: row.totals,
          ),
          onEditPayroll: (row) => _showEmployeePayrollDialog(
            routeContext,
            ref,
            row.employee,
            periodOverride: period,
            paidLocked: row.paymentStatus.isPaid,
          ),
          onMarkPaid: (row) async {
            final status = await repo.markPayrollPaid(
              periodId: period.id,
              employeeId: row.employee.id,
            );
            if (!routeContext.mounted) return null;
            ScaffoldMessenger.of(routeContext).showSnackBar(
              SnackBar(
                content: Text(
                  'Nomina de ${row.employee.nombre} marcada como pagada',
                ),
              ),
            );
            return status;
          },
          onReloadRows: () => _loadRowsForPeriod(ref, state, period),
          money: money,
        ),
      ),
    );
  }

  Future<void> _openOpenPeriodTotalsDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay quincena abierta')));
      return;
    }

    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final rows = await _loadOpenPeriodRows(ref, state);
    if (!context.mounted) return;

    final totalBase = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = rows.fold<double>(
      0,
      (sum, row) =>
          sum + row.totals.commissions + row.totals.serviceCommissions,
    );
    final totalBonos = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalDeductions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Totales de quincena actual'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quincena: ${open.title}'),
              Text('Empleados: ${rows.length}'),
              const SizedBox(height: 10),
              _summaryLine('Total base', money.format(totalBase)),
              _summaryLine(
                'Comisión por ventas',
                money.format(totalCommissions),
              ),
              _summaryLine('Bonos / extras', money.format(totalBonos)),
              _summaryLine('Deducciones', money.format(totalDeductions)),
              const Divider(height: 14),
              _summaryLine(
                'TOTAL GENERAL A PAGAR',
                money.format(totalPagar),
                highlight: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _openOpenPeriodPdfPreviewDialog(context, open, rows);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generar PDF'),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildOpenPeriodPayrollPdfBytes(
    PayrollPeriod open,
    List<_PayrollPeriodRow> rows,
  ) async {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final doc = pw.Document();

    final totalBase = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = rows.fold<double>(
      0,
      (sum, row) =>
          sum + row.totals.commissions + row.totals.serviceCommissions,
    );
    final totalBonos = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalDeductions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'Nómina quincenal - ${open.title}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Empleado',
              'Base',
              'Comisión',
              'Bonos/Extras',
              'Deducciones',
              'Neto',
            ],
            data: rows
                .map(
                  (row) => [
                    row.employee.nombre,
                    money.format(row.totals.baseSalary),
                    money.format(
                      row.totals.commissions + row.totals.serviceCommissions,
                    ),
                    money.format(
                      row.totals.bonuses + row.totals.otherAdditions,
                    ),
                    money.format(row.totals.deductions),
                    money.format(row.totals.total),
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 280,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _pdfTotalLine('Total base', money.format(totalBase)),
                  _pdfTotalLine('Comisión', money.format(totalCommissions)),
                  _pdfTotalLine('Bonos / extras', money.format(totalBonos)),
                  _pdfTotalLine('Deducciones', money.format(totalDeductions)),
                  pw.Divider(height: 10),
                  _pdfTotalLine(
                    'TOTAL GENERAL',
                    money.format(totalPagar),
                    highlight: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildEmployeePayrollPdfBytes({
    required WidgetRef ref,
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
  }) async {
    final settings = await ref
        .read(companySettingsRepositoryProvider)
        .getSettings();
    final entries = await ref
        .read(nominaRepositoryProvider)
        .listEntries(period.id, employee.id);
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final companyName = settings.companyName.trim().isEmpty
        ? 'FULLTECH'
        : settings.companyName.trim();
    final companyRnc = settings.rnc.trim();
    final companyPhone = settings.phone.trim();
    final range =
        '${DateFormat('dd/MM/yyyy').format(period.startDate)} - ${DateFormat('dd/MM/yyyy').format(period.endDate)}';
    final roleLabel = (employee.puesto ?? '').trim().isEmpty
        ? 'Empleado'
        : employee.puesto!.trim();

    final doc = pw.Document(
      title: 'Nomina ${employee.nombre}',
      author: companyName,
    );
    final primary = PdfColor.fromInt(0xFF0B5D6E);
    final primaryDark = PdfColor.fromInt(0xFF083E4A);
    final surface = PdfColor.fromInt(0xFFF4F7FA);
    final lineColor = PdfColor.fromInt(0xFFE0E7EF);
    final danger = PdfColor.fromInt(0xFFB42318);

    pw.Widget amountLine(
      String label,
      String value, {
      bool strong = false,
      PdfColor? color,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: lineColor, width: 0.45),
          ),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: strong ? 10.5 : 9.5,
                  fontWeight: strong
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: PdfColors.blueGrey800,
                ),
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: strong ? 10.5 : 9.5,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? PdfColors.blueGrey900,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget section(String title, List<pw.Widget> children) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: lineColor, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: primaryDark,
              ),
            ),
            pw.SizedBox(height: 5),
            ...children,
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.blueGrey400,
            ),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: primary,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      if (companyRnc.isNotEmpty)
                        pw.Text(
                          'RNC: $companyRnc',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                          ),
                        ),
                      if (companyPhone.isNotEmpty)
                        pw.Text(
                          'Tel: $companyPhone',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'COMPROBANTE DE NOMINA',
                        style: pw.TextStyle(
                          color: primaryDark,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        DateFormat('dd/MM/yyyy').format(DateTime.now()),
                        style: const pw.TextStyle(
                          color: PdfColors.blueGrey600,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: surface,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: lineColor, width: 0.8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        employee.nombre,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Cargo: $roleLabel',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.blueGrey700,
                        ),
                      ),
                      pw.Text(
                        'Quincena: ${period.title}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.blueGrey700,
                        ),
                      ),
                      pw.Text(
                        'Rango: $range',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.blueGrey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: lineColor, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Total pagado',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.blueGrey600,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        money.format(totals.total),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          section('ADICIONES', [
            amountLine('Salario quincenal', money.format(totals.baseSalary)),
            if (totals.serviceCommissions > 0)
              amountLine(
                'Comision por instalaciones',
                money.format(totals.serviceCommissions),
              ),
            if (totals.commissions > 0)
              amountLine(
                'Comision por ventas',
                money.format(totals.commissions),
              ),
            if (totals.bonuses > 0)
              amountLine('Bonificaciones', money.format(totals.bonuses)),
            if (totals.holidayWorked > 0)
              amountLine(
                'Feriados trabajados',
                money.format(totals.holidayWorked),
              ),
            if (totals.otherAdditions > 0)
              amountLine('Otros ingresos', money.format(totals.otherAdditions)),
            amountLine(
              'Total adiciones',
              money.format(totals.additions),
              strong: true,
              color: primaryDark,
            ),
          ]),
          section('DEDUCCIONES', [
            if (totals.seguroLey > 0)
              amountLine(
                'Seguro de ley',
                money.format(totals.seguroLey),
                color: danger,
              ),
            if (totals.absences > 0)
              amountLine(
                'Ausencias',
                money.format(totals.absences),
                color: danger,
              ),
            if (totals.late > 0)
              amountLine('Tardanzas', money.format(totals.late), color: danger),
            if (totals.advances > 0)
              amountLine(
                'Adelantos',
                money.format(totals.advances),
                color: danger,
              ),
            if (totals.otherDeductions > 0)
              amountLine(
                'Otros descuentos',
                money.format(totals.otherDeductions),
                color: danger,
              ),
            if (totals.deductions <= 0)
              amountLine('Sin deducciones', money.format(0)),
            amountLine(
              'Total deducciones',
              money.format(totals.deductions),
              strong: true,
              color: danger,
            ),
          ]),
          if (entries.isNotEmpty)
            section('MOVIMIENTOS DE LA QUINCENA', [
              pw.TableHelper.fromTextArray(
                headers: const ['Fecha', 'Tipo', 'Concepto', 'Monto'],
                data: entries
                    .map(
                      (entry) => [
                        DateFormat('dd/MM/yyyy').format(entry.date),
                        entry.type.label,
                        entry.concept,
                        money.format(entry.amount),
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                border: pw.TableBorder.all(color: lineColor, width: 0.45),
              ),
            ]),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: primaryDark,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TOTAL PAGADO',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  money.format(totals.total),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Documento generado automaticamente por el sistema de nomina.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.blueGrey500,
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  String _buildEmployeePayrollPdfFileName(
    PayrollEmployee employee,
    PayrollPeriod period,
  ) {
    String sanitize(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
    }

    final employeeSlug = sanitize(employee.nombre).isEmpty
        ? 'empleado'
        : sanitize(employee.nombre);
    final periodSlug = sanitize(period.title).isEmpty
        ? 'quincena'
        : sanitize(period.title);
    return 'nomina_${employeeSlug}_$periodSlug.pdf';
  }

  Future<void> _sendPayrollToWhatsApp(
    BuildContext context,
    WidgetRef ref, {
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
    bool showSuccessFeedback = true,
  }) async {
    final repo = ref.read(nominaRepositoryProvider);
    final bytes = await _buildEmployeePayrollPdfBytes(
      ref: ref,
      period: period,
      employee: employee,
      totals: totals,
    );

    try {
      await repo.sendPayrollToWhatsApp(
        employeeId: employee.id,
        periodId: period.id,
        bytes: bytes,
        fileName: _buildEmployeePayrollPdfFileName(employee, period),
      );
    } catch (error) {
      if (!showSuccessFeedback) rethrow;
      if (!context.mounted) return;
      final message = error is ApiException ? error.message : error.toString();
      await AppFeedback.showError(
        context,
        'No se pudo enviar la nomina a ${employee.nombre}: $message',
        fallbackContext: context,
        scope: 'NominaSendPayroll',
      );
      return;
    }

    if (!showSuccessFeedback || !context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Nómina enviada por WhatsApp a ${employee.nombre}',
      fallbackContext: context,
      scope: 'NominaSendPayroll',
    );
  }

  Future<void> _previewEmployeePayrollPdf(
    BuildContext context,
    WidgetRef ref, {
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
  }) async {
    final bytes = await _buildEmployeePayrollPdfBytes(
      ref: ref,
      period: period,
      employee: employee,
      totals: totals,
    );

    if (!context.mounted) return;
    await Printing.layoutPdf(
      name: _buildEmployeePayrollPdfFileName(employee, period),
      onLayout: (_) async => bytes,
    );
  }

  Future<DateTime?> _pickPayrollScheduledAt(BuildContext context) async {
    var selected = DateTime.now().add(const Duration(hours: 1));

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          final label = DateFormat(
            'dd/MM/yyyy h:mm a',
            'es_DO',
          ).format(selected);

          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: selected,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked == null) return;
            setStateDialog(() {
              selected = DateTime(
                picked.year,
                picked.month,
                picked.day,
                selected.hour,
                selected.minute,
              );
            });
          }

          Future<void> pickTime() async {
            final picked = await showTimePicker(
              context: dialogContext,
              initialTime: TimeOfDay.fromDateTime(selected),
            );
            if (picked == null) return;
            setStateDialog(() {
              selected = DateTime(
                selected.year,
                selected.month,
                selected.day,
                picked.hour,
                picked.minute,
              );
            });
          }

          return AlertDialog(
            title: const Text('Programar envio'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Se enviara en: $label'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickDate,
                        icon: const Icon(Icons.event_outlined),
                        label: const Text('Fecha'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickTime,
                        icon: const Icon(Icons.schedule_outlined),
                        label: const Text('Hora'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (selected.isBefore(DateTime.now())) {
                    AppFeedback.showError(
                      dialogContext,
                      'Selecciona una fecha y hora futura.',
                      fallbackContext: dialogContext,
                      scope: 'NominaSchedulePayroll',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, selected);
                },
                icon: const Icon(Icons.schedule_send_outlined),
                label: const Text('Programar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _schedulePayrollToWhatsApp(
    BuildContext context,
    WidgetRef ref, {
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
  }) async {
    final scheduledAt = await _pickPayrollScheduledAt(context);
    if (scheduledAt == null || !context.mounted) return;

    final bytes = await _buildEmployeePayrollPdfBytes(
      ref: ref,
      period: period,
      employee: employee,
      totals: totals,
    );

    try {
      await ref
          .read(nominaRepositoryProvider)
          .schedulePayrollToWhatsApp(
            employeeId: employee.id,
            periodId: period.id,
            bytes: bytes,
            fileName: _buildEmployeePayrollPdfFileName(employee, period),
            scheduledFor: scheduledAt,
          );
    } catch (error) {
      if (!context.mounted) return;
      final message = error is ApiException ? error.message : error.toString();
      await AppFeedback.showError(
        context,
        'No se pudo programar la nomina de ${employee.nombre}: $message',
        fallbackContext: context,
        scope: 'NominaSchedulePayroll',
      );
      return;
    }

    if (!context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Nomina de ${employee.nombre} programada para ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(scheduledAt)}.',
      fallbackContext: context,
      scope: 'NominaSchedulePayroll',
    );
  }

  Future<void> _sendOpenPeriodPayrollToAll(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      await AppFeedback.showError(
        context,
        'No hay quincena abierta para enviar.',
        fallbackContext: context,
        scope: 'NominaSendPayrollAll',
      );
      return;
    }

    final rows = await _loadOpenPeriodRows(ref, state);
    if (!context.mounted) return;

    if (rows.isEmpty) {
      await AppFeedback.showError(
        context,
        'No hay empleados activos en nómina para enviar.',
        fallbackContext: context,
        scope: 'NominaSendPayrollAll',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar nómina a todo'),
        content: Text(
          'Se enviará la nómina de ${open.title} a ${rows.length} usuario(s) de forma automática por WhatsApp. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar a todos'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _sendingPayrollToAll = true);

    final progress = ValueNotifier<_PayrollBulkSendProgress>(
      _PayrollBulkSendProgress(
        processed: 0,
        total: rows.length,
        currentEmployee: rows.first.employee.nombre,
      ),
    );
    final failures = <String>[];

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<_PayrollBulkSendProgress>(
            valueListenable: progress,
            builder: (dialogContext, value, _) => AlertDialog(
              title: const Text('Enviando nómina a todos'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Procesando: ${value.currentEmployee}'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: value.value),
                    const SizedBox(height: 10),
                    Text('Enviados: ${value.processed} de ${value.total}'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    try {
      for (final row in rows) {
        progress.value = _PayrollBulkSendProgress(
          processed: progress.value.processed,
          total: progress.value.total,
          currentEmployee: row.employee.nombre,
        );

        try {
          await _sendPayrollToWhatsApp(
            context,
            ref,
            period: open,
            employee: row.employee,
            totals: row.totals,
            showSuccessFeedback: false,
          );
        } catch (error) {
          final message = error is ApiException
              ? error.message
              : error.toString();
          failures.add('${row.employee.nombre}: $message');
        } finally {
          progress.value = _PayrollBulkSendProgress(
            processed: progress.value.processed + 1,
            total: progress.value.total,
            currentEmployee: row.employee.nombre,
          );
        }
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
      if (mounted) {
        setState(() => _sendingPayrollToAll = false);
      }
    }

    if (!context.mounted) return;

    if (failures.isEmpty) {
      await AppFeedback.showInfo(
        context,
        'Se enviaron ${rows.length} nóminas por WhatsApp correctamente.',
        fallbackContext: context,
        scope: 'NominaSendPayrollAll',
      );
      return;
    }

    final successCount = rows.length - failures.length;
    await AppFeedback.showError(
      context,
      'Se enviaron $successCount de ${rows.length} nóminas. Fallaron ${failures.length}: ${failures.join(' | ')}',
      fallbackContext: context,
      scope: 'NominaSendPayrollAll',
    );
  }

  pw.Widget _pdfTotalLine(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOpenPeriodPdfPreviewDialog(
    BuildContext context,
    PayrollPeriod open,
    List<_PayrollPeriodRow> rows,
  ) async {
    final pdfBytes = await _buildOpenPeriodPayrollPdfBytes(open, rows);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 920,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PDF Nómina · ${open.title}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final fileName =
                            'nomina_${open.title.replaceAll(' ', '_')}.pdf';
                        await Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: fileName,
                        );
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Descargar'),
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
      ),
    );
  }

  Future<void> _showEmployeeDialog(
    BuildContext context,
    WidgetRef ref, {
    PayrollEmployee? employee,
  }) async {
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    TraceLog.log(
      'NominaEmployeeDialog',
      'open employeeId=${employee?.id ?? 'new'} scaffoldMounted=${scaffoldContext.mounted}',
      seq: flowSeq,
    );

    UserModel? selectedUser;
    if (employee == null) {
      final existingUserIds = ref
          .read(nominaHomeControllerProvider)
          .employees
          .where((item) => item.activo)
          .map((item) => item.id)
          .toSet();
      selectedUser = await showDialog<UserModel>(
        context: context,
        builder: (_) =>
            _PayrollUserPickerDialog(excludedUserIds: existingUserIds),
      );
      if (!context.mounted) return;
      if (selectedUser == null) return;
    }

    final successMessage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayrollEmployeeDialog(
        employee: employee,
        selectedUser: selectedUser,
        traceSeq: flowSeq,
      ),
    );

    if (successMessage == null || !scaffoldContext.mounted) return;

    await AppFeedback.showInfo(
      scaffoldContext,
      successMessage,
      fallbackContext: scaffoldContext,
      scope: 'NominaEmployeeDialog',
    );
  }

  Future<void> _showEmployeePayrollDialog(
    BuildContext context,
    WidgetRef ref,
    PayrollEmployee employee, {
    PayrollPeriod? periodOverride,
    bool paidLocked = false,
  }) async {
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    TraceLog.log(
      'NominaEmployeePayrollDialog',
      'open employeeId=${employee.id} scaffoldMounted=${scaffoldContext.mounted}',
      seq: flowSeq,
    );

    final state = ref.read(nominaHomeControllerProvider);
    final open = periodOverride ?? state.openPeriod;
    if (open == null) {
      await AppFeedback.showError(
        scaffoldContext,
        'No hay quincena abierta',
        fallbackContext: scaffoldContext,
        scope: 'NominaEmployeePayrollDialog',
      );
      return;
    }

    final repo = ref.read(nominaRepositoryProvider);
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');

    var effectivePaidLocked = paidLocked;
    if (!effectivePaidLocked) {
      final statusRows = await repo.listPaymentStatuses(
        periodId: open.id,
        employeeId: employee.id,
      );
      effectivePaidLocked = statusRows.isNotEmpty && statusRows.first.isPaid;
    }

    var entries = await repo.listEntries(open.id, employee.id);
    var totals = await repo.computeTotals(open.id, employee.id);
    final config = await repo.getEmployeeConfig(open.id, employee.id);

    final conceptCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final seguroLeyCtrl = TextEditingController(
      text: employee.seguroLeyMonto.toStringAsFixed(2),
    );
    var dialogEmployee = employee;
    PayrollEntryType selectedType = PayrollEntryType.descuento;
    var editingSeguroLey = !employee.seguroLeyMontoLocked;
    var holidayWasWorked = true;
    var notifyUser = false;
    var isSavingEntry = false;
    var isSavingSeguroLey = false;
    var isSendingPayroll = false;
    final salaryForDailyRate =
        config?.baseSalary ?? employee.salarioBaseQuincenal;
    final dominicanDailySalary = salaryForDailyRate <= 0
        ? 0.0
        : (salaryForDailyRate * 2) / 23.83;

    double currentQuantity() {
      final raw = qtyCtrl.text.trim().replaceAll(',', '.');
      final qty = double.tryParse(raw) ?? 1;
      return qty > 0 ? qty : 1;
    }

    bool isAutomaticAmountType(PayrollEntryType type) {
      return type == PayrollEntryType.ausencia ||
          type == PayrollEntryType.feriadoTrabajado;
    }

    double automaticAmountForSelectedType() {
      final qty = currentQuantity();
      if (selectedType == PayrollEntryType.ausencia) {
        return -(dominicanDailySalary * qty);
      }
      if (selectedType == PayrollEntryType.feriadoTrabajado) {
        return holidayWasWorked ? dominicanDailySalary * qty : 0;
      }
      return 0;
    }

    void syncAutomaticAmount() {
      if (!isAutomaticAmountType(selectedType)) return;
      amountCtrl.text = automaticAmountForSelectedType().toStringAsFixed(2);
    }

    String amountHelperText() {
      if (selectedType == PayrollEntryType.ausencia) {
        return 'Auto: sueldo mensual / 23.83 x cantidad, aplicado como descuento.';
      }
      if (selectedType == PayrollEntryType.feriadoTrabajado) {
        return holidayWasWorked
            ? 'Auto: agrega 100% del salario diario para que el feriado quede doble.'
            : 'Si no se trabajo, no se agrega pago adicional.';
      }
      return 'Indica el monto manual de este movimiento.';
    }

    Future<void> reload(StateSetter setStateDialog) async {
      entries = await repo.listEntries(open.id, employee.id);
      totals = await repo.computeTotals(open.id, employee.id);
      setStateDialog(() {});
    }

    Future<void> saveSeguroLey(StateSetter setStateDialog) async {
      final raw = seguroLeyCtrl.text.trim().replaceAll(',', '.');
      final value = double.tryParse(raw);
      if (value == null || value < 0) {
        await AppFeedback.showError(
          scaffoldContext,
          'El seguro de ley debe ser un monto mayor o igual a 0',
          fallbackContext: context,
          scope: 'NominaEmployeePayrollDialog',
        );
        return;
      }

      setStateDialog(() => isSavingSeguroLey = true);
      try {
        final saved = await repo.upsertEmployee(
          dialogEmployee.copyWith(
            seguroLeyMonto: value,
            seguroLeyMontoLocked: false,
          ),
        );
        dialogEmployee = saved;
        seguroLeyCtrl.text = saved.seguroLeyMonto.toStringAsFixed(2);
        totals = await repo.computeTotals(open.id, saved.id);
        setStateDialog(() {
          editingSeguroLey = false;
          isSavingSeguroLey = false;
        });
        await ref.read(nominaHomeControllerProvider.notifier).load();
        if (!context.mounted || !scaffoldContext.mounted) return;
        await AppFeedback.showInfo(
          scaffoldContext,
          'Seguro de ley guardado para todas las quincenas',
          fallbackContext: context,
          scope: 'NominaEmployeePayrollDialog',
        );
      } catch (e, st) {
        TraceLog.log(
          'NominaEmployeePayrollDialog',
          'save seguro ley error',
          seq: flowSeq,
          error: e,
          stackTrace: st,
        );
        if (context.mounted) {
          setStateDialog(() => isSavingSeguroLey = false);
        }
        if (!context.mounted || !scaffoldContext.mounted) return;
        await AppFeedback.showError(
          scaffoldContext,
          'No se pudo guardar el seguro de ley: $e',
          fallbackContext: context,
          scope: 'NominaEmployeePayrollDialog',
        );
      }
    }

    if (!context.mounted) return;

    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: Text('Nómina de ${employee.nombre}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quincena: ${open.title}'),
                    const SizedBox(height: 6),
                    Text(
                      'Salario base: ${money.format(config?.baseSalary ?? employee.salarioBaseQuincenal)}',
                    ),
                    Text(
                      'Comisión por ventas (auto): ${money.format(totals.salesCommissionAuto)}',
                      style: TextStyle(
                        color: totals.salesGoalReached
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Meta (puntos): ${money.format(totals.salesGoal)} · Puntos: ${money.format(totals.salesAmountThisPeriod)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      totals.salesGoalReached
                          ? 'Meta alcanzada en puntos: comisión por ventas habilitada automáticamente.'
                          : 'Meta no alcanzada en puntos: comisión por ventas en RD\$0.00.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text('Seguro ley: ${money.format(totals.seguroLey)}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: seguroLeyCtrl,
                            enabled:
                                !effectivePaidLocked &&
                                editingSeguroLey &&
                                !isSavingSeguroLey,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Seguro de ley fijo',
                              helperText:
                                  'Descuento fijo por quincena para este usuario',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: editingSeguroLey
                              ? 'Editando seguro de ley'
                              : 'Editar seguro de ley',
                          onPressed:
                              effectivePaidLocked ||
                                  isSavingSeguroLey ||
                                  editingSeguroLey
                              ? null
                              : () => setStateDialog(
                                  () => editingSeguroLey = true,
                                ),
                          icon: Icon(
                            editingSeguroLey
                                ? Icons.lock_open_outlined
                                : Icons.edit_outlined,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Guardar seguro de ley',
                          onPressed:
                              effectivePaidLocked ||
                                  !editingSeguroLey ||
                                  isSavingSeguroLey
                              ? null
                              : () => saveSeguroLey(setStateDialog),
                          icon: isSavingSeguroLey
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                        ),
                      ],
                    ),
                    if (effectivePaidLocked) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text(
                          'Esta nomina fue pagada y no se puede editar',
                        ),
                      ),
                    ],
                    if (totals.holidayWorked > 0)
                      Text(
                        'Feriado trabajado: ${money.format(totals.holidayWorked)}',
                      ),
                    Text(
                      'Total neto: ${money.format(totals.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Agregar ajuste',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PayrollEntryType>(
                      initialValue: selectedType,
                      items: PayrollEntryType.values
                          .where(
                            (type) => type != PayrollEntryType.pagoCombustible,
                          )
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() {
                            selectedType = value;
                            if (value == PayrollEntryType.feriadoTrabajado) {
                              holidayWasWorked = true;
                              if (conceptCtrl.text.trim().isEmpty) {
                                conceptCtrl.text = 'Feriado trabajado';
                              }
                            } else if (value == PayrollEntryType.ausencia) {
                              if (conceptCtrl.text.trim().isEmpty) {
                                conceptCtrl.text = 'Ausencia';
                              }
                            } else {
                              amountCtrl.clear();
                            }
                            syncAutomaticAmount();
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: conceptCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Concepto',
                        hintText:
                            'Ej: Ausencia 12/02, bonificación por meta, descuento administrativo...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            onChanged: (_) =>
                                setStateDialog(syncAutomaticAmount),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            readOnly: isAutomaticAmountType(selectedType),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Monto',
                              helperText: amountHelperText(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selectedType == PayrollEntryType.feriadoTrabajado) ...[
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Se trabajo'),
                        subtitle: const Text(
                          'Aplica el 100% adicional del salario diario para completar el pago doble.',
                        ),
                        value: holidayWasWorked,
                        onChanged: (value) => setStateDialog(() {
                          holidayWasWorked = value;
                          syncAutomaticAmount();
                        }),
                      ),
                    ],
                    const SizedBox(height: 4),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enviar notificacion al usuario'),
                      subtitle: const Text(
                        'Activalo solo cuando quieras avisarle por WhatsApp.',
                      ),
                      value: notifyUser,
                      onChanged: (value) =>
                          setStateDialog(() => notifyUser = value),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: (isSavingEntry || effectivePaidLocked)
                          ? null
                          : () async {
                              TraceLog.log(
                                'NominaEmployeePayrollDialog',
                                'add adjustment start dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                                seq: flowSeq,
                              );
                              final concept = conceptCtrl.text.trim();
                              if (concept.isEmpty) {
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'Debes escribir un concepto',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                                return;
                              }
                              final qty =
                                  double.tryParse(qtyCtrl.text.trim()) ?? 1;
                              if (qty <= 0) {
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'La cantidad debe ser > 0',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                                return;
                              }

                              final parsedAmount = double.tryParse(
                                amountCtrl.text.trim(),
                              );
                              double amount;

                              if (selectedType ==
                                  PayrollEntryType.feriadoTrabajado) {
                                if (!holidayWasWorked) {
                                  await AppFeedback.showError(
                                    scaffoldContext,
                                    'Marca "Se trabajo" para registrar un feriado trabajado',
                                    fallbackContext: context,
                                    scope: 'NominaEmployeePayrollDialog',
                                  );
                                  return;
                                }
                                amount = automaticAmountForSelectedType();
                              } else if (selectedType ==
                                  PayrollEntryType.ausencia) {
                                amount = automaticAmountForSelectedType();
                              } else {
                                if (parsedAmount == null) {
                                  await AppFeedback.showError(
                                    scaffoldContext,
                                    'Monto invalido',
                                    fallbackContext: context,
                                    scope: 'NominaEmployeePayrollDialog',
                                  );
                                  return;
                                }
                                amount = parsedAmount;
                              }

                              if (selectedType.isDeduction && amount > 0) {
                                amount = -amount;
                              }
                              if (!selectedType.isDeduction &&
                                  selectedType != PayrollEntryType.otro &&
                                  amount < 0) {
                                amount = amount.abs();
                              }

                              setStateDialog(() => isSavingEntry = true);

                              try {
                                await repo.addEntry(
                                  PayrollEntry(
                                    id: '',
                                    ownerId: repo.ownerId,
                                    periodId: open.id,
                                    employeeId: employee.id,
                                    date: DateTime.now(),
                                    type: selectedType,
                                    concept: concept,
                                    amount: amount,
                                    cantidad: qty,
                                    notifyUser: notifyUser,
                                  ),
                                );

                                conceptCtrl.clear();
                                amountCtrl.clear();
                                qtyCtrl.text = '1';
                                setStateDialog(() {
                                  notifyUser = false;
                                  holidayWasWorked = true;
                                  if (isAutomaticAmountType(selectedType)) {
                                    syncAutomaticAmount();
                                  }
                                });
                                await reload(setStateDialog);
                                TraceLog.log(
                                  'NominaEmployeePayrollDialog',
                                  'add adjustment saved dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                                  seq: flowSeq,
                                );
                                if (!context.mounted) return;
                                if (!scaffoldContext.mounted) return;
                                await AppFeedback.showInfo(
                                  scaffoldContext,
                                  'Ajuste guardado',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                              } catch (e, st) {
                                TraceLog.log(
                                  'NominaEmployeePayrollDialog',
                                  'add adjustment error',
                                  seq: flowSeq,
                                  error: e,
                                  stackTrace: st,
                                );
                                if (!context.mounted) return;
                                if (!scaffoldContext.mounted) return;
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'No se pudo guardar el ajuste: $e',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                              } finally {
                                if (context.mounted) {
                                  setStateDialog(() => isSavingEntry = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.add),
                      label: isSavingEntry
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Agregar ajuste'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Movimientos de la quincena',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    if (entries.isEmpty)
                      const Text('Sin movimientos registrados')
                    else
                      ...entries.map(
                        (entry) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${entry.type.label}: ${entry.concept}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat('dd/MM/yyyy').format(entry.date),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money.format(entry.amount),
                                style: TextStyle(
                                  color: entry.amount < 0
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: () async {
                                  if (effectivePaidLocked) return;
                                  await repo.deleteEntry(entry.id);
                                  await reload(setStateDialog);
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton.filledTonal(
                tooltip: 'Ver PDF que se enviara',
                onPressed: isSendingPayroll
                    ? null
                    : () => _previewEmployeePayrollPdf(
                        scaffoldContext,
                        ref,
                        period: open,
                        employee: employee,
                        totals: totals,
                      ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              TextButton.icon(
                onPressed: isSendingPayroll
                    ? null
                    : () async {
                        setStateDialog(() => isSendingPayroll = true);
                        try {
                          await _sendPayrollToWhatsApp(
                            scaffoldContext,
                            ref,
                            period: open,
                            employee: employee,
                            totals: totals,
                          );
                        } catch (e, st) {
                          TraceLog.log(
                            'NominaEmployeePayrollDialog',
                            'send payroll whatsapp error',
                            seq: flowSeq,
                            error: e,
                            stackTrace: st,
                          );
                          if (!context.mounted) return;
                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showError(
                            scaffoldContext,
                            'No se pudo enviar la nómina: $e',
                            fallbackContext: context,
                            scope: 'NominaEmployeePayrollDialog',
                          );
                        } finally {
                          if (context.mounted) {
                            setStateDialog(() => isSendingPayroll = false);
                          }
                        }
                      },
                icon: isSendingPayroll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Enviar nómina'),
              ),
              IconButton.filledTonal(
                tooltip: 'Programar envio',
                onPressed: isSendingPayroll
                    ? null
                    : () => _schedulePayrollToWhatsApp(
                        scaffoldContext,
                        ref,
                        period: open,
                        employee: employee,
                        totals: totals,
                      ),
                icon: const Icon(Icons.event_available_outlined),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      conceptCtrl.dispose();
      amountCtrl.dispose();
      qtyCtrl.dispose();
      seguroLeyCtrl.dispose();
    }

    if (!context.mounted) return;
    await ref.read(nominaHomeControllerProvider.notifier).load();
  }

  Future<void> _exportOpenPeriodPdf(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quincena abierta para exportar')),
      );
      return;
    }

    final rows = await _loadOpenPeriodRows(ref, state);
    final bytes = await _buildOpenPeriodPayrollPdfBytes(open, rows);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<void> _showCreatePeriodDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    var isSubmitting = false;
    final titleCtrl = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 14));

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isSubmitting,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Nueva quincena'),
            content: AbsorbPointer(
              absorbing: isSubmitting,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inicio'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setStateDialog(() => start = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fin'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                    trailing: const Icon(Icons.date_range),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: end,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setStateDialog(() => end = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        TraceLog.log(
                          'NominaCreatePeriodDialog',
                          'submit start dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                          seq: flowSeq,
                        );

                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) {
                          await AppFeedback.showError(
                            scaffoldContext,
                            'Debes indicar un titulo',
                            fallbackContext: context,
                            scope: 'NominaCreatePeriodDialog',
                          );
                          return;
                        }

                        setStateDialog(() => isSubmitting = true);

                        try {
                          await ref
                              .read(nominaHomeControllerProvider.notifier)
                              .createPeriod(
                                start: start,
                                end: end,
                                title: title,
                              );

                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit success dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                            seq: flowSeq,
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                          }

                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showInfo(
                            scaffoldContext,
                            'Quincena creada correctamente',
                            fallbackContext: scaffoldContext,
                            scope: 'NominaCreatePeriodDialog',
                          );
                        } catch (e, st) {
                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit error',
                            seq: flowSeq,
                            error: e,
                            stackTrace: st,
                          );

                          if (!context.mounted) return;
                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showError(
                            scaffoldContext,
                            'No se pudo crear: $e',
                            fallbackContext: context,
                            scope: 'NominaCreatePeriodDialog',
                          );
                        } finally {
                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit finish dialogMounted=${context.mounted}',
                            seq: flowSeq,
                          );

                          if (context.mounted) {
                            setStateDialog(() => isSubmitting = false);
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleCtrl.dispose();
    }
  }

  Future<void> _confirmClosePeriod(
    BuildContext context,
    WidgetRef ref,
    PayrollPeriod period,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar quincena'),
        content: Text('¿Deseas cerrar "${period.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .closePeriod(period.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quincena cerrada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cerrar: $e')));
    }
  }
}

class _PayrollEmployeeDialog extends ConsumerStatefulWidget {
  const _PayrollEmployeeDialog({
    required this.employee,
    required this.selectedUser,
    required this.traceSeq,
  });

  final PayrollEmployee? employee;
  final UserModel? selectedUser;
  final int traceSeq;

  @override
  ConsumerState<_PayrollEmployeeDialog> createState() =>
      _PayrollEmployeeDialogState();
}

class _PayrollEmployeeDialogState
    extends ConsumerState<_PayrollEmployeeDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _seguroLeyCtrl;
  late final TextEditingController _cuotaCtrl;

  bool _isSubmitting = false;
  late bool _editingSeguroLey;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text:
          widget.employee?.nombre ?? widget.selectedUser?.nombreCompleto ?? '',
    );
    _phoneCtrl = TextEditingController(
      text: widget.employee?.telefono ?? widget.selectedUser?.telefono ?? '',
    );
    _roleCtrl = TextEditingController(
      text: widget.employee?.puesto ?? widget.selectedUser?.role ?? '',
    );
    _salaryCtrl = TextEditingController(
      text: widget.employee == null
          ? '0'
          : widget.employee!.salarioBaseQuincenal > 0
          ? widget.employee!.salarioBaseQuincenal.toStringAsFixed(2)
          : '',
    );
    _seguroLeyCtrl = TextEditingController(
      text: (widget.employee?.seguroLeyMonto ?? 0).toStringAsFixed(2),
    );
    _cuotaCtrl = TextEditingController(
      text: (widget.employee?.cuotaMinima ?? 0).toStringAsFixed(2),
    );
    _editingSeguroLey =
        widget.employee == null || !widget.employee!.seguroLeyMontoLocked;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _roleCtrl.dispose();
    _salaryCtrl.dispose();
    _seguroLeyCtrl.dispose();
    _cuotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    TraceLog.log(
      'NominaEmployeeDialog',
      'submit start mounted=$mounted',
      seq: widget.traceSeq,
    );

    final salaryText = _salaryCtrl.text.trim();
    final salary = salaryText.isEmpty ? null : double.tryParse(salaryText);
    final cuota = double.tryParse(_cuotaCtrl.text.trim()) ?? -1;
    final seguroLey = double.tryParse(_seguroLeyCtrl.text.trim()) ?? -1;

    String? validationError;
    if (widget.employee == null && salary == null) {
      validationError = 'El salario base es obligatorio al agregar';
    } else if (salary != null && salary < 0) {
      validationError = 'El salario base debe ser un numero >= 0';
    } else if (cuota < 0) {
      validationError = 'La cuota minima debe ser un numero >= 0';
    } else if (seguroLey < 0) {
      validationError = 'El seguro de ley debe ser un monto >= 0';
    } else if (widget.employee == null && widget.selectedUser != null) {
      final alreadyExists = ref
          .read(nominaHomeControllerProvider)
          .employees
          .where((e) => e.activo)
          .any((item) => item.id == widget.selectedUser!.id);
      if (alreadyExists) {
        validationError = 'Este usuario ya esta agregado en nomina';
      }
    }

    if (validationError != null) {
      if (!mounted) return;
      setState(() => _errorText = validationError);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .saveEmployee(
            id: widget.employee?.id ?? widget.selectedUser?.id,
            nombre: _nameCtrl.text,
            telefono: _phoneCtrl.text,
            puesto: _roleCtrl.text,
            salarioBase: salary,
            cuotaMinima: cuota,
            seguroLeyMonto: seguroLey,
            allowSeguroLeyMontoEdit: _editingSeguroLey,
            activo: widget.employee?.activo ?? true,
          );

      TraceLog.log(
        'NominaEmployeeDialog',
        'submit save ok mounted=$mounted',
        seq: widget.traceSeq,
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        widget.employee == null ? 'Empleado agregado' : 'Empleado actualizado',
      );
    } catch (e, st) {
      TraceLog.log(
        'NominaEmployeeDialog',
        'submit save error',
        seq: widget.traceSeq,
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'No se pudo guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(
          widget.employee == null ? 'Agregar empleado' : 'Editar empleado',
        ),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _nameCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _roleCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Puesto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _salaryCtrl,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Salario base quincenal',
                  helperText: 'Se aplica a la quincena abierta',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cuotaCtrl,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cuota mínima (meta quincenal)',
                  helperText: 'Meta de ventas quincenal del empleado',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _seguroLeyCtrl,
                enabled: !_isSubmitting && _editingSeguroLey,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Seguro de ley (monto)',
                  suffixIcon: widget.employee == null
                      ? null
                      : IconButton(
                          tooltip: _editingSeguroLey
                              ? 'Editando seguro de ley'
                              : 'Editar seguro de ley',
                          onPressed: _isSubmitting || _editingSeguroLey
                              ? null
                              : () => setState(() => _editingSeguroLey = true),
                          icon: Icon(
                            _editingSeguroLey
                                ? Icons.lock_open_outlined
                                : Icons.edit_outlined,
                          ),
                        ),
                  helperText: 'Deducción fija por quincena',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _PayrollUserPickerDialog extends ConsumerStatefulWidget {
  const _PayrollUserPickerDialog({required this.excludedUserIds});

  final Set<String> excludedUserIds;

  @override
  ConsumerState<_PayrollUserPickerDialog> createState() =>
      _PayrollUserPickerDialogState();
}

class _PayrollUserPickerDialogState
    extends ConsumerState<_PayrollUserPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<UserModel> _users = const [];
  UserModel? _selected;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ref.read(usersRepositoryProvider).fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'No se pudieron cargar usuarios: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final visible = _users.where((user) {
      if (widget.excludedUserIds.contains(user.id)) return false;
      if (query.isEmpty) return true;
      return user.nombreCompleto.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.telefono.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('Seleccionar usuario'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) {
                if (!mounted) return;
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'Buscar usuario...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              height: 300,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? const Center(child: Text('No hay usuarios para mostrar'))
                  : RadioGroup<String>(
                      groupValue: _selected?.id,
                      onChanged: (value) {
                        if (!mounted) return;
                        if (value == null) return;
                        UserModel? next;
                        for (final u in visible) {
                          if (u.id == value) {
                            next = u;
                            break;
                          }
                        }
                        if (next == null) return;
                        setState(() => _selected = next);
                      },
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = visible[index];
                          return RadioListTile<String>(
                            value: user.id,
                            dense: true,
                            title: Text(
                              user.nombreCompleto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              user.telefono.isEmpty
                                  ? user.email
                                  : '${user.telefono} · ${user.email}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Seleccionar'),
        ),
      ],
    );
  }
}

class _EmployeeCard extends ConsumerStatefulWidget {
  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onManage,
    required this.onDelete,
    this.showDetail = false,
  });

  final PayrollEmployee employee;
  final VoidCallback onEdit;
  final VoidCallback onManage;
  final VoidCallback onDelete;

  /// When true, shows the expandable detail & movements buttons (desktop only).
  final bool showDetail;

  @override
  ConsumerState<_EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends ConsumerState<_EmployeeCard>
    with TickerProviderStateMixin {
  // ── Info panel ──────────────────────────────────────────────────────────
  bool _expandedInfo = false;
  late final AnimationController _infoCtrl;
  late final Animation<double> _infoAnim;

  // ── Movements panel ─────────────────────────────────────────────────────
  bool _expandedMovements = false;
  late final AnimationController _movCtrl;
  late final Animation<double> _movAnim;

  // Lazy loaded data
  List<PayrollEntry>? _entries;
  PayrollTotals? _totals;
  bool _movLoading = false;
  String? _movError;

  @override
  void initState() {
    super.initState();
    _infoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _infoAnim = CurvedAnimation(parent: _infoCtrl, curve: Curves.easeInOut);

    _movCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _movAnim = CurvedAnimation(parent: _movCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _infoCtrl.dispose();
    _movCtrl.dispose();
    super.dispose();
  }

  void _toggleInfo() {
    setState(() => _expandedInfo = !_expandedInfo);
    _expandedInfo ? _infoCtrl.forward() : _infoCtrl.reverse();
  }

  Future<void> _toggleMovements() async {
    setState(() => _expandedMovements = !_expandedMovements);
    if (_expandedMovements) {
      _movCtrl.forward();
      if (_entries == null) {
        await _loadMovements();
      }
    } else {
      _movCtrl.reverse();
    }
  }

  Future<void> _loadMovements() async {
    final open = ref.read(nominaHomeControllerProvider).openPeriod;
    if (open == null) {
      setState(() {
        _movError = 'Sin quincena abierta';
        _movLoading = false;
      });
      return;
    }

    setState(() {
      _movLoading = true;
      _movError = null;
    });

    try {
      final repo = ref.read(nominaRepositoryProvider);
      final entries = await repo.listEntries(open.id, widget.employee.id);
      final totals = await repo.computeTotals(open.id, widget.employee.id);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _totals = totals;
        _movLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _movError = 'No se pudieron cargar: $e';
        _movLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final employee = widget.employee;
    final anyExpanded = _expandedInfo || _expandedMovements;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: anyExpanded
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.55),
          width: anyExpanded ? 1.0 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    _compactInitials(employee.nombre),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${employee.puesto ?? 'Sin puesto'} · Base ${money.format(employee.salarioBaseQuincenal)} · Cuota ${money.format(employee.cuotaMinima)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // ── Desktop-only expand buttons ───────────────────────
                if (widget.showDetail) ...[
                  // Info toggle
                  Tooltip(
                    message: _expandedInfo ? 'Ocultar datos' : 'Ver datos',
                    child: _ExpandToggleChip(
                      icon: Icons.person_outline_rounded,
                      active: _expandedInfo,
                      onTap: _toggleInfo,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Movements toggle
                  Tooltip(
                    message: _expandedMovements
                        ? 'Ocultar movimientos'
                        : 'Ver movimientos',
                    child: _ExpandToggleChip(
                      icon: Icons.receipt_long_outlined,
                      active: _expandedMovements,
                      onTap: _toggleMovements,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _CompactIconActionButton(
                  tooltip: 'Agregar movimiento',
                  onPressed: widget.onManage,
                  icon: Icons.calculate_outlined,
                  color: scheme.primary,
                ),
                _CompactIconActionButton(
                  tooltip: 'Editar',
                  onPressed: widget.onEdit,
                  icon: Icons.edit_outlined,
                  color: scheme.primary,
                ),
                _CompactIconActionButton(
                  tooltip: 'Eliminar',
                  onPressed: widget.onDelete,
                  icon: Icons.delete_outline,
                  color: scheme.error.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),

          // ── Info panel ─────────────────────────────────────────────────
          if (widget.showDetail)
            SizeTransition(
              sizeFactor: _infoAnim,
              axisAlignment: -1,
              child: _EmployeeInfoPanel(employee: employee, money: money),
            ),

          // ── Movements panel ────────────────────────────────────────────
          if (widget.showDetail)
            SizeTransition(
              sizeFactor: _movAnim,
              axisAlignment: -1,
              child: _EmployeeMovementsPanel(
                loading: _movLoading,
                error: _movError,
                entries: _entries,
                totals: _totals,
                money: money,
                onReload: _loadMovements,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Small chip-style toggle button ──────────────────────────────────────────
class _ExpandToggleChip extends StatelessWidget {
  const _ExpandToggleChip({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: active ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── Employee static info panel ───────────────────────────────────────────────
class _EmployeeInfoPanel extends StatelessWidget {
  const _EmployeeInfoPanel({required this.employee, required this.money});

  final PayrollEmployee employee;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DATOS DEL EMPLEADO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              _EmployeeDetailRow(
                icon: Icons.badge_outlined,
                label: 'Puesto',
                value: employee.puesto?.isNotEmpty == true
                    ? employee.puesto!
                    : 'Sin puesto',
              ),
              _EmployeeDetailRow(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: employee.telefono?.isNotEmpty == true
                    ? employee.telefono!
                    : 'Sin teléfono',
              ),
              _EmployeeDetailRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Salario base quincenal',
                value: money.format(employee.salarioBaseQuincenal),
                highlight: true,
              ),
              _EmployeeDetailRow(
                icon: Icons.flag_outlined,
                label: 'Cuota mínima (meta)',
                value: money.format(employee.cuotaMinima),
              ),
              _EmployeeDetailRow(
                icon: Icons.health_and_safety_outlined,
                label: 'Seguro de ley',
                value: money.format(employee.seguroLeyMonto),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Payroll movements/entries panel ─────────────────────────────────────────
class _EmployeeMovementsPanel extends StatelessWidget {
  const _EmployeeMovementsPanel({
    required this.loading,
    required this.error,
    required this.entries,
    required this.totals,
    required this.money,
    required this.onReload,
  });

  final bool loading;
  final String? error;
  final List<PayrollEntry>? entries;
  final PayrollTotals? totals;
  final NumberFormat money;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'MOVIMIENTOS — QUINCENA ACTUAL',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (!loading)
                    GestureDetector(
                      onTap: onReload,
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Totals summary row
              if (totals != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      _MovTotalChip(
                        label: 'Base',
                        value: money.format(totals!.baseSalary),
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      _MovTotalChip(
                        label: 'Comisión',
                        value: money.format(totals!.commissions),
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      _MovTotalChip(
                        label: 'Deducciones',
                        value: money.format(totals!.deductions.abs()),
                        color: scheme.error,
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Neto',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            money.format(totals!.total),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: totals!.total < 0
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Entries list
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                )
              else if (entries == null || entries!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Sin movimientos registrados en la quincena actual.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...entries!.map(
                  (entry) => _EntryRow(entry: entry, money: money),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovTotalChip extends StatelessWidget {
  const _MovTotalChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.money});

  final PayrollEntry entry;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDeduction = entry.amount < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDeduction
                  ? scheme.error.withValues(alpha: 0.85)
                  : scheme.primary.withValues(alpha: 0.85),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.type.label}: ${entry.concept}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yyyy').format(entry.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money.format(entry.amount),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDeduction ? scheme.error : scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeDetailRow extends StatelessWidget {
  const _EmployeeDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: highlight ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _NominaPremiumHeroCard extends StatelessWidget {
  const _NominaPremiumHeroCard({
    required this.title,
    required this.range,
    required this.totalLabel,
    required this.activeEmployees,
    required this.onHistory,
    required this.onTotals,
    required this.onPdf,
    required this.onSendAllPayroll,
    required this.onAddEmployee,
    this.onCreatePeriod,
    this.onClosePeriod,
    this.compact = false,
  });

  final String title;
  final String range;
  final String totalLabel;
  final int activeEmployees;
  final VoidCallback? onHistory;
  final VoidCallback? onTotals;
  final VoidCallback? onPdf;
  final VoidCallback? onSendAllPayroll;
  final VoidCallback onAddEmployee;
  final VoidCallback? onCreatePeriod;
  final VoidCallback? onClosePeriod;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FDFF), Color(0xFFE4F3F7)],
        ),
        border: Border.all(color: const Color(0xFFB7D7E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12061523),
            blurRadius: 16,
            offset: Offset(0, 8),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF0D3141),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      range,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF4D6773),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _NominaTopBadge(icon: Icons.payments_outlined, label: totalLabel),
              const SizedBox(width: 8),
              _NominaTopBadge(
                icon: Icons.groups_2_outlined,
                label: '$activeEmployees',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NominaHeroActionButton(
                label: 'Agregar usuario',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: onAddEmployee,
                solid: true,
                iconOnly: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _NominaHeroActionButton(
                        label: 'Historial',
                        icon: Icons.history,
                        onPressed: onHistory,
                      ),
                      _NominaHeroActionButton(
                        label: 'Totales',
                        icon: Icons.summarize_outlined,
                        onPressed: onTotals,
                      ),
                      _NominaHeroActionButton(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        onPressed: onPdf,
                      ),
                      _NominaHeroActionButton(
                        label: 'Enviar a todos',
                        icon: Icons.mark_chat_unread_outlined,
                        onPressed: onSendAllPayroll,
                      ),
                      if (onClosePeriod != null)
                        _NominaHeroActionButton(
                          label: 'Cerrar',
                          icon: Icons.task_alt_outlined,
                          onPressed: onClosePeriod,
                        ),
                      if (onCreatePeriod != null)
                        _NominaHeroActionButton(
                          label: 'Abrir',
                          icon: Icons.add_circle_outline,
                          onPressed: onCreatePeriod,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NominaTopBadge extends StatelessWidget {
  const _NominaTopBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD3E5EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF0E708E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF123747),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NominaHeroActionButton extends StatelessWidget {
  const _NominaHeroActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.solid = false,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool solid;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final basePadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9);
    final style = solid
        ? FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F6F8B),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: basePadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF164354),
            side: const BorderSide(color: Color(0xFFC7DDE5)),
            padding: basePadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );

    final child = iconOnly
        ? Tooltip(
            message: label,
            child: solid
                ? FilledButton(
                    onPressed: onPressed,
                    style: style,
                    child: Icon(icon, size: 18),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: style,
                    child: Icon(icon, size: 18),
                  ),
          )
        : solid
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: style,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: style,
          );

    return Padding(padding: const EdgeInsets.only(right: 8), child: child);
  }
}

class _NominaPrimaryBoard extends StatelessWidget {
  const _NominaPrimaryBoard({
    required this.openPeriod,
    required this.totalAbierto,
    required this.payrollBase,
    required this.payrollQuota,
    required this.activeEmployees,
    required this.money,
    this.compact = false,
  });

  final PayrollPeriod? openPeriod;
  final double totalAbierto;
  final double payrollBase;
  final double payrollQuota;
  final int activeEmployees;
  final NumberFormat money;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.68),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10061523),
            blurRadius: 18,
            offset: Offset(0, 10),
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
                      'Detalle de la quincena en curso',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      openPeriod == null
                          ? 'Sin periodo abierto'
                          : openPeriod!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: openPeriod == null
                      ? scheme.surfaceContainerHigh
                      : scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  openPeriod == null ? 'Sin apertura' : 'Abierta',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: openPeriod == null
                        ? scheme.onSurfaceVariant
                        : scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NominaMiniStatTile(
                label: 'Total',
                value: money.format(totalAbierto),
                icon: Icons.account_balance_wallet_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Base',
                value: money.format(payrollBase),
                icon: Icons.badge_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Cuota',
                value: money.format(payrollQuota),
                icon: Icons.flag_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Activos',
                value: activeEmployees.toString(),
                icon: Icons.groups_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NominaMiniStatTile extends StatelessWidget {
  const _NominaMiniStatTile({
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 164, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
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

class _NominaUsersSectionCard extends StatelessWidget {
  const _NominaUsersSectionCard({
    required this.expanded,
    required this.employees,
    required this.onToggle,
    required this.onAdd,
    required this.child,
  });

  final bool expanded;
  final List<PayrollEmployee> employees;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.68),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10061523),
            blurRadius: 18,
            offset: Offset(0, 10),
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
                      'Usuarios en nomina',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${employees.length} registrados',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _CompactIconActionButton(
                tooltip: expanded ? 'Ocultar' : 'Mostrar',
                onPressed: onToggle,
                icon: expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: scheme.primary,
              ),
              _CompactIconActionButton(
                tooltip: 'Agregar usuario',
                onPressed: onAdd,
                icon: Icons.person_add_alt_1_outlined,
                color: scheme.primary,
              ),
            ],
          ),
          if (expanded) ...[const SizedBox(height: 10), child],
        ],
      ),
    );
  }
}

class _NominaErrorBanner extends StatelessWidget {
  const _NominaErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PayrollHistoryPeriodSummary {
  const _PayrollHistoryPeriodSummary({
    required this.period,
    required this.total,
  });

  final PayrollPeriod period;
  final double total;
}

enum _PayrollHistoryQuickFilter {
  all('Todo'),
  last90Days('90 dias'),
  currentYear('Este ano');

  const _PayrollHistoryQuickFilter(this.label);
  final String label;
}

enum _PayrollDetailEmployeeFilter {
  all('Todos'),
  withCommission('Con comision'),
  withDeductions('Con deducciones');

  const _PayrollDetailEmployeeFilter(this.label);
  final String label;
}

class _PayrollHistoryFullScreen extends ConsumerStatefulWidget {
  const _PayrollHistoryFullScreen({
    required this.items,
    required this.onOpenDetails,
    required this.onEditPayroll,
    required this.onSendPayroll,
    required this.onSchedulePayroll,
    required this.onPreviewPayroll,
  });

  final List<_PayrollHistoryPeriodSummary> items;
  final Future<void> Function(PayrollPeriod period) onOpenDetails;
  final Future<void> Function(
    BuildContext context,
    PayrollPeriod period,
    _PayrollPeriodRow row,
  )
  onEditPayroll;
  final Future<void> Function(
    BuildContext context,
    PayrollPeriod period,
    _PayrollPeriodRow row,
  )
  onSendPayroll;
  final Future<void> Function(
    BuildContext context,
    PayrollPeriod period,
    _PayrollPeriodRow row,
  )
  onSchedulePayroll;
  final Future<void> Function(
    BuildContext context,
    PayrollPeriod period,
    _PayrollPeriodRow row,
  )
  onPreviewPayroll;

  @override
  ConsumerState<_PayrollHistoryFullScreen> createState() =>
      _PayrollHistoryFullScreenState();
}

class _PayrollHistoryFullScreenState
    extends ConsumerState<_PayrollHistoryFullScreen> {
  // ── List filters ────────────────────────────────────────────────────────
  late final TextEditingController _searchController;
  DateTime? _from;
  DateTime? _to;
  _PayrollHistoryQuickFilter _quickFilter = _PayrollHistoryQuickFilter.all;

  // ── Desktop inline detail ────────────────────────────────────────────────
  _PayrollHistoryPeriodSummary? _selectedItem;
  Object? _detailRows;
  bool _detailLoading = false;
  String? _detailError;
  late final TextEditingController _detailSearchCtrl;
  _PayrollDetailEmployeeFilter _detailFilter = _PayrollDetailEmployeeFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
    _detailSearchCtrl = TextEditingController();
    _detailSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _detailSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? now.subtract(const Duration(days: 180)))
        : (_to ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && picked.isBefore(_from!)) _from = picked;
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _from = null;
      _to = null;
      _quickFilter = _PayrollHistoryQuickFilter.all;
    });
  }

  List<_PayrollHistoryPeriodSummary> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return widget.items
        .where((item) {
          if (query.isNotEmpty &&
              !item.period.title.toLowerCase().contains(query)) {
            return false;
          }
          if (_quickFilter == _PayrollHistoryQuickFilter.last90Days) {
            final pivot = now.subtract(const Duration(days: 90));
            if (item.period.endDate.isBefore(pivot)) return false;
          }
          if (_quickFilter == _PayrollHistoryQuickFilter.currentYear &&
              item.period.endDate.year != now.year) {
            return false;
          }
          if (_from != null) {
            final from = DateTime(_from!.year, _from!.month, _from!.day);
            if (item.period.endDate.isBefore(from)) return false;
          }
          if (_to != null) {
            final to = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59);
            if (item.period.startDate.isAfter(to)) return false;
          }
          return true;
        })
        .toList(growable: false)
      ..sort((a, b) => b.period.endDate.compareTo(a.period.endDate));
  }

  Future<void> _selectPeriod(_PayrollHistoryPeriodSummary item) async {
    setState(() {
      _selectedItem = item;
      _detailRows = null;
      _detailLoading = true;
      _detailError = null;
      _detailSearchCtrl.clear();
      _detailFilter = _PayrollDetailEmployeeFilter.all;
    });
    try {
      final repo = ref.read(nominaRepositoryProvider);
      final employees = [...ref.read(nominaHomeControllerProvider).employees]
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      final statuses = await repo.listPaymentStatuses(periodId: item.period.id);
      final statusesByEmployee = {
        for (final status in statuses) status.employeeId: status,
      };
      final rows = <_PayrollPeriodRow>[];
      for (final employee in employees) {
        final totals = await repo.computeTotals(item.period.id, employee.id);
        rows.add((
          employee: employee,
          totals: totals,
          paymentStatus:
              statusesByEmployee[employee.id] ??
              PayrollPaymentRecord.draft(
                periodId: item.period.id,
                employeeId: employee.id,
              ),
        ));
      }
      if (!mounted) return;
      setState(() {
        _detailRows = rows;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailError = 'Error al cargar: $e';
        _detailLoading = false;
      });
    }
  }

  List<_PayrollPeriodRow> get _safeDetailRows {
    final rawRows = _detailRows;
    if (rawRows is! List) return const [];

    return rawRows
        .map<_PayrollPeriodRow?>((row) {
          try {
            final dynamic item = row;
            final PayrollEmployee employee = item.employee as PayrollEmployee;
            final PayrollTotals totals = item.totals as PayrollTotals;
            final dynamic rawPaymentStatus = item.paymentStatus;
            final paymentStatus = rawPaymentStatus is PayrollPaymentRecord
                ? rawPaymentStatus
                : PayrollPaymentRecord.draft(
                    periodId: _selectedItem?.period.id ?? '',
                    employeeId: employee.id,
                  );
            return (
              employee: employee,
              totals: totals,
              paymentStatus: paymentStatus,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<_PayrollPeriodRow>()
        .toList(growable: false);
  }

  List<_PayrollPeriodRow> get _filteredDetailRows {
    final rows = _safeDetailRows;
    final query = _detailSearchCtrl.text.trim().toLowerCase();
    return rows
        .where((row) {
          if (query.isNotEmpty &&
              !row.employee.nombre.toLowerCase().contains(query)) {
            return false;
          }
          switch (_detailFilter) {
            case _PayrollDetailEmployeeFilter.withCommission:
              return row.totals.commissions > 0 ||
                  row.totals.serviceCommissions > 0;
            case _PayrollDetailEmployeeFilter.withDeductions:
              return row.totals.deductions > 0;
            case _PayrollDetailEmployeeFilter.all:
              return true;
          }
        })
        .toList(growable: false)
      ..sort((a, b) => b.totals.total.compareTo(a.totals.total));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    return isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  // ── DESKTOP layout ───────────────────────────────────────────────────────
  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = _filteredItems;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final visibleTotal = filtered.fold<double>(0, (s, i) => s + i.total);
    final activeFilters = [
      if (_searchController.text.trim().isNotEmpty) 1,
      if (_from != null) 1,
      if (_to != null) 1,
      if (_quickFilter != _PayrollHistoryQuickFilter.all) 1,
    ].length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: const Text('Historial de nóminas'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (activeFilters > 0)
            TextButton(
              onPressed: _resetFilters,
              child: const Text(
                'Limpiar filtros',
                style: TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── LEFT: period list ──────────────────────────────────────────
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary header
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quincenas cerradas',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${filtered.length} resultados · ${money.format(visibleTotal)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Search
                      TextField(
                        controller: _searchController,
                        style: theme.textTheme.bodySmall,
                        decoration: InputDecoration(
                          hintText: 'Buscar quincena...',
                          hintStyle: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 16,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          filled: true,
                          fillColor: scheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Quick filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _PayrollHistoryQuickFilter.values
                              .map(
                                (f) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _PayrollFilterChip(
                                    label: f.label,
                                    selected: _quickFilter == f,
                                    onTap: () =>
                                        setState(() => _quickFilter = f),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Date pickers
                      Row(
                        children: [
                          Expanded(
                            child: _HistoryDateButton(
                              label: 'Desde',
                              value: _from == null
                                  ? '—'
                                  : DateFormat('dd/MM/yy').format(_from!),
                              onTap: () => _pickDate(isFrom: true),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _HistoryDateButton(
                              label: 'Hasta',
                              value: _to == null
                                  ? '—'
                                  : DateFormat('dd/MM/yy').format(_to!),
                              onTap: () => _pickDate(isFrom: false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Period list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Sin resultados',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: scheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final isSelected =
                                _selectedItem?.period.id == item.period.id;
                            return _HistoryPeriodListTile(
                              item: item,
                              money: money,
                              selected: isSelected,
                              onTap: () => _selectPeriod(item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── RIGHT: inline detail ─────────────────────────────────────
          Expanded(
            child: _selectedItem == null
                ? _HistoryEmptyDetail()
                : _HistoryInlineDetail(
                    item: _selectedItem!,
                    rows: _safeDetailRows,
                    loading: _detailLoading,
                    error: _detailError,
                    searchCtrl: _detailSearchCtrl,
                    filter: _detailFilter,
                    filteredRows: _filteredDetailRows,
                    money: money,
                    onFilterChange: (f) => setState(() => _detailFilter = f),
                    onSendPayroll: (row) async {
                      await widget.onSendPayroll(
                        context,
                        _selectedItem!.period,
                        row,
                      );
                    },
                    onSchedulePayroll: (row) async {
                      await widget.onSchedulePayroll(
                        context,
                        _selectedItem!.period,
                        row,
                      );
                    },
                    onPreviewPayroll: (row) async {
                      await widget.onPreviewPayroll(
                        context,
                        _selectedItem!.period,
                        row,
                      );
                    },
                    onEditPayroll: (row) async {
                      await widget.onEditPayroll(
                        context,
                        _selectedItem!.period,
                        row,
                      );
                      await _selectPeriod(_selectedItem!);
                    },
                    onMarkPaid: (row) async {
                      await ref
                          .read(nominaRepositoryProvider)
                          .markPayrollPaid(
                            periodId: _selectedItem!.period.id,
                            employeeId: row.employee.id,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Nomina de ${row.employee.nombre} marcada como pagada',
                          ),
                        ),
                      );
                      await _selectPeriod(_selectedItem!);
                    },
                    onExportPdf: () async {
                      await widget.onOpenDetails(_selectedItem!.period);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── MOBILE layout (unchanged behavior) ──────────────────────────────────
  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = _filteredItems;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final visibleTotal = filtered.fold<double>(0, (s, i) => s + i.total);
    final latestClose = filtered.isEmpty
        ? null
        : DateFormat('dd/MM/yyyy').format(filtered.first.period.endDate);
    final activeFilters = [
      if (_searchController.text.trim().isNotEmpty) 1,
      if (_from != null) 1,
      if (_to != null) 1,
      if (_quickFilter != _PayrollHistoryQuickFilter.all) 1,
    ].length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de nominas'),
        actions: [
          if (activeFilters > 0)
            TextButton(onPressed: _resetFilters, child: const Text('Limpiar')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _PayrollSurface(
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
                              'Quincenas cerradas',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              filtered.isEmpty
                                  ? 'No hay quincenas visibles con los filtros actuales.'
                                  : '${filtered.length} resultados visibles.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (activeFilters > 0)
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    children: [
                      _PayrollHeaderMetric(
                        icon: Icons.receipt_long_outlined,
                        label: 'Quincenas',
                        value: '${filtered.length}',
                      ),
                      _PayrollHeaderMetric(
                        icon: Icons.payments_outlined,
                        label: 'Total visible',
                        value: money.format(visibleTotal),
                      ),
                      _PayrollHeaderMetric(
                        icon: Icons.event_available_outlined,
                        label: 'Ultimo cierre',
                        value: latestClose ?? 'Sin datos',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por titulo de quincena',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _PayrollHistoryQuickFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _PayrollFilterChip(
                                label: filter.label,
                                selected: _quickFilter == filter,
                                onTap: () =>
                                    setState(() => _quickFilter = filter),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PayrollFilterButton(
                          label: 'Desde',
                          value: _from == null
                              ? 'Seleccionar fecha'
                              : DateFormat('dd/MM/yyyy').format(_from!),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PayrollFilterButton(
                          label: 'Hasta',
                          value: _to == null
                              ? 'Seleccionar fecha'
                              : DateFormat('dd/MM/yyyy').format(_to!),
                          icon: Icons.event_available_outlined,
                          onTap: () => _pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _NominaEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No hay quincenas con estos filtros',
                        message:
                            'Ajusta la busqueda o el rango de fechas para ver resultados.',
                        actionLabel: 'Limpiar filtros',
                        onAction: _resetFilters,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _PayrollHistoryPeriodCard(
                        item: item,
                        onTap: () => widget.onOpenDetails(item.period),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Desktop helper widgets ────────────────────────────────────────────────────

class _HistoryDateButton extends StatelessWidget {
  const _HistoryDateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 12,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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

class _HistoryPeriodListTile extends StatelessWidget {
  const _HistoryPeriodListTile({
    required this.item,
    required this.money,
    required this.selected,
    required this.onTap,
  });
  final _PayrollHistoryPeriodSummary item;
  final NumberFormat money;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.period.startDate)} – '
        '${DateFormat('dd/MM/yyyy').format(item.period.endDate)}';

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: selected
            ? scheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            if (selected)
              Container(
                width: 3,
                height: 36,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.period.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    range,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money.format(item.total),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEmptyDetail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 40,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Selecciona una quincena',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El detalle y los pagos aparecerán aquí.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryInlineDetail extends StatelessWidget {
  const _HistoryInlineDetail({
    required this.item,
    required this.rows,
    required this.loading,
    required this.error,
    required this.searchCtrl,
    required this.filter,
    required this.filteredRows,
    required this.money,
    required this.onFilterChange,
    required this.onSendPayroll,
    required this.onSchedulePayroll,
    required this.onPreviewPayroll,
    required this.onEditPayroll,
    required this.onMarkPaid,
    required this.onExportPdf,
  });

  final _PayrollHistoryPeriodSummary item;
  final List<_PayrollPeriodRow>? rows;
  final bool loading;
  final String? error;
  final TextEditingController searchCtrl;
  final _PayrollDetailEmployeeFilter filter;
  final List<_PayrollPeriodRow> filteredRows;
  final NumberFormat money;
  final void Function(_PayrollDetailEmployeeFilter) onFilterChange;
  final Future<void> Function(_PayrollPeriodRow) onSendPayroll;
  final Future<void> Function(_PayrollPeriodRow) onSchedulePayroll;
  final Future<void> Function(_PayrollPeriodRow) onPreviewPayroll;
  final Future<void> Function(_PayrollPeriodRow) onEditPayroll;
  final Future<void> Function(_PayrollPeriodRow) onMarkPaid;
  final Future<void> Function() onExportPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.period.startDate)} – '
        '${DateFormat('dd/MM/yyyy').format(item.period.endDate)}';

    final totalBase = filteredRows.fold<double>(
      0,
      (s, r) => s + r.totals.baseSalary,
    );
    final totalCommissions = filteredRows.fold<double>(
      0,
      (s, r) => s + r.totals.commissions + r.totals.serviceCommissions,
    );
    final totalExtras = filteredRows.fold<double>(
      0,
      (s, r) => s + r.totals.bonuses + r.totals.otherAdditions,
    );
    final totalDeductions = filteredRows.fold<double>(
      0,
      (s, r) => s + r.totals.deductions,
    );
    final totalNeto = filteredRows.fold<double>(
      0,
      (s, r) => s + r.totals.total,
    );
    final allRows = rows ?? const <_PayrollPeriodRow>[];
    final paidCount = allRows.where((row) => row.paymentStatus.isPaid).length;
    final allPaid = allRows.isNotEmpty && paidCount == allRows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Detail header bar ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
          color: scheme.surface,
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
                          item.period.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          range,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (allPaid) ...[
                    const SizedBox(width: 10),
                    const _PayrollPaidBadge(
                      label: 'Nomina de quincena pagada',
                      dense: true,
                    ),
                  ] else if (paidCount > 0) ...[
                    const SizedBox(width: 10),
                    _PayrollPaidBadge(
                      label: '$paidCount/${allRows.length} pagadas',
                      dense: true,
                    ),
                  ],
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onExportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
              // Totals summary strip
              if (rows != null && !loading) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _HistoryStatChip(
                        label: 'Total neto',
                        value: money.format(totalNeto),
                        primary: true,
                      ),
                      const SizedBox(width: 6),
                      _HistoryStatChip(
                        label: 'Base',
                        value: money.format(totalBase),
                      ),
                      const SizedBox(width: 6),
                      _HistoryStatChip(
                        label: 'Comisión',
                        value: money.format(totalCommissions),
                      ),
                      const SizedBox(width: 6),
                      _HistoryStatChip(
                        label: 'Extras',
                        value: money.format(totalExtras),
                      ),
                      const SizedBox(width: 6),
                      _HistoryStatChip(
                        label: 'Deducciones',
                        value: money.format(totalDeductions),
                        danger: true,
                      ),
                      const SizedBox(width: 6),
                      _HistoryStatChip(
                        label: 'Pagadas',
                        value: '$paidCount/${allRows.length}',
                        primary: allPaid,
                      ),
                    ],
                  ),
                ),
              ],
              // Search + filters
              if (rows != null && !loading) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        style: theme.textTheme.bodySmall,
                        decoration: InputDecoration(
                          hintText: 'Buscar empleado...',
                          hintStyle: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 15,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          filled: true,
                          fillColor: scheme.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...(_PayrollDetailEmployeeFilter.values.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _PayrollFilterChip(
                          label: f.label,
                          selected: filter == f,
                          onTap: () => onFilterChange(f),
                        ),
                      ),
                    )),
                  ],
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),

        // ── Employee rows ─────────────────────────────────────────────
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Text(error!, style: TextStyle(color: scheme.error)),
                )
              : filteredRows.isEmpty
              ? Center(
                  child: Text(
                    'Sin empleados con este filtro.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: filteredRows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = filteredRows[index];
                    return _PayrollPeriodEmployeeCard(
                      row: row,
                      money: money,
                      onSendPayroll: () => onSendPayroll(row),
                      onSchedulePayroll: () => onSchedulePayroll(row),
                      onPreviewPayroll: () => onPreviewPayroll(row),
                      onEditPayroll: () => onEditPayroll(row),
                      onMarkPaid: row.paymentStatus.isPaid
                          ? null
                          : () => onMarkPaid(row),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryStatChip extends StatelessWidget {
  const _HistoryStatChip({
    required this.label,
    required this.value,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = primary
        ? scheme.primary
        : danger
        ? scheme.error
        : scheme.onSurface;
    final bg = primary
        ? scheme.primary.withValues(alpha: 0.08)
        : danger
        ? scheme.error.withValues(alpha: 0.06)
        : scheme.surfaceContainerLowest;
    final border = primary
        ? scheme.primary.withValues(alpha: 0.25)
        : danger
        ? scheme.error.withValues(alpha: 0.2)
        : scheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPeriodDetailsScreen extends StatefulWidget {
  const _PayrollPeriodDetailsScreen({
    required this.period,
    required this.rows,
    required this.totalPagar,
    required this.onOpenPdf,
    required this.onSendPayroll,
    required this.onSchedulePayroll,
    required this.onPreviewPayroll,
    required this.onEditPayroll,
    required this.onMarkPaid,
    required this.onReloadRows,
    required this.money,
  });

  final PayrollPeriod period;
  final List<_PayrollPeriodRow> rows;
  final double totalPagar;
  final Future<void> Function() onOpenPdf;
  final Future<void> Function(_PayrollPeriodRow row) onSendPayroll;
  final Future<void> Function(_PayrollPeriodRow row) onSchedulePayroll;
  final Future<void> Function(_PayrollPeriodRow row) onPreviewPayroll;
  final Future<void> Function(_PayrollPeriodRow row) onEditPayroll;
  final Future<PayrollPaymentRecord?> Function(_PayrollPeriodRow row)
  onMarkPaid;
  final Future<List<_PayrollPeriodRow>> Function() onReloadRows;
  final NumberFormat money;

  @override
  State<_PayrollPeriodDetailsScreen> createState() =>
      _PayrollPeriodDetailsScreenState();
}

class _PayrollPeriodDetailsScreenState
    extends State<_PayrollPeriodDetailsScreen> {
  late final TextEditingController _searchController;
  late List<_PayrollPeriodRow> _rows;
  _PayrollDetailEmployeeFilter _filter = _PayrollDetailEmployeeFilter.all;
  bool _refreshingRows = false;

  @override
  void initState() {
    super.initState();
    _rows = [...widget.rows];
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reloadRows() async {
    if (_refreshingRows) return;
    setState(() => _refreshingRows = true);
    try {
      final rows = await widget.onReloadRows();
      if (!mounted) return;
      setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _refreshingRows = false);
    }
  }

  List<_PayrollPeriodRow> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    return _rows
        .where((row) {
          if (query.isNotEmpty &&
              !row.employee.nombre.toLowerCase().contains(query)) {
            return false;
          }
          switch (_filter) {
            case _PayrollDetailEmployeeFilter.withCommission:
              return row.totals.commissions > 0 ||
                  row.totals.serviceCommissions > 0;
            case _PayrollDetailEmployeeFilter.withDeductions:
              return row.totals.deductions > 0;
            case _PayrollDetailEmployeeFilter.all:
              return true;
          }
        })
        .toList(growable: false)
      ..sort((a, b) => b.totals.total.compareTo(a.totals.total));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final filtered = _filteredRows;
    final activeFilters = [
      if (_searchController.text.trim().isNotEmpty) 1,
      if (_filter != _PayrollDetailEmployeeFilter.all) 1,
    ].length;
    final totalBase = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = filtered.fold<double>(
      0,
      (sum, row) =>
          sum + row.totals.commissions + row.totals.serviceCommissions,
    );
    final totalDeductions = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalExtras = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalVisible = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );
    final paidCount = _rows.where((row) => row.paymentStatus.isPaid).length;
    final allPaid = _rows.isNotEmpty && paidCount == _rows.length;
    final range =
        '${DateFormat('dd/MM/yyyy').format(widget.period.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.period.endDate)}';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 0,
        title: Text(
          widget.period.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: () => widget.onOpenPdf(),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, isCompact ? 10 : 12, 12, 0),
            child: _PayrollSurface(
              padding: EdgeInsets.all(isCompact ? 10 : 12),
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
                              'Detalle premium de quincena',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              range,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.money.format(
                                _rows.fold<double>(
                                  0,
                                  (sum, row) => sum + row.totals.total,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Total general de la quincena',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _PayrollMiniPill(
                        icon: _refreshingRows
                            ? Icons.sync_outlined
                            : Icons.groups_outlined,
                        label: _refreshingRows
                            ? 'Actualizando'
                            : '${filtered.length} empleados',
                      ),
                    ],
                  ),
                  if (allPaid) ...[
                    const SizedBox(height: 10),
                    const _PayrollPaidBadge(label: 'Nomina de quincena pagada'),
                  ] else if (paidCount > 0) ...[
                    const SizedBox(height: 10),
                    _PayrollPaidBadge(
                      label: '$paidCount/${_rows.length} nominas pagadas',
                    ),
                  ],
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _PayrollInlineMetric(
                          label: 'Base',
                          value: widget.money.format(totalBase),
                        ),
                        _PayrollInlineMetric(
                          label: 'Comision',
                          value: widget.money.format(totalCommissions),
                        ),
                        _PayrollInlineMetric(
                          label: 'Extras',
                          value: widget.money.format(totalExtras),
                        ),
                        _PayrollInlineMetric(
                          label: 'Deducciones',
                          value: widget.money.format(totalDeductions),
                        ),
                        _PayrollInlineMetric(
                          label: 'Neto visible',
                          value: widget.money.format(totalVisible),
                        ),
                        _PayrollInlineMetric(
                          label: 'Pagadas',
                          value: '$paidCount/${_rows.length}',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: isCompact ? 10 : 12,
                    ),
                    child: Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filtros del detalle',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (activeFilters > 0)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _filter = _PayrollDetailEmployeeFilter.all;
                          }),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Mostrar todo'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre del empleado',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: scheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _PayrollDetailEmployeeFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _PayrollFilterChip(
                                label: filter.label,
                                selected: _filter == filter,
                                onTap: () => setState(() => _filter = filter),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _NominaEmptyState(
                        icon: Icons.people_outline,
                        title: 'No hay empleados con este filtro',
                        message:
                            'Prueba con otro criterio para ver el detalle de la quincena.',
                        actionLabel: 'Mostrar todo',
                        onAction: () => setState(() {
                          _searchController.clear();
                          _filter = _PayrollDetailEmployeeFilter.all;
                        }),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(12, isCompact ? 6 : 8, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = filtered[index];
                      return _PayrollPeriodEmployeeCard(
                        row: row,
                        money: widget.money,
                        onSendPayroll: () => widget.onSendPayroll(row),
                        onSchedulePayroll: () => widget.onSchedulePayroll(row),
                        onPreviewPayroll: () => widget.onPreviewPayroll(row),
                        onEditPayroll: () async {
                          await widget.onEditPayroll(row);
                          await _reloadRows();
                        },
                        onMarkPaid: row.paymentStatus.isPaid
                            ? null
                            : () async {
                                await widget.onMarkPaid(row);
                                await _reloadRows();
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PayrollSurface extends StatelessWidget {
  const _PayrollSurface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surface, scheme.surfaceContainerLowest],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PayrollMiniPill extends StatelessWidget {
  const _PayrollMiniPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollInlineMetric extends StatelessWidget {
  const _PayrollInlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollHeaderMetric extends StatelessWidget {
  const _PayrollHeaderMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
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
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
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

class _PayrollAmountBadge extends StatelessWidget {
  const _PayrollAmountBadge({
    required this.label,
    required this.value,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  final String label;
  final String value;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = backgroundColor ?? scheme.surfaceContainerLowest;
    final fg = textColor ?? scheme.onSurface;
    final bd = borderColor ?? scheme.outlineVariant.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPaidBadge extends StatelessWidget {
  const _PayrollPaidBadge({required this.label, this.dense = false});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.surface,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 11,
        vertical: dense ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: dense ? 14 : 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollFilterChip extends StatelessWidget {
  const _PayrollFilterChip({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.primary.withValues(alpha: 0.82),
                  ],
                )
              : null,
          color: selected ? null : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PayrollFilterButton extends StatelessWidget {
  const _PayrollFilterButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollHistoryPeriodCard extends StatelessWidget {
  const _PayrollHistoryPeriodCard({required this.item, required this.onTap});

  final _PayrollHistoryPeriodSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.period.startDate)} - ${DateFormat('dd/MM/yyyy').format(item.period.endDate)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    _compactInitials(item.period.title),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.period.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        range,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PayrollAmountBadge(
                            label: 'Total pagado',
                            value: money.format(item.total),
                            backgroundColor: scheme.primaryContainer,
                            textColor: scheme.onPrimaryContainer,
                            borderColor: scheme.primary.withValues(alpha: 0.18),
                          ),
                          _PayrollAmountBadge(
                            label: 'Estado',
                            value: 'Cerrada',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayrollPeriodEmployeeCard extends StatefulWidget {
  const _PayrollPeriodEmployeeCard({
    required this.row,
    required this.money,
    required this.onSendPayroll,
    required this.onSchedulePayroll,
    required this.onPreviewPayroll,
    required this.onEditPayroll,
    this.onMarkPaid,
  });

  final _PayrollPeriodRow row;
  final NumberFormat money;
  final Future<void> Function() onSendPayroll;
  final Future<void> Function() onSchedulePayroll;
  final Future<void> Function() onPreviewPayroll;
  final Future<void> Function() onEditPayroll;
  final Future<void> Function()? onMarkPaid;

  @override
  State<_PayrollPeriodEmployeeCard> createState() =>
      _PayrollPeriodEmployeeCardState();
}

class _PayrollPeriodEmployeeCardState extends State<_PayrollPeriodEmployeeCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = widget.row.totals;
    final employee = widget.row.employee;
    final isPaid = widget.row.paymentStatus.isPaid;
    final money = widget.money;
    // ignore: unused_local_variable
    final extras =
        totals.bonuses + totals.holidayWorked + totals.otherAdditions;
    final isNegative = totals.total < 0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _expanded
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: _expanded ? 1.0 : 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Compact header row (always visible) ──────────────────────
          InkWell(
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(10))
                : BorderRadius.circular(10),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  // Left accent bar
                  Container(
                    width: 3,
                    height: 32,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? scheme.primary
                          : isNegative
                          ? scheme.error
                          : scheme.primary.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  // Avatar
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: scheme.secondaryContainer,
                    child: Text(
                      _compactInitials(employee.nombre),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          employee.puesto ?? 'Sin puesto',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isPaid) ...[
                    const _PayrollPaidBadge(label: 'Pagada', dense: true),
                    const SizedBox(width: 8),
                  ],
                  // Neto badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isNegative
                          ? scheme.errorContainer
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          money.format(totals.total),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isNegative
                                ? scheme.onErrorContainer
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          'Neto',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isNegative
                                ? scheme.onErrorContainer.withValues(alpha: 0.7)
                                : scheme.onPrimaryContainer.withValues(
                                    alpha: 0.7,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expand arrow
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable detail ─────────────────────────────────────────
          SizeTransition(
            sizeFactor: _anim,
            axisAlignment: -1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── ADICIONES ──────────────────────────────────
                      _BreakdownSection(
                        label: 'ADICIONES',
                        color: scheme.primary,
                        rows: [
                          _BreakdownLine(
                            label: 'Salario base',
                            value: money.format(totals.baseSalary),
                            bold: true,
                          ),
                          if (totals.commissions > 0)
                            _BreakdownLine(
                              label: 'Comisión por ventas',
                              value: money.format(totals.commissions),
                            ),
                          if (totals.serviceCommissions > 0)
                            _BreakdownLine(
                              label: 'Comision por instalaciones',
                              value: money.format(totals.serviceCommissions),
                            ),
                          if (totals.bonuses > 0)
                            _BreakdownLine(
                              label: 'Bonificaciones',
                              value: money.format(totals.bonuses),
                            ),
                          if (totals.otherAdditions > 0)
                            _BreakdownLine(
                              label: 'Otros ingresos',
                              value: money.format(totals.otherAdditions),
                            ),
                          _BreakdownLine(
                            label: 'Total adiciones',
                            value: money.format(totals.additions),
                            bold: true,
                            isTotal: true,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── DEDUCCIONES ────────────────────────────────
                      _BreakdownSection(
                        label: 'DEDUCCIONES',
                        color: scheme.error,
                        rows: [
                          if (totals.seguroLey > 0)
                            _BreakdownLine(
                              label: 'Seguro de ley',
                              value: money.format(totals.seguroLey),
                              danger: true,
                            ),
                          if (totals.absences > 0)
                            _BreakdownLine(
                              label: 'Ausencias',
                              value: money.format(totals.absences),
                              danger: true,
                            ),
                          if (totals.advances > 0)
                            _BreakdownLine(
                              label: 'Adelantos',
                              value: money.format(totals.advances),
                              danger: true,
                            ),
                          if (totals.late > 0)
                            _BreakdownLine(
                              label: 'Tardanzas',
                              value: money.format(totals.late),
                              danger: true,
                            ),
                          if (totals.otherDeductions > 0)
                            _BreakdownLine(
                              label: 'Otros descuentos',
                              value: money.format(totals.otherDeductions),
                              danger: true,
                            ),
                          if (totals.deductions == 0)
                            _BreakdownLine(
                              label: 'Sin deducciones',
                              value: '—',
                              muted: true,
                            )
                          else
                            _BreakdownLine(
                              label: 'Total deducciones',
                              value: money.format(totals.deductions.abs()),
                              bold: true,
                              isTotal: true,
                              danger: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── NETO FINAL ─────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isNegative
                              ? scheme.errorContainer.withValues(alpha: 0.5)
                              : scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isNegative
                                ? scheme.error.withValues(alpha: 0.2)
                                : scheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                isPaid ? 'TOTAL PAGADO' : 'NETO A PAGAR',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: isNegative
                                      ? scheme.error
                                      : scheme.primary,
                                ),
                              ),
                            ),
                            Text(
                              money.format(totals.total),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: isNegative
                                    ? scheme.error
                                    : scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ── Send button ────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'Ver PDF que se enviara',
                            onPressed: widget.onPreviewPayroll,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            tooltip: 'Enviar nomina',
                            onPressed: widget.onSendPayroll,
                            icon: const Icon(Icons.send_to_mobile_outlined),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            tooltip: 'Programar envio',
                            onPressed: widget.onSchedulePayroll,
                            icon: const Icon(Icons.event_available_outlined),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            tooltip: isPaid
                                ? 'Esta nomina fue pagada y no se puede editar'
                                : 'Editar nomina',
                            onPressed: widget.onEditPayroll,
                            icon: Icon(
                              isPaid ? Icons.lock_outline : Icons.edit_outlined,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: isPaid ? 'Nomina pagada' : 'Marcar pagada',
                            onPressed: isPaid ? null : widget.onMarkPaid,
                            icon: Icon(
                              isPaid
                                  ? Icons.verified_outlined
                                  : Icons.payments_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
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

// ── Breakdown helpers ─────────────────────────────────────────────────────────

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({
    required this.label,
    required this.color,
    required this.rows,
  });

  final String label;
  final Color color;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 11,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ...rows,
      ],
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({
    required this.label,
    required this.value,
    this.bold = false,
    this.danger = false,
    this.muted = false,
    this.isTotal = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final bool danger;
  final bool muted;
  final bool isTotal;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelColor = muted
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : danger
        ? scheme.error.withValues(alpha: 0.85)
        : color ?? scheme.onSurfaceVariant;
    final valueColor = muted
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : danger
        ? scheme.error
        : color ?? scheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(bottom: isTotal ? 0 : 3, top: isTotal ? 3 : 0),
      child: Row(
        children: [
          if (isTotal)
            Divider(
              height: 0,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactIconActionButton extends StatelessWidget {
  const _CompactIconActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

String _compactInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (parts.isEmpty) return '--';
  return parts.map((part) => part[0].toUpperCase()).join();
}

class _NominaEmptyState extends StatelessWidget {
  const _NominaEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP-ONLY WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _NominaDesktopSidebar extends StatelessWidget {
  const _NominaDesktopSidebar({
    required this.openPeriod,
    required this.totalAbierto,
    required this.payrollBase,
    required this.payrollQuota,
    required this.activeEmployees,
    required this.money,
    required this.loading,
    required this.sendingToAll,
    required this.onAddEmployee,
    this.onHistory,
    this.onTotals,
    this.onPdf,
    this.onSendAll,
    this.onClosePeriod,
    this.onCreatePeriod,
  });

  final PayrollPeriod? openPeriod;
  final double totalAbierto;
  final double payrollBase;
  final double payrollQuota;
  final int activeEmployees;
  final NumberFormat money;
  final bool loading;
  final bool sendingToAll;
  final VoidCallback onAddEmployee;
  final VoidCallback? onHistory;
  final VoidCallback? onTotals;
  final VoidCallback? onPdf;
  final VoidCallback? onSendAll;
  final VoidCallback? onClosePeriod;
  final VoidCallback? onCreatePeriod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOpen = openPeriod != null;
    final range = isOpen
        ? '${DateFormat('dd/MM/yyyy').format(openPeriod!.startDate)} – '
              '${DateFormat('dd/MM/yyyy').format(openPeriod!.endDate)}'
        : null;

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Period header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isOpen
                    ? const Color(0xFFE8F5FA)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOpen
                      ? const Color(0xFFB7D9E6)
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          openPeriod?.title ?? 'Sin quincena abierta',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isOpen
                                ? const Color(0xFF0D3141)
                                : scheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? const Color(0xFF0F6F8B).withValues(alpha: 0.12)
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          isOpen ? 'Abierta' : 'Cerrada',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isOpen
                                ? const Color(0xFF0F6F8B)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (range != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      range,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF4D6773),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── Resumen section ─────────────────────────────────────────
            _SidebarSectionLabel(label: 'Resumen'),
            const SizedBox(height: 8),
            _SidebarStatRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Total a pagar',
              value: money.format(totalAbierto),
              highlight: true,
            ),
            _SidebarStatRow(
              icon: Icons.badge_outlined,
              label: 'Base total',
              value: money.format(payrollBase),
            ),
            _SidebarStatRow(
              icon: Icons.flag_outlined,
              label: 'Cuota total',
              value: money.format(payrollQuota),
            ),
            _SidebarStatRow(
              icon: Icons.groups_outlined,
              label: 'Empleados activos',
              value: activeEmployees.toString(),
            ),

            const SizedBox(height: 18),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 18),

            // ── Acciones section ────────────────────────────────────────
            _SidebarSectionLabel(label: 'Acciones'),
            const SizedBox(height: 8),

            FilledButton.icon(
              onPressed: onAddEmployee,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
              label: const Text('Agregar empleado'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F6F8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(36),
                textStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 6),

            _SidebarActionButton(
              icon: Icons.history,
              label: 'Historial',
              onPressed: onHistory,
            ),
            _SidebarActionButton(
              icon: Icons.summarize_outlined,
              label: 'Totales',
              onPressed: onTotals,
            ),
            _SidebarActionButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'PDF',
              onPressed: onPdf,
            ),
            _SidebarActionButton(
              icon: sendingToAll
                  ? Icons.hourglass_empty_outlined
                  : Icons.mark_chat_unread_outlined,
              label: sendingToAll ? 'Enviando...' : 'Enviar a todos',
              onPressed: onSendAll,
            ),
            if (onClosePeriod != null)
              _SidebarActionButton(
                icon: Icons.task_alt_outlined,
                label: 'Cerrar quincena',
                onPressed: onClosePeriod,
              ),
            if (onCreatePeriod != null)
              _SidebarActionButton(
                icon: Icons.add_circle_outline,
                label: 'Abrir quincena',
                onPressed: onCreatePeriod,
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SidebarStatRow extends StatelessWidget {
  const _SidebarStatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: highlight
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 14,
              color: highlight ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 34,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 14),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ),
    );
  }
}

class _NominaDesktopEmployeePanel extends StatelessWidget {
  const _NominaDesktopEmployeePanel({
    required this.employees,
    required this.loading,
    required this.onAdd,
    required this.onManage,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PayrollEmployee> employees;
  final bool loading;
  final VoidCallback onAdd;
  final void Function(PayrollEmployee) onManage;
  final void Function(PayrollEmployee) onEdit;
  final void Function(PayrollEmployee) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Empleados en nómina',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${employees.length} activos',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // ── Content ──────────────────────────────────────────────────
          if (employees.isEmpty)
            _NominaEmptyState(
              icon: Icons.groups_outlined,
              title: 'No hay empleados en nómina',
              message: 'Agrega el primer empleado para comenzar.',
              actionLabel: 'Agregar empleado',
              onAction: onAdd,
            )
          else
            ...employees.map(
              (employee) => _EmployeeCard(
                employee: employee,
                showDetail: true,
                onManage: () => onManage(employee),
                onEdit: () => onEdit(employee),
                onDelete: () => onDelete(employee),
              ),
            ),
        ],
      ),
    );
  }
}
