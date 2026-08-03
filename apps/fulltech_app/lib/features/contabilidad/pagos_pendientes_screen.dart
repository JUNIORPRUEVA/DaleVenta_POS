import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/contabilidad_repository.dart';
import 'models/payable_models.dart';
import 'utils/payable_payment_pdf_service.dart';

// Sort options
enum _SortOrder { dueDateAsc, dueDateDesc, amountDesc, amountAsc, nameAsc }

extension _SortOrderLabel on _SortOrder {
  String get label {
    switch (this) {
      case _SortOrder.dueDateAsc:
        return 'Vence antes';
      case _SortOrder.dueDateDesc:
        return 'Vence después';
      case _SortOrder.amountDesc:
        return 'Mayor monto';
      case _SortOrder.amountAsc:
        return 'Menor monto';
      case _SortOrder.nameAsc:
        return 'A–Z';
    }
  }
}

enum _DueStatus { overdue, soon, ok }

class PagosPendientesScreen extends ConsumerStatefulWidget {
  const PagosPendientesScreen({super.key});

  @override
  ConsumerState<PagosPendientesScreen> createState() =>
      _PagosPendientesScreenState();
}

class _PagosPendientesScreenState extends ConsumerState<PagosPendientesScreen> {
  final _money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _error;
  List<PayableService> _services = const [];
  List<PayablePayment> _payments = const [];
  _SortOrder _sortOrder = _SortOrder.dueDateAsc;
  bool _historyExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(contabilidadRepositoryProvider);
      final results = await Future.wait([
        repo.listPayableServices(),
        repo.listPayablePayments(),
      ]);
      if (!mounted) return;
      setState(() {
        _services = results[0] as List<PayableService>;
        _payments = results[1] as List<PayablePayment>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar pagos pendientes: $e';
        _loading = false;
      });
    }
  }

  List<PayableService> get _activeServices {
    final list = _services.where((s) => s.active).toList();
    list.sort((a, b) {
      switch (_sortOrder) {
        case _SortOrder.dueDateAsc:
          return a.nextDueDate.compareTo(b.nextDueDate);
        case _SortOrder.dueDateDesc:
          return b.nextDueDate.compareTo(a.nextDueDate);
        case _SortOrder.amountDesc:
          return (b.defaultAmount ?? 0).compareTo(a.defaultAmount ?? 0);
        case _SortOrder.amountAsc:
          return (a.defaultAmount ?? 0).compareTo(b.defaultAmount ?? 0);
        case _SortOrder.nameAsc:
          return a.title.compareTo(b.title);
      }
    });
    return list;
  }

  PayableService? _findService(String serviceId) {
    for (final s in _services) {
      if (s.id == serviceId) return s;
    }
    return null;
  }

  Future<void> _showSnack(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double get _totalEstimated {
    return _activeServices.fold(0.0, (sum, s) => sum + (s.defaultAmount ?? 0));
  }

  int get _overdueCount {
    final now = DateTime.now();
    return _activeServices.where((s) => s.nextDueDate.isBefore(now)).length;
  }

  int get _dueSoonCount {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));
    return _activeServices
        .where(
          (s) => !s.nextDueDate.isBefore(now) && s.nextDueDate.isBefore(limit),
        )
        .length;
  }

  Future<void> _openCreateFixedDialog() async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var providerKind = PayableProviderKind.person;
    var frequency = PayableFrequency.monthly;
    var dueDate = DateTime.now();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLS) => AlertDialog(
          title: const Text('Nuevo servicio fijo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Servicio / concepto',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PayableProviderKind>(
                  initialValue: providerKind,
                  items: PayableProviderKind.values
                      .map(
                        (k) => DropdownMenuItem(value: k, child: Text(k.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLS(() => providerKind = v);
                  },
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: providerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre persona / empresa',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PayableFrequency>(
                  initialValue: frequency,
                  items: const [
                    DropdownMenuItem(
                      value: PayableFrequency.monthly,
                      child: Text('Mensual'),
                    ),
                    DropdownMenuItem(
                      value: PayableFrequency.biweekly,
                      child: Text('Quincenal'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLS(() => frequency = v);
                  },
                  decoration: const InputDecoration(labelText: 'Frecuencia'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monto estimado (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Próximo pago'),
                  subtitle: Text(_dateFmt.format(dueDate)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: dueDate,
                    );
                    if (picked != null) setLS(() => dueDate = picked);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Detalle (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final providerName = providerCtrl.text.trim();
                if (title.isEmpty || providerName.isEmpty) {
                  await _showSnack('Completa servicio y beneficiario');
                  return;
                }
                final amount = double.tryParse(amountCtrl.text.trim());
                try {
                  await ref
                      .read(contabilidadRepositoryProvider)
                      .createPayableService(
                        title: title,
                        providerKind: providerKind,
                        providerName: providerName,
                        description: noteCtrl.text,
                        frequency: frequency,
                        defaultAmount: amount,
                        nextDueDate: dueDate,
                      );
                  if (!ctx.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  await _showSnack('No se pudo guardar: $e');
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      await _load();
      await _showSnack('Servicio fijo guardado');
    }
  }

  Future<void> _openDirectPaymentDialog() async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var providerKind = PayableProviderKind.person;
    var paidAt = DateTime.now();

    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLS) => AlertDialog(
          title: const Text('Registrar pago directo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Concepto (ej: Renta local)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PayableProviderKind>(
                  initialValue: providerKind,
                  items: PayableProviderKind.values
                      .map(
                        (k) => DropdownMenuItem(value: k, child: Text(k.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLS(() => providerKind = v);
                  },
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: providerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Persona / empresa',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Monto pagado'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de pago'),
                  subtitle: Text(_dateFmt.format(paidAt)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: paidAt,
                    );
                    if (picked != null) setLS(() => paidAt = picked);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Detalle (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final providerName = providerCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (title.isEmpty || providerName.isEmpty || amount <= 0) {
                  await _showSnack('Completa los campos y el monto');
                  return;
                }
                try {
                  final repo = ref.read(contabilidadRepositoryProvider);
                  final service = await repo.createPayableService(
                    title: title,
                    providerKind: providerKind,
                    providerName: providerName,
                    description: noteCtrl.text,
                    frequency: PayableFrequency.oneTime,
                    defaultAmount: amount,
                    nextDueDate: paidAt,
                    active: true,
                  );
                  await repo.registerPayablePayment(
                    serviceId: service.id,
                    amount: amount,
                    paidAt: paidAt,
                    note: noteCtrl.text,
                  );
                  if (!ctx.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  await _showSnack('No se pudo registrar: $e');
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (done == true) {
      await _load();
      await _showSnack('Pago directo registrado');
    }
  }

  Future<void> _openRegisterPaymentDialog(PayableService service) async {
    final amountCtrl = TextEditingController(
      text: service.defaultAmount?.toStringAsFixed(2) ?? '',
    );
    final noteCtrl = TextEditingController();
    var paidAt = DateTime.now();

    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLS) => AlertDialog(
          title: const Text('Marcar como pagado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  service.providerName,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Monto pagado'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de pago'),
                  subtitle: Text(_dateFmt.format(paidAt)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: paidAt,
                    );
                    if (picked != null) setLS(() => paidAt = picked);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amount <= 0) {
                  await _showSnack('Ingresa un monto válido');
                  return;
                }
                try {
                  await ref
                      .read(contabilidadRepositoryProvider)
                      .registerPayablePayment(
                        serviceId: service.id,
                        amount: amount,
                        paidAt: paidAt,
                        note: noteCtrl.text,
                      );
                  if (!ctx.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  await _showSnack('No se pudo registrar el pago: $e');
                }
              },
              child: const Text('Confirmar pago'),
            ),
          ],
        ),
      ),
    );
    if (done == true) {
      await _load();
      await _showSnack('Pago registrado correctamente');
    }
  }

  Future<void> _openReceiptPreview({
    required PayableService service,
    required List<PayablePayment> payments,
    required DateTime from,
    required DateTime to,
  }) async {
    if (payments.isEmpty) {
      await _showSnack('No hay pagos en ese período');
      return;
    }
    final bytes = await buildPayableReceiptPdf(
      data: PayableReceiptPdfData(
        companyName: 'FULLTECH',
        serviceTitle: service.title,
        providerName: service.providerName,
        providerKind: service.providerKind,
        periodFrom: from,
        periodTo: to,
        payments: payments,
      ),
    );
    if (!mounted) return;
    final fileName =
        'comprobante_${service.providerName.replaceAll(' ', '_')}_${DateFormat('yyyyMM').format(from)}.pdf';
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: 700,
          child: Column(
            children: [
              ListTile(
                title: Text('Comprobante · ${service.providerName}'),
                trailing: IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Compartir PDF',
                  onPressed: () async {
                    await sharePayableReceiptPdf(
                      bytes: bytes,
                      filename: fileName,
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: PdfPreview(
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  build: (_) async => bytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMonthlyReceiptForService(PayableService service) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
      helpText: 'Selecciona un día del mes a reportar',
    );
    if (selected == null) return;
    final from = DateTime(selected.year, selected.month, 1);
    final to = DateTime(selected.year, selected.month + 1, 0, 23, 59, 59);
    final monthly = service.payments
        .where((p) => !p.paidAt.isBefore(from) && !p.paidAt.isAfter(to))
        .toList();
    await _openReceiptPreview(
      service: service,
      payments: monthly,
      from: from,
      to: to,
    );
  }

  Future<void> _toggleActive(PayableService service) async {
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .updatePayableService(id: service.id, active: !service.active);
      await _load();
    } catch (e) {
      await _showSnack('No se pudo actualizar estado: $e');
    }
  }

  Future<void> _confirmDeleteService(PayableService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text(
          '¿Eliminar "${service.title}" y todos sus pagos? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .deletePayableService(service.id);
      await _load();
      if (mounted) await _showSnack('Servicio eliminado');
    } catch (e) {
      if (mounted) await _showSnack('No se pudo eliminar: $e');
    }
  }

  Future<void> _confirmDeletePayment(PayablePayment payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: const Text(
          '¿Eliminar este pago registrado? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .deletePayablePayment(payment.id);
      await _load();
      if (mounted) await _showSnack('Pago eliminado');
    } catch (e) {
      if (mounted) await _showSnack('No se pudo eliminar: $e');
    }
  }

  Future<void> _openEditPaymentDialog(PayablePayment payment) async {
    final amountCtrl = TextEditingController(
      text: payment.amount.toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController(text: payment.note ?? '');
    var paidAt = payment.paidAt;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLS) => AlertDialog(
          title: const Text('Editar pago'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Monto'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de pago'),
                  subtitle: Text(_dateFmt.format(paidAt)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: paidAt,
                    );
                    if (picked != null) setLS(() => paidAt = picked);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ingresa un monto válido')),
                  );
                  return;
                }
                try {
                  await ref
                      .read(contabilidadRepositoryProvider)
                      .updatePayablePayment(
                        id: payment.id,
                        amount: amount,
                        paidAt: paidAt,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                      );
                  if (!ctx.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('No se pudo actualizar: $e')),
                    );
                  }
                }
              },
              child: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
    if (done == true && mounted) {
      await _load();
      await _showSnack('Pago actualizado');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);

    if (!canUseModule) {
      return Scaffold(
        backgroundColor: MediaQuery.sizeOf(context).width < 900
            ? AppColors.background
            : null,
        appBar: CustomAppBar(title: 'Pagos pendientes', showLogo: false),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este módulo está disponible solo para usuarios autorizados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    final isAdmin = user?.appRole.isAdmin == true;
    final isMobile = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: isMobile ? AppColors.background : null,
      appBar: CustomAppBar(
        title: 'Pagos pendientes',
        showLogo: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab_fixed',
            onPressed: _openCreateFixedDialog,
            icon: const Icon(Icons.add_task_outlined),
            label: const Text('Servicio fijo'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'fab_direct',
            onPressed: _openDirectPaymentDialog,
            icon: const Icon(Icons.attach_money_outlined),
            label: const Text('Pago directo'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Stack(
          children: [
            Positioned.fill(
              child: _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _buildContent(context, isAdmin: isAdmin),
            ),
            if (_loading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, {required bool isAdmin}) {
    final active = _activeServices;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _SummaryPanel(
          totalEstimated: _totalEstimated,
          activeCount: active.length,
          overdueCount: _overdueCount,
          dueSoonCount: _dueSoonCount,
          money: _money,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Servicios activos (${active.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _SortMenu(
              current: _sortOrder,
              onSelect: (v) => setState(() => _sortOrder = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (active.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('No hay servicios pendientes activos.'),
                  ),
                ],
              ),
            ),
          )
        else
          ...active.map(
            (service) => _ServiceTile(
              key: ValueKey(service.id),
              service: service,
              money: _money,
              dateFmt: _dateFmt,
              isAdmin: isAdmin,
              onPay: () => _openRegisterPaymentDialog(service),
              onReceipt: () => _openMonthlyReceiptForService(service),
              onToggle: () => _toggleActive(service),
              onDelete: isAdmin ? () => _confirmDeleteService(service) : null,
            ),
          ),
        const SizedBox(height: 24),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _historyExpanded = !_historyExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Historial de pagos (${_payments.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _historyExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildHistory(context, isAdmin: isAdmin),
          crossFadeState: _historyExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  Widget _buildHistory(BuildContext context, {required bool isAdmin}) {
    if (_payments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Aún no hay pagos registrados.'),
      );
    }
    return Column(
      children: [
        const SizedBox(height: 8),
        ..._payments.take(30).map((payment) {
          final service = _findService(payment.serviceId);
          return _HistoryRow(
            payment: payment,
            service: service,
            money: _money,
            dateFmt: _dateFmt,
            isAdmin: isAdmin,
            onPdf: service == null
                ? null
                : () async {
                    final from = DateTime(
                      payment.paidAt.year,
                      payment.paidAt.month,
                      1,
                    );
                    final to = DateTime(
                      payment.paidAt.year,
                      payment.paidAt.month + 1,
                      0,
                      23,
                      59,
                      59,
                    );
                    final monthly = service.payments
                        .where(
                          (p) =>
                              !p.paidAt.isBefore(from) && !p.paidAt.isAfter(to),
                        )
                        .toList();
                    await _openReceiptPreview(
                      service: service,
                      payments: monthly,
                      from: from,
                      to: to,
                    );
                  },
            onEdit: isAdmin ? () => _openEditPaymentDialog(payment) : null,
            onDelete: isAdmin ? () => _confirmDeletePayment(payment) : null,
          );
        }),
      ],
    );
  }
}

// ── Summary Panel ─────────────────────────────────────────────────────────────

class _SummaryPanel extends StatelessWidget {
  final double totalEstimated;
  final int activeCount;
  final int overdueCount;
  final int dueSoonCount;
  final NumberFormat money;

  const _SummaryPanel({
    required this.totalEstimated,
    required this.activeCount,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESUMEN',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              money.format(totalEstimated),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Total estimado a pagar (servicios activos)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(
                  icon: Icons.list_alt_outlined,
                  label: '$activeCount activos',
                  color: scheme.onPrimaryContainer,
                  bg: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                ),
                if (overdueCount > 0)
                  _StatChip(
                    icon: Icons.warning_amber_rounded,
                    label:
                        '$overdueCount vencido${overdueCount > 1 ? "s" : ""}',
                    color: scheme.error,
                    bg: scheme.errorContainer,
                  ),
                if (dueSoonCount > 0)
                  _StatChip(
                    icon: Icons.schedule_rounded,
                    label:
                        '$dueSoonCount próximo${dueSoonCount > 1 ? "s" : ""} (7d)',
                    color: scheme.onPrimaryContainer,
                    bg: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sort menu ─────────────────────────────────────────────────────────────────

class _SortMenu extends StatelessWidget {
  final _SortOrder current;
  final ValueChanged<_SortOrder> onSelect;
  const _SortMenu({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortOrder>(
      tooltip: 'Ordenar',
      initialValue: current,
      onSelected: onSelect,
      itemBuilder: (_) => _SortOrder.values
          .map(
            (o) => PopupMenuItem(
              value: o,
              child: Row(
                children: [
                  Icon(
                    o == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(o.label),
                ],
              ),
            ),
          )
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.sort_rounded, size: 16),
        label: Text(current.label, style: const TextStyle(fontSize: 12)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatelessWidget {
  final PayableService service;
  final NumberFormat money;
  final DateFormat dateFmt;
  final bool isAdmin;
  final VoidCallback onPay;
  final VoidCallback onReceipt;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  const _ServiceTile({
    super.key,
    required this.service,
    required this.money,
    required this.dateFmt,
    required this.isAdmin,
    required this.onPay,
    required this.onReceipt,
    required this.onToggle,
    this.onDelete,
  });

  _DueStatus get _status {
    final now = DateTime.now();
    if (service.nextDueDate.isBefore(now)) return _DueStatus.overdue;
    if (service.nextDueDate.isBefore(now.add(const Duration(days: 7)))) {
      return _DueStatus.soon;
    }
    return _DueStatus.ok;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final status = _status;

    final statusColor = switch (status) {
      _DueStatus.overdue => scheme.error,
      _DueStatus.soon => const Color(0xFFB45309),
      _DueStatus.ok => scheme.primary,
    };
    final statusBg = switch (status) {
      _DueStatus.overdue => scheme.errorContainer,
      _DueStatus.soon => const Color(0xFFFEF3C7),
      _DueStatus.ok => scheme.primaryContainer,
    };
    final statusLabel = switch (status) {
      _DueStatus.overdue => 'Vencido',
      _DueStatus.soon => 'Próximo',
      _DueStatus.ok => 'Al día',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: status == _DueStatus.overdue
              ? scheme.error.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    service.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _MetaChip(
                  icon: Icons.person_outline_rounded,
                  label: service.providerName,
                ),
                _MetaChip(
                  icon: Icons.repeat_rounded,
                  label: service.frequency.label,
                ),
                _MetaChip(
                  icon: Icons.calendar_today_outlined,
                  label: dateFmt.format(service.nextDueDate),
                  color: statusColor,
                ),
                if (service.defaultAmount != null)
                  _MetaChip(
                    icon: Icons.payments_outlined,
                    label: money.format(service.defaultAmount),
                    bold: true,
                  ),
              ],
            ),
            if (service.lastPaidAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Último pago: ${dateFmt.format(service.lastPaidAt!)}',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onPay,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Pagar'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onReceipt,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: const Text('PDF'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Archivar',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggle,
                  icon: Icon(Icons.archive_outlined, color: scheme.outline),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Eliminar servicio',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool bold;
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg.withValues(alpha: 0.75)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: fg,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── History row ───────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final PayablePayment payment;
  final PayableService? service;
  final NumberFormat money;
  final DateFormat dateFmt;
  final VoidCallback? onPdf;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _HistoryRow({
    required this.payment,
    required this.service,
    required this.money,
    required this.dateFmt,
    required this.isAdmin,
    required this.onPdf,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: scheme.primary,
          ),
        ),
        title: Text(
          money.format(payment.amount),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${service?.title ?? "–"} · ${service?.providerName ?? "–"}\n${dateFmt.format(payment.paidAt)}',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPdf != null)
              IconButton(
                tooltip: 'Comprobante PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                onPressed: onPdf,
              ),
            if (isAdmin)
              IconButton(
                tooltip: 'Editar pago',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                onPressed: onEdit,
              ),
            if (isAdmin)
              IconButton(
                tooltip: 'Eliminar pago',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
