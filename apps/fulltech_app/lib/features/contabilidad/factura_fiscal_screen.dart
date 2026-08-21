import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/evolution/evolution_api_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
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

DateTimeRange _currentMonthRange([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(
    now.year,
    now.month + 1,
    1,
  ).subtract(const Duration(days: 1));
  return DateTimeRange(start: start, end: end);
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
  List<PlatformFile> _selectedFiles = const [];
  List<NcfSequenceModel> _ncfSequences = const [];
  bool _saving = false;
  bool _loadingSequences = false;
  bool _sequenceDialogOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadNcfSequences());
  }

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
    if (hasFile) return 'Cambiar archivos';
    switch (kind) {
      case FiscalInvoiceKind.saleCard:
        return 'Subir ventas por tarjeta';
      case FiscalInvoiceKind.sale:
        return 'Subir ventas';
      case FiscalInvoiceKind.purchase:
        return 'Subir compras';
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
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final readableFiles = result.files
        .where((file) => file.bytes != null && file.bytes!.isNotEmpty)
        .toList(growable: false);
    if (readableFiles.isEmpty) {
      setState(() {
        _error = 'No se pudo leer ninguno de los archivos seleccionados.';
      });
      return;
    }
    setState(() {
      _selectedFiles = readableFiles;
      _noteCtrl.clear();
      _error = null;
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
      _selectedFiles = const [];
      _noteCtrl.clear();
      _error = null;
    });
  }

  Future<void> _openHistoryScreen(BuildContext context) async {
    final defaultRange = _currentMonthRange();
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
    final selectedFiles = _selectedFiles;
    if (selectedFiles.isEmpty || _saving) return;

    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(contabilidadRepositoryProvider);
      for (final selectedFile in selectedFiles) {
        final imageUrl = await repo.uploadFiscalInvoiceImage(selectedFile);
        await repo.createFiscalInvoice(
          kind: _kind,
          invoiceDate: _invoiceDate,
          imageUrl: imageUrl,
          note: _noteForFile(selectedFile, selectedFiles.length),
        );
      }
      if (!mounted) return;

      setState(() {
        _saving = false;
        _selectedFiles = const [];
        _noteCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedFiles.length == 1
                ? 'Factura fiscal guardada en la nube.'
                : '${selectedFiles.length} facturas fiscales guardadas en la nube.',
          ),
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () => _openHistoryScreen(context),
          ),
        ),
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

  String? _noteForFile(PlatformFile file, int totalFiles) {
    final note = _noteCtrl.text.trim();
    if (totalFiles <= 1) return note.isEmpty ? null : note;
    final fileName = file.name.trim();
    final parts = [
      if (note.isNotEmpty) note,
      if (fileName.isNotEmpty) 'Archivo: $fileName',
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  Future<void> _reloadNcfSequences() async {
    if (_loadingSequences) return;
    setState(() => _loadingSequences = true);
    try {
      final rows = await ref
          .read(contabilidadRepositoryProvider)
          .listNcfSequences();
      if (!mounted) return;
      setState(() {
        _ncfSequences = rows;
        _loadingSequences = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSequences = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudieron cargar las secuencias NCF';
      });
    }
  }

  void _showSequenceError(Object e, String fallback) {
    final message = e is ApiException ? e.message : fallback;
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openCreateSequenceDialog() async {
    if (_sequenceDialogOpen) return;
    _sequenceDialogOpen = true;
    try {
      final result = await showDialog<_NcfSequenceFormResult>(
        context: context,
        builder: (_) => const _NcfSequenceDialog(),
      );
      if (result == null || !mounted) return;
      try {
        await ref.read(contabilidadRepositoryProvider).createNcfSequence(
              voucherType: result.voucherType,
              startNumber: result.startNumber,
              endNumber: result.endNumber,
              validUntil: result.validUntil,
              active: result.active,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Secuencia ${result.voucherType} creada.'),
          ),
        );
        await _reloadNcfSequences();
      } catch (e) {
        if (!mounted) return;
        _showSequenceError(e, 'No se pudo crear la secuencia NCF');
      }
    } finally {
      _sequenceDialogOpen = false;
    }
  }

  Future<void> _openEditSequenceDialog(NcfSequenceModel sequence) async {
    if (_sequenceDialogOpen) return;
    _sequenceDialogOpen = true;
    try {
      final result = await showDialog<_NcfSequenceFormResult>(
        context: context,
        builder: (_) => _NcfSequenceDialog(sequence: sequence),
      );
      if (result == null || !mounted) return;
      try {
        await ref
            .read(contabilidadRepositoryProvider)
            .updateNcfSequence(
              sequence.id,
              endNumber: result.endNumber,
              validUntil: result.validUntil,
              active: result.active,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Secuencia ${sequence.voucherType} actualizada.'),
          ),
        );
        await _reloadNcfSequences();
      } catch (e) {
        if (!mounted) return;
        _showSequenceError(e, 'No se pudo actualizar la secuencia NCF');
      }
    } finally {
      _sequenceDialogOpen = false;
    }
  }

  Future<void> _toggleSequenceActive(NcfSequenceModel sequence) async {
    if (_sequenceDialogOpen) return;
    _sequenceDialogOpen = true;
    try {
      final targetActive = !sequence.active;
      try {
        await ref
            .read(contabilidadRepositoryProvider)
            .updateNcfSequence(sequence.id, active: targetActive);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetActive
                  ? 'Secuencia ${sequence.voucherType} activada.'
                  : 'Secuencia ${sequence.voucherType} desactivada.',
            ),
          ),
        );
        await _reloadNcfSequences();
      } catch (e) {
        if (!mounted) return;
        _showSequenceError(e, 'No se pudo cambiar el estado de la secuencia NCF');
      }
    } finally {
      _sequenceDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = hasUserPermission(user, AppPermission.viewAccounting);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final fiscalContent = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? double.infinity : double.infinity,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 16 : 4,
            16,
            isDesktop ? 16 : 4,
            24,
          ),
          children: [
            _buildFiscalConfigCard(context),
            const SizedBox(height: 10),
            _buildUploadCard(context),
            const SizedBox(height: 10),
            if (_error != null) _ErrorBox(message: _error!),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: isDesktop ? desktopSalesSurface : AppColors.background,
      appBar: isDesktop
          ? FullTechPageHeader(
              title: 'Factura fiscal',
              actions: [
                _FiscalHeaderBadge(
                  icon: Icons.receipt_long_outlined,
                  label: 'Archivos',
                  value: '${_selectedFiles.length}',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Abrir historial',
                  onPressed: () => _openHistoryScreen(context),
                  icon: const Icon(Icons.history_outlined),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _pickInvoiceImage,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agregar'),
                ),
                const SizedBox(width: 12),
              ],
            )
          : CustomAppBar(
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
          : isDesktop
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
                      child: fiscalContent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: (width * 0.30).clamp(360.0, 460.0),
                    child: _FiscalFixedInfoColumn(
                      kindLabel: _kind.label,
                      filesCount: _selectedFiles.length,
                      invoiceDate: _invoiceDate,
                      ncfEnabled:
                          ref.watch(companySettingsProvider).valueOrNull
                                  ?.ncfEnabled ??
                              false,
                      companyLoading:
                          ref.watch(companySettingsProvider).isLoading,
                      saving: _saving,
                      onAdd: _pickInvoiceImage,
                      onSave: _selectedFiles.isEmpty || _saving
                          ? null
                          : _saveSelectedInvoice,
                      onHistory: () => _openHistoryScreen(context),
                    ),
                  ),
                ],
              ),
            )
          : fiscalContent,
    );
  }

  Widget _buildFiscalConfigCard(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final companyAsync = ref.watch(companySettingsProvider);

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompanyFiscalDataBlock(companyAsync: companyAsync),
          const SizedBox(height: 18),
          Text(
            'Secuencias NCF',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El NCF real se asigna al emitir la venta desde el backend. Aquí administras los rangos autorizados por tipo de comprobante.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _FiscalSequenceInfoPanel(
            sequences: _ncfSequences,
            loading: _loadingSequences,
            onRefresh: _reloadNcfSequences,
            onAdd: _openCreateSequenceDialog,
            onEdit: _openEditSequenceDialog,
            onToggle: _toggleSequenceActive,
          ),
        ],
      ),
    );
    return isMobile ? content : AppCard(child: content);
  }

  Widget _buildUploadCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 460;
    final selectedFiles = _selectedFiles;
    final dateLabel = DateFormat('dd/MM/yyyy').format(_invoiceDate);
    final hasFile = selectedFiles.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
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
              Text(
                'Tipo de comprobante',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _FiscalKindSelector(
                kinds: FiscalInvoiceKind.values,
                selected: _kind,
                iconFor: _kindIcon,
                onChanged: _saving
                    ? null
                    : (kind) => setState(() => _kind = kind),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _pickInvoiceImage,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(_uploadButtonLabel(_kind, hasFile)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(190, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!hasFile)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 22,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sin archivos cargados',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Selecciona foto o PDF',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
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
                          selectedFiles.length == 1
                              ? selectedFiles.first.name
                              : '${selectedFiles.length} archivos seleccionados',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar archivos',
                        onPressed: _saving ? null : _clearSelectedInvoice,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (selectedFiles.length > 1) ...[
                  const SizedBox(height: 8),
                  ...selectedFiles.map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _SelectedFiscalFileChip(file: file),
                    ),
                  ),
                ],
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_done_outlined),
                      label: Text(_saving ? 'Guardando...' : 'Guardar factura'),
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
      ],
    );
    return isNarrow ? content : AppCard(child: content);
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

