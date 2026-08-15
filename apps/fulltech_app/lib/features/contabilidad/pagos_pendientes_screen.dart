import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
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

  void _showSummary() {
    final active = _activeServices;
    final overdue = _overdueCount;
    final dueSoon = _dueSoonCount;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resumen de pagos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _PaymentSummaryStat(
                label: 'Total estimado a pagar',
                value: _money.format(_totalEstimated),
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 8),
              _PaymentSummaryStat(
                label: 'Servicios activos',
                value: '${active.length}',
                icon: Icons.list_alt_outlined,
              ),
              const SizedBox(height: 8),
              _PaymentSummaryStat(
                label: 'Vencidos',
                value: '$overdue',
                icon: Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 8),
              _PaymentSummaryStat(
                label: 'Próximos (7 días)',
                value: '$dueSoon',
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    final result = await showGeneralDialog<_PagosOptionsResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros y opciones de pagos',
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _PagosOptionsSheet(initialSort: _sortOrder),
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
    if (result == null || !mounted) return;
    if (result.sort != _sortOrder) {
      setState(() => _sortOrder = result.sort);
    }
    switch (result.action) {
      case _PagosSheetAction.createFixed:
        await _openCreateFixedDialog();
        break;
      case _PagosSheetAction.directPayment:
        await _openDirectPaymentDialog();
        break;
      case _PagosSheetAction.none:
        break;
    }
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
    final canUseModule = hasUserPermission(user, AppPermission.viewAccounting);

    if (!canUseModule) {
      return Scaffold(
        backgroundColor: MediaQuery.sizeOf(context).width < 900
            ? AppColors.background
            : null,
        appBar: CustomAppBar(
          title: 'Pagos pendientes',
          showLogo: false,
          showDepartmentLabel: false,
          trailing: const SizedBox.shrink(),
        ),
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
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final isMobile = !isDesktop;
    final active = _activeServices;
    final overdue = _overdueCount;
    final dueSoon = _dueSoonCount;

    return Scaffold(
      backgroundColor: isDesktop ? desktopSalesSurface : AppColors.background,
      appBar: isDesktop
          ? FullTechPageHeader(
              title: 'Pagos pendientes',
              actions: [
                _PaymentsHeaderBadge(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Activos',
                  value: '${active.length}',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Filtros y opciones',
                  onPressed: _openFilters,
                  icon: const Icon(Icons.filter_alt_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _loading ? 'Actualizando...' : 'Actualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openCreateFixedDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agregar'),
                ),
                const SizedBox(width: 12),
              ],
            )
          : CustomAppBar(
              title: 'Pagos pendientes',
              showLogo: false,
              showDepartmentLabel: false,
              actions: [
                IconButton(
                  tooltip: 'Filtros y opciones',
                  onPressed: _openFilters,
                  icon: const Icon(Icons.filter_alt_outlined),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
              trailing: const SizedBox.shrink(),
            ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              heroTag: 'payments_summary',
              tooltip: 'Ver resumen',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              onPressed: _showSummary,
              child: const Icon(Icons.summarize_rounded),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: isDesktop
            ? DesktopSalesFrame(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _PaymentsListPane(
                          loading: _loading,
                          child: _error != null
                              ? _ErrorView(message: _error!, onRetry: _load)
                              : _buildContent(context, isAdmin: isAdmin),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: (width * 0.30).clamp(360.0, 460.0),
                      child: _PaymentsFixedInfoColumn(
                        totalEstimated: _totalEstimated,
                        activeCount: active.length,
                        overdueCount: overdue,
                        dueSoonCount: dueSoon,
                        historyCount: _payments.length,
                        money: _money,
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
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
        Text(
          'Servicios activos (${active.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
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

class _PaymentsListPane extends StatelessWidget {
  const _PaymentsListPane({required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _PaymentsHeaderBadge extends StatelessWidget {
  const _PaymentsHeaderBadge({
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
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: desktopSalesAccent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: desktopSalesMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: desktopSalesText,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsFixedInfoColumn extends StatelessWidget {
  const _PaymentsFixedInfoColumn({
    required this.totalEstimated,
    required this.activeCount,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.historyCount,
    required this.money,
  });

  final double totalEstimated;
  final int activeCount;
  final int overdueCount;
  final int dueSoonCount;
  final int historyCount;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return DesktopSalesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Resumen',
            style: TextStyle(
              color: desktopSalesText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _PaymentSummaryStat(
            label: 'Total estimado',
            value: money.format(totalEstimated),
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 8),
          _PaymentSummaryStat(
            label: 'Servicios activos',
            value: '$activeCount',
            icon: Icons.list_alt_outlined,
          ),
          const SizedBox(height: 8),
          _PaymentSummaryStat(
            label: 'Vencidos',
            value: '$overdueCount',
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 8),
          _PaymentSummaryStat(
            label: 'Próximos 7 días',
            value: '$dueSoonCount',
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(height: 8),
          _PaymentSummaryStat(
            label: 'Historial',
            value: '$historyCount',
            icon: Icons.history_outlined,
          ),
        ],
      ),
    );
  }
}

class _PaymentSummaryStat extends StatelessWidget {
  const _PaymentSummaryStat({
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
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

enum _PagosSheetAction { none, createFixed, directPayment }

class _PagosOptionsResult {
  const _PagosOptionsResult({
    required this.sort,
    this.action = _PagosSheetAction.none,
  });

  final _SortOrder sort;
  final _PagosSheetAction action;
}

class _PagosOptionsSheet extends StatefulWidget {
  const _PagosOptionsSheet({required this.initialSort});

  final _SortOrder initialSort;

  @override
  State<_PagosOptionsSheet> createState() => _PagosOptionsSheetState();
}

class _PagosOptionsSheetState extends State<_PagosOptionsSheet> {
  late _SortOrder _sort = widget.initialSort;

  void _apply() {
    Navigator.of(
      context,
    ).pop(_PagosOptionsResult(sort: _sort, action: _PagosSheetAction.none));
  }

  void _runAction(_PagosSheetAction action) {
    Navigator.of(context).pop(_PagosOptionsResult(sort: _sort, action: action));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width * 0.85).clamp(340.0, 540.0);

    return Dismissible(
      key: const ValueKey('pagos-options-panel'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Material(
        color: Colors.white,
        elevation: 18,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: media.height,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.filter_alt_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtros y opciones',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Orden y acciones rápidas',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    children: [
                      _PagosFilterSection<_SortOrder>(
                        title: 'Ordenar',
                        value: _sort,
                        options: _SortOrder.values,
                        labelBuilder: (order) => order.label,
                        onSelected: (value) {
                          setState(() => _sort = value);
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Acciones',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PagosActionTile(
                        icon: Icons.add_task_outlined,
                        label: 'Nuevo servicio fijo',
                        onTap: () => _runAction(_PagosSheetAction.createFixed),
                      ),
                      const SizedBox(height: 8),
                      _PagosActionTile(
                        icon: Icons.attach_money_outlined,
                        label: 'Pago directo',
                        onTap: () =>
                            _runAction(_PagosSheetAction.directPayment),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceAlt,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              const _PagosOptionsResult(
                                sort: _SortOrder.dueDateAsc,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: const Text('Limpiar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _apply,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Aplicar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
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
      ),
    );
  }
}

class _PagosFilterSection<T> extends StatelessWidget {
  const _PagosFilterSection({
    required this.title,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (var index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              Material(
                color: options[index] == value
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.25,
                      ),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSelected(options[index]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          options[index] == value
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 18,
                          color: options[index] == value
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labelBuilder(options[index]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: options[index] == value
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PagosActionTile extends StatelessWidget {
  const _PagosActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
