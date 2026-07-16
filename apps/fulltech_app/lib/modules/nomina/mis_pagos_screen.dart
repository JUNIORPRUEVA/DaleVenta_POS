import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

class MisPagosScreen extends ConsumerStatefulWidget {
  const MisPagosScreen({super.key});

  @override
  ConsumerState<MisPagosScreen> createState() => _MisPagosScreenState();
}

class _MisPagosScreenState extends ConsumerState<MisPagosScreen>
    with WidgetsBindingObserver {
  static const String _companyName = 'FULLTECH, SRL';
  static const String _companyRnc = '133080209';
  static const String _companyPhone = '8295344286';

  bool _loading = true;
  bool _syncing = false;
  String? _error;
  List<PayrollHistoryItem> _items = const [];
  Timer? _autoRefresh;
  DateTime? _lastSyncAt;
  DateTime? _desktopFrom;
  DateTime? _desktopTo;
  _DesktopPayrollStatus _desktopStatus = _DesktopPayrollStatus.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapLoad());
    _autoRefresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_syncing) {
        unawaited(_syncWithCloud(silent: true));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_syncing) {
      unawaited(_syncWithCloud(silent: true));
    }
  }

  Future<void> _bootstrapLoad() async {
    final repo = ref.read(nominaRepositoryProvider);
    final cached = await repo.getCachedMyPayrollHistory().timeout(
      const Duration(milliseconds: 700),
      onTimeout: () => const [],
    );
    if (!mounted) return;
    setState(() {
      _items = cached;
      _loading = false;
      _error = null;
    });
    await _syncWithCloud(silent: true);
  }

  Future<void> _load() async {
    await _syncWithCloud(silent: _items.isNotEmpty);
  }

  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_syncing) return;
    if (!silent) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    setState(() {
      _syncing = true;
    });

    try {
      final data = await ref
          .read(nominaRepositoryProvider)
          .listMyPayrollHistoryAndCache();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
        _syncing = false;
        _error = null;
        _lastSyncAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      final hasLocalData = _items.isNotEmpty;
      final isSessionExpired =
          e is ApiException &&
          (e.code == 401 || e.type == ApiErrorType.unauthorized);
      final baseMessage = isSessionExpired
          ? 'Tu sesion expiro. Inicia sesion de nuevo para ver tus pagos.'
          : 'No se pudo cargar Mis Pagos: $e';
      setState(() {
        _loading = false;
        _syncing = false;
        _error = hasLocalData
            ? 'Mostrando copia local. No se pudo sincronizar con la nube: $baseMessage'
            : baseMessage;
      });
    }
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1240;

  List<PayrollHistoryItem> _applyDesktopFilters(
    List<PayrollHistoryItem> items,
  ) {
    final filtered =
        items
            .where((item) {
              if (_desktopStatus == _DesktopPayrollStatus.paid &&
                  !item.isPaid) {
                return false;
              }
              if (_desktopStatus == _DesktopPayrollStatus.pending &&
                  item.isPaid) {
                return false;
              }

              if (_desktopFrom != null) {
                final from = DateTime(
                  _desktopFrom!.year,
                  _desktopFrom!.month,
                  _desktopFrom!.day,
                );
                if (item.periodEnd.isBefore(from)) return false;
              }

              if (_desktopTo != null) {
                final to = DateTime(
                  _desktopTo!.year,
                  _desktopTo!.month,
                  _desktopTo!.day,
                  23,
                  59,
                  59,
                );
                if (item.periodStart.isAfter(to)) return false;
              }

              return true;
            })
            .toList(growable: false)
          ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

    return filtered;
  }

  Future<void> _pickDesktopDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_desktopFrom ?? now.subtract(const Duration(days: 180)))
        : (_desktopTo ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _desktopFrom = picked;
        if (_desktopTo != null && _desktopTo!.isBefore(picked)) {
          _desktopTo = picked;
        }
      } else {
        _desktopTo = picked;
        if (_desktopFrom != null && picked.isBefore(_desktopFrom!)) {
          _desktopFrom = picked;
        }
      }
    });
  }

  void _resetDesktopFilters() {
    setState(() {
      _desktopFrom = null;
      _desktopTo = null;
      _desktopStatus = _DesktopPayrollStatus.all;
    });
  }

  Future<void> _openHistoryScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _MisPagosHistoryScreen()));
    if (!mounted) return;
    await _load();
  }

  Widget _buildDesktopBody(
    BuildContext context, {
    required PayrollHistoryItem? currentPeriod,
    required List<PayrollHistoryItem> historyItems,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final filteredHistory = _applyDesktopFilters(historyItems);
    final filteredPaid = filteredHistory
        .where((item) => item.isPaid)
        .toList(growable: false);
    final totalBenefits = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.benefitsAmount,
    );
    final totalCommission = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.commissionFromSales,
    );
    final totalNet = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.netTotal,
    );
    final totalGross = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.grossTotal,
    );
    final allItems = [
      if (currentPeriod != null) currentPeriod,
      ...historyItems,
    ];
    final now = DateTime.now();
    final totalPaidCurrentMonth = allItems
        .where((item) => item.isPaid)
        .where((item) {
          final paidOn = item.paymentDate ?? item.periodEnd;
          return paidOn.year == now.year && paidOn.month == now.month;
        })
        .fold<double>(0, (sum, item) => sum + item.netTotal);
    final latestPaidGlobal =
        ([...allItems]..sort(
              (a, b) => (b.paymentDate ?? b.periodEnd).compareTo(
                a.paymentDate ?? a.periodEnd,
              ),
            ))
            .firstWhere(
              (item) => item.isPaid,
              orElse: () => PayrollHistoryItem(
                entryId: '',
                periodId: '',
                periodTitle: '',
                periodStart: DateTime.fromMillisecondsSinceEpoch(0),
                periodEnd: DateTime.fromMillisecondsSinceEpoch(0),
                periodStatus: 'DRAFT',
                baseSalary: 0,
                commissionFromSales: 0,
                overtimeAmount: 0,
                bonusesAmount: 0,
                deductionsAmount: 0,
                benefitsAmount: 0,
                grossTotal: 0,
                netTotal: 0,
              ),
            );
    final hasLatestPaidGlobal = latestPaidGlobal.entryId.isNotEmpty;
    final historicalCount = allItems.length;
    final pendingCount = allItems.where((item) => !item.isPaid).length;
    final latestPaid = filteredPaid.isEmpty ? null : filteredPaid.first;
    final activeFilterCount = [
      if (_desktopFrom != null) 1,
      if (_desktopTo != null) 1,
      if (_desktopStatus != _DesktopPayrollStatus.all) 1,
    ].length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactDesktop = screenWidth < 1440;

    Widget heroActions({required bool compact}) {
      if (compact) {
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: currentPeriod == null
                    ? null
                    : () => _showPayrollDetailsDialog(currentPeriod),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Quincena actual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        );
      }

      return SizedBox(
        width: 270,
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: currentPeriod == null
                    ? null
                    : () => _showPayrollDetailsDialog(currentPeriod),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Quincena actual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final sidebar = _DesktopPaymentsSidebar(
      scheme: scheme,
      money: money,
      activeFilterCount: activeFilterCount,
      currentPeriod: currentPeriod,
      desktopStatus: _desktopStatus,
      desktopFrom: _desktopFrom,
      desktopTo: _desktopTo,
      totalBenefits: totalBenefits,
      totalCommission: totalCommission,
      totalGross: totalGross,
      filteredPaidCount: filteredPaid.length,
      latestPaid: latestPaid,
      error: _error,
      onStatusChanged: (status) => setState(() => _desktopStatus = status),
      onPickFrom: () => _pickDesktopDate(isFrom: true),
      onPickTo: () => _pickDesktopDate(isFrom: false),
      onResetFilters: _resetDesktopFilters,
      onDetails: currentPeriod == null
          ? null
          : () => _showPayrollDetailsDialog(currentPeriod),
      onPdf: currentPeriod == null
          ? null
          : () => _openPayrollPdfPreview(currentPeriod),
    );

    final content = _DesktopPaymentsContent(
      money: money,
      totalBenefits: totalBenefits,
      totalCommission: totalCommission,
      totalNet: totalNet,
      activeFilterCount: activeFilterCount,
      filteredHistory: filteredHistory,
      onTapDetails: _showPayrollDetailsDialog,
      onOpenPdf: _openPayrollPdfPreview,
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.08),
            scheme.primary.withValues(alpha: 0.02),
            scheme.surface,
          ],
        ),
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F3D91), Color(0xFF081A33)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: isCompactDesktop
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _DesktopPaymentsMetric(
                                  label: 'Pagado este mes',
                                  value: money.format(totalPaidCurrentMonth),
                                  icon: Icons.payments_outlined,
                                  accent: const Color(0xFFFDE68A),
                                  dark: true,
                                ),
                                _DesktopPaymentsMetric(
                                  label: 'Ultimo pago',
                                  value: hasLatestPaidGlobal
                                      ? money.format(latestPaidGlobal.netTotal)
                                      : 'Sin pagos',
                                  icon: Icons.update_rounded,
                                  accent: const Color(0xFF86EFAC),
                                  dark: true,
                                ),
                                _DesktopPaymentsMetric(
                                  label: 'Pagos historicos',
                                  value: historicalCount.toString(),
                                  icon: Icons.calendar_month_outlined,
                                  accent: const Color(0xFF93C5FD),
                                  dark: true,
                                ),
                                _DesktopPaymentsMetric(
                                  label: 'Pendientes',
                                  value: pendingCount.toString(),
                                  icon: Icons.schedule_outlined,
                                  accent: const Color(0xFFFCA5A5),
                                  dark: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            heroActions(compact: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _DesktopPaymentsMetric(
                                    label: 'Pagado este mes',
                                    value: money.format(totalPaidCurrentMonth),
                                    icon: Icons.payments_outlined,
                                    accent: const Color(0xFFFDE68A),
                                    dark: true,
                                  ),
                                  _DesktopPaymentsMetric(
                                    label: 'Ultimo pago',
                                    value: hasLatestPaidGlobal
                                        ? money.format(
                                            latestPaidGlobal.netTotal,
                                          )
                                        : 'Sin pagos',
                                    icon: Icons.update_rounded,
                                    accent: const Color(0xFF86EFAC),
                                    dark: true,
                                  ),
                                  _DesktopPaymentsMetric(
                                    label: 'Pagos historicos',
                                    value: historicalCount.toString(),
                                    icon: Icons.calendar_month_outlined,
                                    accent: const Color(0xFF93C5FD),
                                    dark: true,
                                  ),
                                  _DesktopPaymentsMetric(
                                    label: 'Pendientes',
                                    value: pendingCount.toString(),
                                    icon: Icons.schedule_outlined,
                                    accent: const Color(0xFFFCA5A5),
                                    dark: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            heroActions(compact: false),
                          ],
                        ),
                ),
                const SizedBox(height: 22),
                isCompactDesktop
                    ? Column(
                        children: [
                          sidebar,
                          const SizedBox(height: 16),
                          content,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 340, child: sidebar),
                          const SizedBox(width: 20),
                          Expanded(child: content),
                        ],
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
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isDesktop = _isDesktop(context);

    final currentPeriod = _items.firstWhere(
      (item) => item.periodStatus.toUpperCase() == 'OPEN',
      orElse: () => _items.firstWhere(
        (item) => !item.isPaid,
        orElse: () => PayrollHistoryItem(
          entryId: '',
          periodId: '',
          periodTitle: '',
          periodStart: DateTime.fromMillisecondsSinceEpoch(0),
          periodEnd: DateTime.fromMillisecondsSinceEpoch(0),
          periodStatus: '',
          baseSalary: 0,
          commissionFromSales: 0,
          overtimeAmount: 0,
          bonusesAmount: 0,
          deductionsAmount: 0,
          benefitsAmount: 0,
          grossTotal: 0,
          netTotal: 0,
        ),
      ),
    );
    final hasCurrentPeriod = currentPeriod.periodId.isNotEmpty;
    final historyItems = _items
        .where(
          (item) =>
              !hasCurrentPeriod || item.periodId != currentPeriod.periodId,
        )
        .toList();

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Mis Pagos',
        showLogo: false,
        darkerTone: true,
        actions: [
          IconButton(
            tooltip: 'Historial completo',
            onPressed: _openHistoryScreen,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Sincronizar con la nube',
            onPressed: _syncing ? null : _load,
            icon: Icon(
              _syncing ? Icons.cloud_sync_rounded : Icons.cloud_upload_rounded,
            ),
          ),
        ],
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: UserAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    imageUrl: currentUser.fotoPersonalUrl,
                    child: Text(
                      getInitials(currentUser.nombreCompleto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: isDesktop
          ? RefreshIndicator(
              onRefresh: _load,
              child: _buildDesktopBody(
                context,
                currentPeriod: hasCurrentPeriod ? currentPeriod : null,
                historyItems: historyItems,
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_syncing || _lastSyncAt != null) ...[
                    _SyncStatusBanner(
                      syncing: _syncing,
                      lastSyncAt: _lastSyncAt,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _CurrentPeriodCard(
                    item: hasCurrentPeriod ? currentPeriod : null,
                    onPdf: hasCurrentPeriod
                        ? () => _openPayrollPdfPreview(currentPeriod)
                        : null,
                    onDetails: hasCurrentPeriod
                        ? () => _showPayrollDetailsDialog(currentPeriod)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<Uint8List> _buildPayrollPdf(PayrollHistoryItem item) async {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    final currentUser = ref.read(authStateProvider).user;
    final fallbackName = (currentUser?.nombreCompleto ?? '').trim().isNotEmpty
        ? currentUser!.nombreCompleto.trim()
        : _nameFromEmail(currentUser?.email ?? '');
    final employeeName = item.employeeName.trim().isNotEmpty
        ? item.employeeName.trim()
        : fallbackName;
    final employeeRole = _roleLabel(currentUser?.role ?? '');

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      _companyName,
                      style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('RNC: $_companyRnc'),
                    pw.Text('Tel: $_companyPhone'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'COMPROBANTE DE PAGO DE NÓMINA',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 6),
              pw.Text('Empleado: $employeeName'),
              pw.Text('Rol: $employeeRole'),
              pw.Text('Quincena: ${item.periodTitle}'),
              pw.Text('Rango: $range'),
              pw.Text('Estado: ${item.isPaid ? 'Pagado' : 'Pendiente'}'),
              pw.SizedBox(height: 14),
              pw.Text('Salario quincenal: ${money.format(item.baseSalary)}'),
              pw.Text('Comisión: ${money.format(item.commissionFromSales)}'),
              pw.Text(
                'Extras: ${money.format(item.overtimeAmount + item.bonusesAmount)}',
              ),
              pw.Text('Beneficios: ${money.format(item.benefitsAmount)}'),
              pw.Text('Deducciones: ${money.format(item.deductionsAmount)}'),
              pw.Divider(),
              pw.Text(
                'Neto a pagar: ${money.format(item.netTotal)}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  String _roleLabel(String rawRole) {
    switch (rawRole.toUpperCase()) {
      case 'ADMIN':
        return 'Administrador';
      case 'ASISTENTE':
        return 'Asistente';
      case 'MARKETING':
        return 'Marketing';
      case 'VENDEDOR':
        return 'Vendedor';
      case 'TECNICO':
        return 'Técnico';
      default:
        return rawRole.isEmpty ? 'N/D' : rawRole;
    }
  }

  String _nameFromEmail(String email) {
    final clean = email.trim();
    if (clean.isEmpty) return 'N/D';
    final username = clean.split('@').first.trim();
    if (username.isEmpty) return clean;
    final words = username
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return username;
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _openPayrollPdfPreview(PayrollHistoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PayrollPdfPreviewScreen(
          title: item.periodTitle,
          buildPdf: () => _buildPayrollPdf(item),
        ),
      ),
    );
  }

  Future<void> _showPayrollDetailsDialog(PayrollHistoryItem item) async {
    final net = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$',
    ).format(item.netTotal);
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.periodTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(range),
              const SizedBox(height: 8),
              _DetailRow(label: 'Estado', value: item.statusLabel),
              _DetailRow(
                label: 'Fecha de pago',
                value: item.paymentDate == null
                    ? 'Pendiente'
                    : DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(item.paymentDate!),
              ),
              _DetailRow(label: 'Salario base', value: item.baseSalary),
              _DetailRow(label: 'Comisiones', value: item.commissions),
              _DetailRow(label: 'Bonos', value: item.bonuses),
              _DetailRow(label: 'Horas extra', value: item.overtime),
              _DetailRow(label: 'Descuentos', value: item.discounts),
              _DetailRow(
                label: 'Extras',
                value: item.overtimeAmount + item.bonusesAmount,
              ),
              _DetailRow(label: 'Beneficios', value: item.benefitsAmount),
              _DetailRow(label: 'Deducciones', value: item.deductionsAmount),
              _DetailRow(label: 'Total bruto', value: item.totalGross),
              _DetailRow(
                label: 'Total descontado',
                value: item.totalDiscounted,
              ),
              const Divider(height: 20),
              _DetailRow(
                label: 'Metodo de pago',
                value: item.paymentMethod ?? 'N/D',
              ),
              _DetailRow(
                label: 'Referencia',
                value: item.paymentReference?.trim().isNotEmpty == true
                    ? item.paymentReference!
                    : 'N/D',
              ),
              _DetailRow(
                label: 'Notas',
                value: item.notes?.trim().isNotEmpty == true
                    ? item.notes!
                    : 'N/D',
              ),
              _DetailRow(
                label: 'Creado',
                value: item.createdAt == null
                    ? 'N/D'
                    : DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(item.createdAt!),
              ),
              _DetailRow(
                label: 'Actualizado',
                value: item.updatedAt == null
                    ? 'N/D'
                    : DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(item.updatedAt!),
              ),
              const Divider(height: 20),
              _DetailRow(label: 'Neto quincena', value: net, bold: true),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openPayrollPdfPreview(item),
            icon: const Icon(Icons.download_outlined),
            label: const Text('PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({required this.syncing, required this.lastSyncAt});

  final bool syncing;
  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final label = syncing
        ? 'Sincronizando con la nube...'
        : lastSyncAt == null
        ? 'Sincronización pendiente'
        : 'Sincronizado ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(lastSyncAt!)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            syncing ? Icons.cloud_sync_rounded : Icons.cloud_done_rounded,
            color: syncing ? colorScheme.primary : colorScheme.tertiary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DesktopPayrollStatus {
  all('Todo'),
  paid('Pagado'),
  pending('Pendiente');

  const _DesktopPayrollStatus(this.label);
  final String label;
}

class _CurrentPeriodCard extends StatelessWidget {
  const _CurrentPeriodCard({required this.item, this.onPdf, this.onDetails});

  final PayrollHistoryItem? item;
  final VoidCallback? onPdf;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    if (item == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.event_busy_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No hay quincena en curso abierta',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final range =
        '${DateFormat('dd/MM/yyyy').format(item!.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item!.periodEnd)}';
    final statusColor = item!.isPaid
        ? const Color(0xFF166534)
        : const Color(0xFF9A3412);
    final statusBg = item!.isPaid
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFEDD5);
    final paidDateLabel = item!.paymentDate == null
        ? 'Pendiente de pago'
        : 'Pagada ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item!.paymentDate!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quincena en curso',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item!.periodTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      range,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  item!.statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              paidDateLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _PeriodAmountRow(
            label: 'Salario base',
            value: money.format(item!.baseSalary),
          ),
          _PeriodAmountRow(
            label: 'Comisiones',
            value: money.format(item!.commissions),
          ),
          _PeriodAmountRow(label: 'Bonos', value: money.format(item!.bonuses)),
          _PeriodAmountRow(
            label: 'Descuentos',
            value: money.format(item!.totalDiscounted),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.11),
                  theme.colorScheme.primary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Neto quincena',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  money.format(item!.netTotal),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Detalles'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodAmountRow extends StatelessWidget {
  const _PeriodAmountRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onTap, this.onPdf});

  final PayrollHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    final net = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$',
    ).format(item.netTotal);
    final statusColor = item.isPaid
        ? const Color(0xFF166534)
        : const Color(0xFF9A3412);
    final statusBg = item.isPaid
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFEDD5);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.isPaid
                      ? Icons.verified_outlined
                      : Icons.schedule_outlined,
                  size: 18,
                  color: item.isPaid ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.periodTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        range,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 128),
                  child: Text(
                    net,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onTap, child: const Text('Detalles')),
                if (onPdf != null)
                  TextButton(onPressed: onPdf, child: const Text('PDF')),
              ],
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final Object value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = value is num
        ? NumberFormat.currency(locale: 'en_US', symbol: 'RD\$').format(value)
        : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPdfPreviewScreen extends StatelessWidget {
  const _PayrollPdfPreviewScreen({required this.title, required this.buildPdf});

  final String title;
  final Future<Uint8List> Function() buildPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'PDF · $title',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        build: (_) => buildPdf(),
      ),
    );
  }
}