class _FiscalHeaderBadge extends StatelessWidget {
  const _FiscalHeaderBadge({
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

class _FiscalFixedInfoColumn extends StatelessWidget {
  const _FiscalFixedInfoColumn({
    required this.kindLabel,
    required this.filesCount,
    required this.invoiceDate,
    required this.ncfEnabled,
    required this.companyLoading,
    required this.saving,
    required this.onAdd,
    required this.onSave,
    required this.onHistory,
  });

  final String kindLabel;
  final int filesCount;
  final DateTime invoiceDate;
  final bool ncfEnabled;
  final bool companyLoading;
  final bool saving;
  final VoidCallback onAdd;
  final VoidCallback? onSave;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return DesktopSalesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Resumen',
            style: TextStyle(
              color: desktopSalesText,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          _FiscalSideStat(
            icon: Icons.category_outlined,
            label: 'Tipo',
            value: kindLabel,
          ),
          const SizedBox(height: 8),
          _FiscalSideStat(
            icon: Icons.attach_file_outlined,
            label: 'Archivos seleccionados',
            value: '$filesCount',
          ),
          const SizedBox(height: 8),
          _FiscalSideStat(
            icon: Icons.event_outlined,
            label: 'Fecha',
            value: dateFmt.format(invoiceDate),
          ),
          const SizedBox(height: 8),
          _FiscalSideStat(
            icon: Icons.fact_check_outlined,
            label: 'Comprobantes fiscales',
            value: companyLoading
                ? 'Cargando'
                : (ncfEnabled ? 'Activados' : 'Desactivados'),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.history_outlined),
            label: const Text('Historial'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: saving ? null : onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando...' : 'Guardar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _FiscalSideStat extends StatelessWidget {
  const _FiscalSideStat({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: desktopSalesLine),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: desktopSalesAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: desktopSalesMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: desktopSalesText,
                    fontSize: 14,
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

class _FiscalKindSelector extends StatelessWidget {
  const _FiscalKindSelector({
    required this.kinds,
    required this.selected,
    required this.iconFor,
    required this.onChanged,
  });

  final List<FiscalInvoiceKind> kinds;
  final FiscalInvoiceKind selected;
  final IconData Function(FiscalInvoiceKind kind) iconFor;
  final ValueChanged<FiscalInvoiceKind>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final children = [
          for (final kind in kinds)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FiscalKindChip(
                  kind: kind,
                  icon: iconFor(kind),
                  selected: selected == kind,
                  onTap: onChanged == null ? null : () => onChanged!(kind),
                ),
              ),
            ),
        ];

        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in kinds)
                SizedBox(
                  width: (constraints.maxWidth - 8) / 2,
                  child: _FiscalKindChip(
                    kind: kind,
                    icon: iconFor(kind),
                    selected: selected == kind,
                    onTap: onChanged == null ? null : () => onChanged!(kind),
                  ),
                ),
            ],
          );
        }

        return Row(children: children);
      },
    );
  }
}

