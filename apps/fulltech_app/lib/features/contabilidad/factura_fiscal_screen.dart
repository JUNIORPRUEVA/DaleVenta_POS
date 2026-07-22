import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/evolution/evolution_api_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/contabilidad_repository.dart';
import 'models/fiscal_invoice_model.dart';
import 'utils/fiscal_invoice_image_url.dart';
import 'utils/fiscal_invoices_pdf_service.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';

DateTimeRange _previousMonthRange([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  final currentMonthStart = DateTime(now.year, now.month, 1);
  final previousMonthEnd = currentMonthStart.subtract(const Duration(days: 1));
  final previousMonthStart = DateTime(
    previousMonthEnd.year,
    previousMonthEnd.month,
    1,
  );
  return DateTimeRange(start: previousMonthStart, end: previousMonthEnd);
}

const String _fiscalAccountantPhone = '8295319442';

class FacturaFiscalScreen extends ConsumerStatefulWidget {
  const FacturaFiscalScreen({super.key});

  @override
  ConsumerState<FacturaFiscalScreen> createState() =>
      _FacturaFiscalScreenState();
}

class _FacturaFiscalScreenState extends ConsumerState<FacturaFiscalScreen> {
  final _noteCtrl = TextEditingController();
  final _noteFocusNode = FocusNode();
  DateTime _invoiceDate = DateTime.now();
  FiscalInvoiceKind _kind = FiscalInvoiceKind.purchase;
  PlatformFile? _selectedFile;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteFocusNode.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  IconData _kindIcon(FiscalInvoiceKind kind) {
    switch (kind) {
      case FiscalInvoiceKind.saleCard:
        return Icons.credit_card_rounded;
      case FiscalInvoiceKind.sale:
        return Icons.trending_up_rounded;
      case FiscalInvoiceKind.purchase:
        return Icons.inventory_2_outlined;
    }
  }

  String _uploadButtonLabel(FiscalInvoiceKind kind, bool hasFile) {
    if (hasFile) return 'Cambiar imagen';
    switch (kind) {
      case FiscalInvoiceKind.saleCard:
        return 'Subir venta por tarjeta';
      case FiscalInvoiceKind.sale:
        return 'Subir venta';
      case FiscalInvoiceKind.purchase:
        return 'Subir compra';
    }
  }

  Future<void> _pickInvoiceDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _invoiceDate = picked);
  }

  Future<void> _pickInvoiceImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _selectedFile = result.files.first;
      _noteCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _noteFocusNode.requestFocus();
      }
    });
  }

  void _clearSelectedInvoice() {
    if (_saving) return;
    setState(() {
      _selectedFile = null;
      _noteCtrl.clear();
      _error = null;
    });
  }

  Future<void> _openHistoryScreen(BuildContext context) async {
    final defaultRange = _previousMonthRange();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FiscalInvoiceHistoryScreen(
          initialFrom: defaultRange.start,
          initialTo: defaultRange.end,
          initialKind: null,
        ),
      ),
    );
  }

  Future<void> _saveSelectedInvoice() async {
    final selectedFile = _selectedFile;
    if (selectedFile == null || _saving) return;

    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(contabilidadRepositoryProvider);
      final imageUrl = await repo.uploadFiscalInvoiceImage(selectedFile);
      await repo.createFiscalInvoice(
        kind: _kind,
        invoiceDate: _invoiceDate,
        imageUrl: imageUrl,
        note: _noteCtrl.text,
      );
      if (!mounted) return;

      setState(() {
        _saving = false;
        _selectedFile = null;
        _noteCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura fiscal guardada en la nube.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudo guardar la factura fiscal';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Factura fiscal',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Abrir historial',
            onPressed: () => _openHistoryScreen(context),
            icon: const Icon(Icons.history_outlined),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: !canUseModule
          ? const Center(
              child: Text(
                'Solo ADMIN y ASISTENTE tienen acceso completo a este módulo.',
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildUploadCard(context),
                    const SizedBox(height: 10),
                    if (_error != null) _ErrorBox(message: _error!),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildUploadCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 460;
    final selectedFile = _selectedFile;
    final dateLabel = DateFormat('dd/MM/yyyy').format(_invoiceDate);
    final hasFile = selectedFile != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.12),
                  scheme.secondary.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isNarrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderInfo(context),
                      const SizedBox(height: 12),
                      _buildDatePill(context, dateLabel),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildHeaderInfo(context)),
                      const SizedBox(width: 12),
                      _buildDatePill(context, dateLabel),
                    ],
                  ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_kindIcon(_kind), color: scheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kind.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _pickInvoiceImage,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_uploadButtonLabel(_kind, hasFile)),
                ),
                const SizedBox(height: 10),
                if (!hasFile)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 30,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sin imagen cargada',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedFile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar imagen',
                          onPressed: _saving ? null : _clearSelectedInvoice,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteCtrl,
                    focusNode: _noteFocusNode,
                    enabled: !_saving,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _saveSelectedInvoice(),
                    decoration: InputDecoration(
                      labelText: 'Observación o nota',
                      hintText:
                          'Describe brevemente esta factura para guardarla.',
                      suffixIcon: _saving
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 430;
                      final saveButton = FilledButton.icon(
                        onPressed: _saving ? null : _saveSelectedInvoice,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_done_outlined),
                        label: Text(
                          _saving ? 'Guardando...' : 'Guardar factura',
                        ),
                      );
                      final clearButton = OutlinedButton.icon(
                        onPressed: _saving ? null : _clearSelectedInvoice,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Quitar'),
                      );

                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            saveButton,
                            const SizedBox(height: 8),
                            clearButton,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: clearButton),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: saveButton),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final itemWidth = (constraints.maxWidth - (gap * 2)) / 3;
              final kinds = FiscalInvoiceKind.values;

              return Row(
                children: [
                  for (var index = 0; index < kinds.length; index++) ...[
                    SizedBox(
                      width: itemWidth,
                      child: _InvoiceKindOption(
                        label: kinds[index].label,
                        icon: _kindIcon(kinds[index]),
                        selected: _kind == kinds[index],
                        onTap: _saving
                            ? null
                            : () => setState(() => _kind = kinds[index]),
                      ),
                    ),
                    if (index != kinds.length - 1) const SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nueva factura fiscal',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildDatePill(BuildContext context, String dateLabel) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Cambiar fecha',
            onPressed: _saving ? null : () => _pickInvoiceDate(context),
            icon: const Icon(Icons.event_outlined),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final FiscalInvoiceModel item;

  const _InvoiceCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final note = item.note?.trim();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.kind.label} · ${dateFmt.format(item.invoiceDate)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                dateFmt.format(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _FiscalInvoiceImage(imageUrl: item.imageUrl),
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Nota: $note', style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 6),
          Text(
            'Registrado por: ${item.createdByName ?? item.createdById ?? 'N/D'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InvoiceKindOption extends StatelessWidget {
  const _InvoiceKindOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
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

class _FiscalInvoiceImage extends StatelessWidget {
  final String imageUrl;

  const _FiscalInvoiceImage({required this.imageUrl});

  String _resolvedUrl() {
    return resolveFiscalInvoiceImageUrl(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl();
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 6),
          Text(
            'Imagen no disponible',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );

    if (url.isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

class _FiscalInvoiceHistoryScreen extends ConsumerStatefulWidget {
  const _FiscalInvoiceHistoryScreen({
    required this.initialFrom,
    required this.initialTo,
    required this.initialKind,
  });

  final DateTime initialFrom;
  final DateTime initialTo;
  final FiscalInvoiceKind? initialKind;

  @override
  ConsumerState<_FiscalInvoiceHistoryScreen> createState() =>
      _FiscalInvoiceHistoryScreenState();
}

class _FiscalInvoiceHistoryScreenState
    extends ConsumerState<_FiscalInvoiceHistoryScreen> {
  late DateTime _from = widget.initialFrom;
  late DateTime _to = widget.initialTo;
  FiscalInvoiceKind? _kindFilter;
  bool _loading = true;
  bool _sendingPreviousMonthReport = false;
  String? _error;
  List<FiscalInvoiceModel> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _kindFilter = widget.initialKind;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(contabilidadRepositoryProvider)
          .listFiscalInvoices(from: _from, to: _to, kind: _kindFilter);
      if (!mounted) return;
      setState(() {
        _invoices = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudo cargar el historial fiscal';
      });
    }
  }

  Future<void> _sendPreviousMonthReport(BuildContext context) async {
    if (_sendingPreviousMonthReport) return;

    final messenger = ScaffoldMessenger.of(context);
    final range = _previousMonthRange();

    setState(() {
      _sendingPreviousMonthReport = true;
      _error = null;
    });

    try {
      final invoices = await ref
          .read(contabilidadRepositoryProvider)
          .listFiscalInvoices(from: range.start, to: range.end);
      if (invoices.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No hay facturas fiscales en el mes pasado.'),
          ),
        );
        return;
      }

      final bytes = await buildFiscalInvoicesPdf(
        from: range.start,
        to: range.end,
        invoices: invoices,
      );
      await _sendReportToAccountant(
        bytes: bytes,
        from: range.start,
        to: range.end,
        successMessage: 'Reporte del mes pasado enviado al contable.',
      );

      if (!mounted) return;
      messenger.clearSnackBars();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo enviar el reporte del mes pasado';
      });
    } finally {
      if (mounted) {
        setState(() => _sendingPreviousMonthReport = false);
      }
    }
  }

  Future<void> _openPdfDialog(
    BuildContext context,
    Uint8List bytes, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (bytes.isEmpty) {
      _showScreenError('No se pudo generar el PDF.');
      return;
    }

    final filename = _reportFileName(from, to);

    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (_) {
          var sending = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('PDF facturas fiscales'),
              content: const Text(
                'El PDF fue generado. En web se abre sin vista previa para evitar bloqueos del visor.',
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                FilledButton.icon(
                  onPressed: sending
                      ? null
                      : () async {
                          setDialogState(() => sending = true);
                          try {
                            await _sendReportToAccountant(
                              bytes: bytes,
                              from: from,
                              to: to,
                              successMessage:
                                  'Reporte del filtro enviado al contable.',
                            );
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => sending = false);
                            }
                          }
                        },
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Enviar al contable'),
                ),
                FilledButton.icon(
                  onPressed: sending
                      ? null
                      : () async {
                          try {
                            await Printing.sharePdf(
                              bytes: bytes,
                              filename: filename,
                            );
                          } catch (e) {
                            if (!mounted) return;
                            _showScreenError(
                              'No se pudo descargar o compartir el PDF: $e',
                            );
                          }
                        },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Descargar'),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) {
        var sending = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 960,
              height: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'PDF facturas fiscales',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: sending
                              ? null
                              : () async {
                                  setDialogState(() => sending = true);
                                  try {
                                    await _sendReportToAccountant(
                                      bytes: bytes,
                                      from: from,
                                      to: to,
                                      successMessage:
                                          'Reporte del filtro enviado al contable.',
                                    );
                                  } finally {
                                    if (context.mounted) {
                                      setDialogState(() => sending = false);
                                    }
                                  }
                                },
                          icon: sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: const Text('Enviar al contable'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Descargar / compartir',
                          onPressed: sending
                              ? null
                              : () async {
                                  try {
                                    await Printing.sharePdf(
                                      bytes: bytes,
                                      filename: filename,
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    _showScreenError(
                                      'No se pudo descargar o compartir el PDF: $e',
                                    );
                                  }
                                },
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          onPressed: sending
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PdfPreview(
                      canChangePageFormat: false,
                      canDebug: false,
                      allowPrinting: true,
                      allowSharing: true,
                      build: (_) async => bytes,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _reportFileName(DateTime from, DateTime to) {
    final fromStamp = DateFormat('yyyyMMdd').format(from);
    final toStamp = DateFormat('yyyyMMdd').format(to);
    return 'facturas_fiscales_${fromStamp}_$toStamp.pdf';
  }

  String _reportCaption(DateTime from, DateTime to) {
    return 'Reporte de facturas fiscales del ${DateFormat('dd/MM/yyyy').format(from)} al ${DateFormat('dd/MM/yyyy').format(to)}.';
  }

  Future<void> _sendReportToAccountant({
    required Uint8List bytes,
    required DateTime from,
    required DateTime to,
    required String successMessage,
  }) async {
    await ref
        .read(evolutionApiRepositoryProvider)
        .sendPdfDocument(
          toNumber: _fiscalAccountantPhone,
          bytes: bytes,
          fileName: _reportFileName(from, to),
          caption: _reportCaption(from, to),
        );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final previousRange = _previousMonthRange();
    final monthLabel = DateFormat(
      'MMMM yyyy',
      'es_DO',
    ).format(previousRange.start);

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Historial fiscal',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle(
                    title: 'Historial de facturas',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_invoices.length} registros',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(_from)} - ${DateFormat('dd/MM/yyyy').format(_to)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Las imagenes cargadas aparecen aqui y el PDF se genera segun el filtro aplicado.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2100),
                            initialDateRange: DateTimeRange(
                              start: _from,
                              end: _to,
                            ),
                          );
                          if (range == null) return;
                          setState(() {
                            _from = range.start;
                            _to = range.end;
                          });
                          await _load();
                        },
                        icon: const Icon(Icons.date_range_outlined),
                        label: const Text('Intervalo de fecha'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final range = _previousMonthRange();
                          setState(() {
                            _from = range.start;
                            _to = range.end;
                            _kindFilter = null;
                          });
                          await _load();
                        },
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('Mes pasado'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _invoices.isEmpty
                            ? null
                            : () async {
                                try {
                                  final bytes = await buildFiscalInvoicesPdf(
                                    from: _from,
                                    to: _to,
                                    invoices: _invoices,
                                  );
                                  if (!context.mounted) return;
                                  await _openPdfDialog(
                                    context,
                                    bytes,
                                    from: _from,
                                    to: _to,
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  _showScreenError(
                                    'No se pudo generar el PDF del filtro: $e',
                                  );
                                }
                              },
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF del filtro'),
                      ),
                      FilledButton.icon(
                        onPressed: _sendingPreviousMonthReport
                            ? null
                            : () => _sendPreviousMonthReport(context),
                        icon: _sendingPreviousMonthReport
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text('Enviar $monthLabel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tipo de factura',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _kindFilter == null,
                        onSelected: (_) async {
                          setState(() => _kindFilter = null);
                          await _load();
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Ventas por tarjeta'),
                        selected: _kindFilter == FiscalInvoiceKind.saleCard,
                        onSelected: (_) async {
                          setState(
                            () => _kindFilter = FiscalInvoiceKind.saleCard,
                          );
                          await _load();
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Compras'),
                        selected: _kindFilter == FiscalInvoiceKind.purchase,
                        onSelected: (_) async {
                          setState(
                            () => _kindFilter = FiscalInvoiceKind.purchase,
                          );
                          await _load();
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Ventas'),
                        selected: _kindFilter == FiscalInvoiceKind.sale,
                        onSelected: (_) async {
                          setState(() => _kindFilter = FiscalInvoiceKind.sale);
                          await _load();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 8),
            ..._invoices.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InvoiceCard(item: item),
              ),
            ),
            if (!_loading && _invoices.isEmpty)
              const AppCard(
                child: Text(
                  'No hay facturas fiscales en el rango seleccionado.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showScreenError(String message) {
    setState(() {
      _error = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