enum _HistoryStatusFilter { all, paid, pending, closed, canceled }

enum _HistorySortOrder { newest, oldest }

class _HistoryFilters {
  const _HistoryFilters({
    this.search = '',
    this.status = _HistoryStatusFilter.all,
    this.from,
    this.to,
    this.sort = _HistorySortOrder.newest,
  });

  final String search;
  final _HistoryStatusFilter status;
  final DateTime? from;
  final DateTime? to;
  final _HistorySortOrder sort;

  _HistoryFilters copyWith({
    String? search,
    _HistoryStatusFilter? status,
    DateTime? from,
    DateTime? to,
    bool clearFrom = false,
    bool clearTo = false,
    _HistorySortOrder? sort,
  }) {
    return _HistoryFilters(
      search: search ?? this.search,
      status: status ?? this.status,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      sort: sort ?? this.sort,
    );
  }
}

class _MisPagosHistoryScreen extends ConsumerStatefulWidget {
  const _MisPagosHistoryScreen();

  @override
  ConsumerState<_MisPagosHistoryScreen> createState() =>
      _MisPagosHistoryScreenState();
}

class _MisPagosHistoryScreenState
    extends ConsumerState<_MisPagosHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<PayrollHistoryItem> _items = const [];
  _HistoryFilters _filters = const _HistoryFilters();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = _filters.status == _HistoryStatusFilter.paid
          ? 'PAID'
          : _filters.status == _HistoryStatusFilter.pending
          ? 'DRAFT'
          : null;
      final data = await ref
          .read(nominaRepositoryProvider)
          .listMyPayrollHistory(
            from: _filters.from,
            to: _filters.to,
            status: status,
            period: _filters.search.trim().isEmpty
                ? null
                : _filters.search.trim(),
          );

      final filtered =
          data
              .where((item) {
                final openCurrent =
                    item.periodStatus.toUpperCase() == 'OPEN' && !item.isPaid;
                if (openCurrent) return false;

                if (_filters.status == _HistoryStatusFilter.closed &&
                    item.periodStatus.toUpperCase() != 'CLOSED') {
                  return false;
                }

                if (_filters.status == _HistoryStatusFilter.canceled) {
                  final statusText = item.paymentStatus.toUpperCase();
                  if (statusText != 'CANCELED' && statusText != 'CANCELLED') {
                    return false;
                  }
                }

                return true;
              })
              .toList(growable: false)
            ..sort((a, b) {
              final left = a.paymentDate ?? a.periodEnd;
              final right = b.paymentDate ?? b.periodEnd;
              return _filters.sort == _HistorySortOrder.newest
                  ? right.compareTo(left)
                  : left.compareTo(right);
            });

      if (!mounted) return;
      setState(() {
        _items = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el historial: $e';
      });
    }
  }

  Future<void> _openFilterPanel() async {
    final result = await showGeneralDialog<_HistoryFilters>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar filtros',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, __) {
        final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(
          320.0,
          520.0,
        );
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            child: SafeArea(child: _HistoryFilterPanel(initial: _filters)),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
    if (result == null) return;
    setState(() => _filters = result);
    await _load();
  }

  Future<Uint8List> _buildHistoryPdf(PayrollHistoryItem item) async {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final user = ref.read(authStateProvider).user;
    final employeeName = item.employeeName.trim().isNotEmpty
        ? item.employeeName.trim()
        : (user?.nombreCompleto.trim().isNotEmpty == true
              ? user!.nombreCompleto.trim()
              : 'Técnico');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'FULLTECH, SRL',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Comprobante de pago de nómina',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Empleado: $employeeName'),
              pw.Text('Quincena: ${item.periodTitle}'),
              pw.Text('Rango: $range'),
              pw.Text('Estado: ${item.statusLabel}'),
              pw.SizedBox(height: 12),
              pw.Text('Salario base: ${money.format(item.baseSalary)}'),
              pw.Text('Comisiones: ${money.format(item.commissions)}'),
              pw.Text('Bonos: ${money.format(item.bonuses)}'),
              pw.Text('Descuentos: ${money.format(item.totalDiscounted)}'),
              pw.Divider(),
              pw.Text(
                'Neto: ${money.format(item.netTotal)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _openPdf(PayrollHistoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PayrollPdfPreviewScreen(
          title: item.periodTitle,
          buildPdf: () => _buildHistoryPdf(item),
        ),
      ),
    );
  }

  Future<void> _openDetails(PayrollHistoryItem item) async {
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.periodTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(range),
              const SizedBox(height: 8),
              _DetailRow(label: 'Estado', value: item.statusLabel),
              _DetailRow(
                label: 'Fecha de pago',
                value: item.paymentDate == null
                    ? 'Pendiente'
                    : DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(item.paymentDate!),
              ),
              _DetailRow(label: 'Salario base', value: item.baseSalary),
              _DetailRow(label: 'Comisiones', value: item.commissions),
              _DetailRow(label: 'Bonos', value: item.bonuses),
              _DetailRow(label: 'Descuentos', value: item.totalDiscounted),
              const Divider(),
              _DetailRow(label: 'Neto', value: item.netTotal, bold: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _openPdf(item), child: const Text('PDF')),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Historial de pagos',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilterPanel,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pagos anteriores',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_items.length} registros',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: const Text(
                  'No hay pagos para los filtros seleccionados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            else
              ..._items.map(
                (item) => _HistoryTile(
                  item: item,
                  onTap: () => _openDetails(item),
                  onPdf: () => _openPdf(item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterPanel extends StatefulWidget {
  const _HistoryFilterPanel({required this.initial});

  final _HistoryFilters initial;

  @override
  State<_HistoryFilterPanel> createState() => _HistoryFilterPanelState();
}

class _HistoryFilterPanelState extends State<_HistoryFilterPanel> {
  late final TextEditingController _searchController;
  late _HistoryStatusFilter _status;
  DateTime? _from;
  DateTime? _to;
  late _HistorySortOrder _sort;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initial.search);
    _status = widget.initial.status;
    _from = widget.initial.from;
    _to = widget.initial.to;
    _sort = widget.initial.sort;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? now.subtract(const Duration(days: 120)))
        : (_to ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _HistoryFilters(
        search: _searchController.text.trim(),
        status: _status,
        from: _from,
        to: _to,
        sort: _sort,
      ),
    );
  }

  void _clear() {
    Navigator.pop(context, const _HistoryFilters());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        bottomLeft: Radius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtros',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por período',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Estado', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                        ('Todos', _HistoryStatusFilter.all),
                        ('Pagado', _HistoryStatusFilter.paid),
                        ('Pendiente', _HistoryStatusFilter.pending),
                        ('Cerrado', _HistoryStatusFilter.closed),
                        ('Cancelado', _HistoryStatusFilter.canceled),
                      ]
                      .map(
                        (entry) => ChoiceChip(
                          label: Text(entry.$1),
                          selected: _status == entry.$2,
                          onSelected: (_) => setState(() => _status = entry.$2),
                        ),
                      )
                      .toList(growable: false),
            ),
            const SizedBox(height: 12),
            Text('Rango de fecha', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.event_available_outlined, size: 16),
                    label: Text(
                      _from == null
                          ? 'Desde'
                          : DateFormat('dd/MM/yy').format(_from!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.event_busy_outlined, size: 16),
                    label: Text(
                      _to == null
                          ? 'Hasta'
                          : DateFormat('dd/MM/yy').format(_to!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Ordenar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Más reciente'),
                  selected: _sort == _HistorySortOrder.newest,
                  onSelected: (_) =>
                      setState(() => _sort = _HistorySortOrder.newest),
                ),
                ChoiceChip(
                  label: const Text('Más antiguo'),
                  selected: _sort == _HistorySortOrder.oldest,
                  onSelected: (_) =>
                      setState(() => _sort = _HistorySortOrder.oldest),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Aplicar filtros'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPaymentsPanel extends StatelessWidget {
  const _DesktopPaymentsPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DesktopPaymentsSidebar extends StatelessWidget {
  const _DesktopPaymentsSidebar({
    required this.scheme,
    required this.money,
    required this.activeFilterCount,
    required this.currentPeriod,
    required this.desktopStatus,
    required this.desktopFrom,
    required this.desktopTo,
    required this.totalBenefits,
    required this.totalCommission,
    required this.totalGross,
    required this.filteredPaidCount,
    required this.latestPaid,
    required this.error,
    required this.onStatusChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onResetFilters,
    required this.onDetails,
    required this.onPdf,
  });

  final ColorScheme scheme;
  final NumberFormat money;
  final int activeFilterCount;
  final PayrollHistoryItem? currentPeriod;
  final _DesktopPayrollStatus desktopStatus;
  final DateTime? desktopFrom;
  final DateTime? desktopTo;
  final double totalBenefits;
  final double totalCommission;
  final double totalGross;
  final int filteredPaidCount;
  final PayrollHistoryItem? latestPaid;
  final String? error;
  final ValueChanged<_DesktopPayrollStatus> onStatusChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onResetFilters;
  final VoidCallback? onDetails;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DesktopPaymentsPanel(
          title: 'Filtros',
          subtitle: 'Refina pagos y beneficios por fecha y estado',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _DesktopPayrollStatus.values
                    .map(
                      (status) => _DesktopStatusChip(
                        label: status.label,
                        selected: desktopStatus == status,
                        onTap: () => onStatusChanged(status),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              _DesktopFilterButton(
                label: 'Desde',
                value: desktopFrom == null
                    ? 'Cualquier fecha'
                    : DateFormat('dd/MM/yyyy').format(desktopFrom!),
                icon: Icons.event_available_outlined,
                onTap: onPickFrom,
              ),
              const SizedBox(height: 10),
              _DesktopFilterButton(
                label: 'Hasta',
                value: desktopTo == null
                    ? 'Cualquier fecha'
                    : DateFormat('dd/MM/yyyy').format(desktopTo!),
                icon: Icons.event_busy_outlined,
                onTap: onPickTo,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: activeFilterCount == 0 ? null : onResetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpiar filtros'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Resumen personal',
          subtitle: 'Lectura ejecutiva del historial visible',
          child: Column(
            children: [
              _DesktopInfoLine(
                label: 'Beneficio total alcanzado',
                value: money.format(totalBenefits),
                emphasized: true,
              ),
              _DesktopInfoLine(
                label: 'Comisión acumulada',
                value: money.format(totalCommission),
              ),
              _DesktopInfoLine(
                label: 'Total bruto',
                value: money.format(totalGross),
              ),
              _DesktopInfoLine(
                label: 'Pagos completados',
                value: filteredPaidCount.toString(),
              ),
              _DesktopInfoLine(
                label: 'Último pago',
                value: latestPaid == null
                    ? 'Sin pagos'
                    : DateFormat('dd/MM/yyyy').format(latestPaid!.periodEnd),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Quincena en curso',
          subtitle: currentPeriod == null
              ? 'No hay una quincena abierta ahora mismo'
              : currentPeriod!.periodTitle,
          child: _DesktopCurrentPeriodCard(
            item: currentPeriod,
            onDetails: onDetails,
            onPdf: onPdf,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
            ),
            child: Text(
              error!,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopPaymentsContent extends StatelessWidget {
  const _DesktopPaymentsContent({
    required this.money,
    required this.totalBenefits,
    required this.totalCommission,
    required this.totalNet,
    required this.activeFilterCount,
    required this.filteredHistory,
    required this.onTapDetails,
    required this.onOpenPdf,
  });

  final NumberFormat money;
  final double totalBenefits;
  final double totalCommission;
  final double totalNet;
  final int activeFilterCount;
  final List<PayrollHistoryItem> filteredHistory;
  final ValueChanged<PayrollHistoryItem> onTapDetails;
  final ValueChanged<PayrollHistoryItem> onOpenPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 920;
            final cardWidth = isNarrow
                ? constraints.maxWidth
                : (constraints.maxWidth - 28) / 3;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Beneficio filtrado',
                    value: money.format(totalBenefits),
                    subtitle: 'Beneficios visibles dentro del rango actual',
                    icon: Icons.verified_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Comisión por ventas',
                    value: money.format(totalCommission),
                    subtitle: 'Comisión acumulada en el historial filtrado',
                    icon: Icons.auto_graph_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Neto recibido',
                    value: money.format(totalNet),
                    subtitle: 'Pagos netos ya liquidados',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Historial de pagos',
          subtitle: activeFilterCount == 0
              ? 'Vista completa de tus quincenas registradas'
              : 'Resultados refinados por el filtro actual',
          child: filteredHistory.isEmpty
              ? const _DesktopPaymentsEmptyState()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 920),
                    child: Column(
                      children: [
                        const _DesktopPaymentsHistoryHeader(),
                        ...filteredHistory.map(
                          (item) => _DesktopPaymentsHistoryRow(
                            item: item,
                            onTap: () => onTapDetails(item),
                            onPdf: () => onOpenPdf(item),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DesktopPaymentsMetric extends StatelessWidget {
  const _DesktopPaymentsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.dark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark
        ? Colors.white.withValues(alpha: 0.72)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.14)
              : accent.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: dark ? Colors.white : accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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

class _DesktopStatusChip extends StatelessWidget {
  const _DesktopStatusChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
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

class _DesktopFilterButton extends StatelessWidget {
  const _DesktopFilterButton({
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
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

class _DesktopInfoLine extends StatelessWidget {
  const _DesktopInfoLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              color: emphasized ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopCurrentPeriodCard extends StatelessWidget {
  const _DesktopCurrentPeriodCard({
    required this.item,
    required this.onDetails,
    required this.onPdf,
  });

  final PayrollHistoryItem? item;
  final VoidCallback? onDetails;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');

    if (item == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: const Text(
          'No tienes una quincena abierta ahora mismo.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }

    final range =
        '${DateFormat('dd/MM/yyyy').format(item!.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item!.periodEnd)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item!.periodTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(range, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          _DesktopInfoLine(
            label: 'Neto estimado',
            value: money.format(item!.netTotal),
            emphasized: true,
          ),
          _DesktopInfoLine(
            label: 'Beneficios',
            value: money.format(item!.benefitsAmount),
          ),
          _DesktopInfoLine(
            label: 'Comisión',
            value: money.format(item!.commissionFromSales),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Detalles'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsKpiCard extends StatelessWidget {
  const _DesktopPaymentsKpiCard({
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
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsHistoryHeader extends StatelessWidget {
  const _DesktopPaymentsHistoryHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(flex: 3, child: Text('Quincena', style: style)),
          const SizedBox(width: 14),
          Expanded(flex: 2, child: Text('Rango', style: style)),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text('Beneficios', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text('Comisión', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 140,
            child: Text('Neto', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 84,
            child: Text('Estado', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 114),
        ],
      ),
    );
  }
}

class _DesktopPaymentsHistoryRow extends StatelessWidget {
  const _DesktopPaymentsHistoryRow({
    required this.item,
    required this.onTap,
    required this.onPdf,
  });

  final PayrollHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Icon(
            item.isPaid ? Icons.verified_outlined : Icons.schedule_outlined,
            color: item.isPaid
                ? const Color(0xFF15803D)
                : const Color(0xFFEA580C),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              item.periodTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Text(
              range,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text(
              money.format(item.benefitsAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text(
              money.format(item.commissionFromSales),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 140,
            child: Text(
              money.format(item.netTotal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: item.isPaid
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.statusLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: item.isPaid
                    ? const Color(0xFF166534)
                    : const Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Ver detalles',
            onPressed: onTap,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsEmptyState extends StatelessWidget {
  const _DesktopPaymentsEmptyState();

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
          Icon(Icons.receipt_long_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'No hay resultados con este filtro',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ajusta las fechas o el estado para volver a mostrar tus quincenas registradas.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