class _FiscalKindChip extends StatelessWidget {
  const _FiscalKindChip({
    required this.kind,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final FiscalInvoiceKind kind;
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
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.10)
                : scheme.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedFiscalFileChip extends StatelessWidget {
  const _SelectedFiscalFileChip({required this.file});

  final PlatformFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ext = (file.extension ?? '').trim().toLowerCase();
    final isPdf = ext == 'pdf';
    final sizeKb = file.size <= 0 ? null : (file.size / 1024).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (sizeKb != null) ...[
            const SizedBox(width: 8),
            Text(
              '${sizeKb}KB',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FiscalSequenceRow extends StatelessWidget {
  const _FiscalSequenceRow({
    required this.sequence,
    required this.onEdit,
    required this.onToggle,
  });

  final NcfSequenceModel sequence;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = sequence.status.trim().isEmpty
        ? (sequence.active ? 'ACTIVE' : 'DISABLED')
        : sequence.status.trim().toUpperCase();
    final dueLabel = sequence.validUntil == null
        ? 'Sin vencimiento'
        : DateFormat('dd/MM/yyyy').format(sequence.validUntil!);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD3E0E7)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 680;
          final titleWidget = SizedBox(
            width: narrow ? double.infinity : 178,
            child: Text(
              '${sequence.voucherType} - ${_voucherTypeLabel(sequence.voucherType)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          );
          final fields = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FiscalSequenceMetric(
                label: 'Desde',
                value: '${sequence.startNumber}',
              ),
              _FiscalSequenceMetric(
                label: 'Hasta',
                value: '${sequence.endNumber}',
              ),
              _FiscalSequenceMetric(
                label: 'Actual',
                value: '${sequence.nextNumber}',
              ),
              _FiscalSequenceMetric(
                label: 'Disponibles',
                value: '${sequence.remaining}',
              ),
              _FiscalSequenceMetric(label: 'Estado', value: status),
              _FiscalSequenceMetric(label: 'Vence', value: dueLabel),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar secuencia',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: scheme.primary,
              ),
              IconButton(
                tooltip: sequence.active
                    ? 'Desactivar secuencia'
                    : 'Activar secuencia',
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
                icon: Icon(
                  sequence.active
                      ? Icons.toggle_on_rounded
                      : Icons.toggle_off_rounded,
                  size: 24,
                ),
                color: sequence.active ? scheme.primary : scheme.outline,
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: titleWidget),
                    actions,
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Próximo número disponible: ${sequence.possibleNextNcf}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                fields,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              const SizedBox(width: 10),
              Expanded(child: fields),
              const SizedBox(width: 6),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _FiscalSequenceInfoPanel extends StatelessWidget {
  const _FiscalSequenceInfoPanel({
    required this.sequences,
    required this.loading,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final List<NcfSequenceModel> sequences;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final void Function(NcfSequenceModel sequence) onEdit;
  final void Function(NcfSequenceModel sequence) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading && sequences.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF7D070)),
          ),
          child: Text(
            'El próximo número es solo referencia administrativa; el NCF real se asigna al emitir la venta desde el backend.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7A4B00),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (sequences.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD3E0E7)),
            ),
            child: Text(
              'No hay secuencias NCF configuradas en el backend.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        else
          for (final sequence in sequences) ...[
            _FiscalSequenceRow(
              sequence: sequence,
              onEdit: () => onEdit(sequence),
              onToggle: () => onToggle(sequence),
            ),
            if (sequence != sequences.last) const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualizar'),
            ),
            FilledButton.icon(
              onPressed: loading ? null : onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar secuencia'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FiscalSequenceMetric extends StatelessWidget {
  const _FiscalSequenceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _voucherTypeLabel(String type) {
  switch (type.trim().toUpperCase()) {
    case 'B01':
      return 'Crédito fiscal';
    case 'B02':
      return 'Consumidor final';
    default:
      return 'Comprobante fiscal';
  }
}

class _CompanyFiscalDataBlock extends StatelessWidget {
  const _CompanyFiscalDataBlock({required this.companyAsync});

  final AsyncValue<CompanySettings> companyAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = companyAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.business_outlined,
                color: Color(0xFF1957E6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Datos fiscales de empresa',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Se leen de la configuración de la empresa (fuente única).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.configuracionEmpresa),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (settings == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _CompanyFiscalRow(label: 'RNC emisor', value: settings.rnc),
          _CompanyFiscalRow(
            label: 'Razón social / Nombre comercial',
            value: settings.companyName,
          ),
          _CompanyFiscalRow(
            label: 'Representante legal',
            value: settings.legalRepresentativeName,
          ),
          _CompanyFiscalRow(label: 'Dirección fiscal', value: settings.address),
          _CompanyFiscalRow(label: 'Teléfono', value: settings.phone),
          if (!settings.ncfEnabled) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF7D070)),
              ),
              child: Text(
                'Los comprobantes fiscales (NCF) están desactivados. Actívalos en Configuración de empresa → Impuestos y comprobantes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7A4B00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CompanyFiscalRow extends StatelessWidget {
  const _CompanyFiscalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: display == '—' ? theme.colorScheme.outline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NcfSequenceFormResult {
  const _NcfSequenceFormResult({
    required this.voucherType,
    required this.startNumber,
    required this.endNumber,
    required this.validUntil,
    required this.active,
  });

  final String voucherType;
  final int startNumber;
  final int endNumber;
  final DateTime? validUntil;
  final bool active;
}

class _NcfSequenceDialog extends StatefulWidget {
  const _NcfSequenceDialog({this.sequence});

  final NcfSequenceModel? sequence;

  @override
  State<_NcfSequenceDialog> createState() => _NcfSequenceDialogState();
}

class _NcfSequenceDialogState extends State<_NcfSequenceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _voucherType;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  DateTime? _validUntil;
  late bool _active;
  bool _submitting = false;

  bool get _isEditing => widget.sequence != null;

  @override
  void initState() {
    super.initState();
    final sequence = widget.sequence;
    _voucherType = sequence?.voucherType ?? 'B01';
    _startCtrl = TextEditingController(
      text: '${sequence?.startNumber ?? 1}',
    );
    _endCtrl = TextEditingController(
      text: '${sequence?.endNumber ?? 100000}',
    );
    _validUntil = sequence?.validUntil;
    _active = sequence?.active ?? true;
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: 'Vencimiento de la secuencia',
    );
    if (picked == null) return;
    setState(
      () => _validUntil = DateTime(
        picked.year,
        picked.month,
        picked.day,
        23,
        59,
        59,
      ),
    );
  }

  void _submit() {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final start = int.tryParse(_startCtrl.text.trim()) ?? 1;
    final end = int.tryParse(_endCtrl.text.trim()) ?? 0;
    if (end < start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El número final no puede ser menor que el número inicial.',
          ),
        ),
      );
      return;
    }
    _submitting = true;
    Navigator.of(
      context,
    ).pop(
      _NcfSequenceFormResult(
        voucherType: _voucherType,
        startNumber: start,
        endNumber: end,
        validUntil: _validUntil,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = _isEditing;
    final sequence = widget.sequence;
    return AlertDialog(
      title: Text(
        isEditing ? 'Editar secuencia NCF' : 'Agregar secuencia NCF',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _voucherType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de comprobante',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'B01',
                    child: Text('B01 - Crédito fiscal'),
                  ),
                  DropdownMenuItem(
                    value: 'B02',
                    child: Text('B02 - Consumidor final'),
                  ),
                ],
                onChanged: isEditing
                    ? null
                    : (value) =>
                          setState(() => _voucherType = value ?? 'B01'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _startCtrl,
                enabled: !isEditing,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Número inicial',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed < 1) {
                    return 'Número inicial inválido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Número final',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed < 1) {
                    return 'Número final inválido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickValidUntil,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _validUntil == null
                      ? 'Sin vencimiento'
                      : 'Vence: ${DateFormat('dd/MM/yyyy').format(_validUntil!)}',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Secuencia activa'),
                subtitle: Text(
                  _active
                      ? 'Se usará al emitir ventas fiscales de este tipo.'
                      : 'No se asignará mientras esté desactivada.',
                ),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              if (isEditing && sequence != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Número actual: ${sequence.nextNumber} · Próximo disponible: ${sequence.possibleNextNcf}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Guardar cambios' : 'Crear secuencia'),
        ),
      ],
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
    final isPdf = _isPdfUrl(imageUrl) || _isPdfUrl(url);
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

    if (isPdf) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => _openExternalFile(context, url),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'PDF fiscal',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tocar para abrir',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

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

  bool _isPdfUrl(String value) {
    final lower = Uri.decodeFull(value).toLowerCase();
    return lower.contains('.pdf') || lower.contains('%2epdf');
  }

  Future<void> _openExternalFile(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo.')),
      );
    }
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
