import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_create_screen.dart';
import 'warning_labels.dart';

class WarningDetailScreen extends ConsumerStatefulWidget {
  final String warningId;
  const WarningDetailScreen({super.key, required this.warningId});

  @override
  ConsumerState<WarningDetailScreen> createState() =>
      _WarningDetailScreenState();
}

class _WarningDetailScreenState extends ConsumerState<WarningDetailScreen> {
  bool _actionLoading = false;
  static const String _companyHeaderName = 'FULLTECH, SRL';
  static const String _companyHeaderPhone = '8295344286';
  static const String _companyHeaderRnc = '133080206';

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle amonestacion')),
        body: const Center(
          child: Text('Acceso no permitido para este usuario'),
        ),
      );
    }

    final async = ref.watch(warningDetailProvider(widget.warningId));
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Detalle amonestacion')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (w) => _buildBody(context, w),
    );
  }

  Widget _buildBody(BuildContext context, EmployeeWarning w) {
    final statusColor = WarningLabels.statusColor(w.status);
    final reason = (w.reason ?? w.title).trim();
    final details = (w.details ?? w.description).trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.warningNumber, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '$_companyHeaderName | Tel: $_companyHeaderPhone | RNC: $_companyHeaderRnc',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          if (w.status == 'DRAFT')
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _openEdit(context, w),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar',
            onPressed: _actionLoading ? null : () => _deleteWarning(context, w),
          ),
          if (w.status != 'ANNULLED')
            IconButton(
              icon: const Icon(Icons.block_rounded),
              tooltip: 'Anular',
              onPressed: _actionLoading ? null : () => _annul(context, w),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Regenerar PDF',
            onPressed: _actionLoading ? null : () => _regeneratePdf(context, w),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    reason.isEmpty ? 'Sin motivo' : reason,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                _Pill(
                  label: WarningLabels.status[w.status] ?? w.status,
                  color: statusColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _InfoPanel(
            title: 'Empleado',
            rows: [
              (
                'Nombre',
                _v(w.employeeNameSnapshot ?? w.employeeUser?.nombreCompleto),
              ),
              (
                'Cedula',
                _v(w.employeeCedulaSnapshot ?? w.employeeUser?.cedula),
              ),
              (
                'Cargo',
                _v(
                  w.employeePositionSnapshot ??
                      w.employeeUser?.workContractJobTitle,
                ),
              ),
              ('Departamento/Area', _v(w.employeeDepartmentSnapshot)),
              (
                'Telefono',
                _v(w.employeePhoneSnapshot ?? w.employeeUser?.telefono),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoPanel(
            title: 'Documento',
            rows: [
              ('Fecha amonestacion', WarningLabels.fmt(w.warningDate)),
              ('Fecha del hecho', WarningLabels.fmt(w.incidentDate)),
              ('Hora aproximada', _v(w.incidentTime)),
              ('Lugar', _v(w.incidentPlace)),
              (
                'Tipo',
                WarningLabels.warningType[w.warningType ?? ''] ??
                    _v(w.warningType),
              ),
              (
                'Encargado',
                _v(w.issuedByNameSnapshot ?? w.createdByUser?.nombreCompleto),
              ),
              (
                'Cargo encargado',
                _v(
                  w.issuedByPositionSnapshot ??
                      w.createdByUser?.workContractJobTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoPanel(
            title: 'Empresa',
            rows: [
              ('Nombre', _v(w.companyNameSnapshot)),
              ('RNC', _v(w.companyRncSnapshot)),
              ('Direccion', _v(w.companyAddressSnapshot)),
            ],
          ),
          const SizedBox(height: 10),
          _TextPanel(title: 'Motivo', text: reason),
          const SizedBox(height: 10),
          _TextPanel(title: 'Detalle de los hechos', text: details),
          const SizedBox(height: 10),
          _TextPanel(
            title: 'Texto completo generado',
            text: (w.generatedText ?? '').trim().isEmpty
                ? details
                : (w.generatedText ?? '').trim(),
          ),
          if ((w.internalNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextPanel(
              title: 'Observaciones internas',
              text: (w.internalNotes ?? '').trim(),
            ),
          ],
          const SizedBox(height: 10),
          _PdfPanel(
            onOpenInApp: _hasPdf(w) ? () => _openPdfInApp(w) : null,
            onPrint: _hasPdf(w) ? () => _printPdf(w) : null,
          ),
          if (w.signatures.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextPanel(
              title: 'Firma legacy (historico)',
              text:
                  'Este registro conserva datos de firma historicos del flujo anterior.',
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _v(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? 'No registrado' : v;
  }

  bool _hasPdf(EmployeeWarning w) {
    final pdfUrl = (w.pdfUrl ?? '').trim();
    final signedPdfUrl = (w.signedPdfUrl ?? '').trim();
    return pdfUrl.isNotEmpty || signedPdfUrl.isNotEmpty;
  }

  Future<void> _annul(BuildContext context, EmployeeWarning w) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anular amonestacion'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motivo de anulacion',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (reasonCtrl.text.trim().isEmpty) return;

    setState(() => _actionLoading = true);
    try {
      await ref
          .read(employeeWarningsRepositoryProvider)
          .annul(w.id, reasonCtrl.text.trim());
      ref.invalidate(warningDetailProvider(w.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amonestacion anulada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _deleteWarning(BuildContext context, EmployeeWarning w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar amonestacion'),
        content: const Text('Esta accion no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final navigator = Navigator.of(context);
    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).delete(w.id);
      ref.invalidate(warningsListControllerProvider);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (navigator.canPop()) {
          navigator.pop(true);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _regeneratePdf(BuildContext context, EmployeeWarning w) async {
    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).generatePdf(w.id);
      ref.invalidate(warningDetailProvider(w.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF regenerado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _openEdit(BuildContext context, EmployeeWarning w) async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => WarningCreateScreen(existing: w)));
    if (result == true && mounted) {
      ref.invalidate(warningDetailProvider(w.id));
    }
  }

  Future<Uint8List> _loadPdfBytes(EmployeeWarning w) {
    final rawPdfUrl = (w.pdfUrl ?? w.signedPdfUrl ?? '').trim();
    return ref
        .read(employeeWarningsRepositoryProvider)
        .getMyWarningPdfBytes(
          id: w.id,
          rawPdfUrl: rawPdfUrl.isEmpty ? null : rawPdfUrl,
        );
  }

  Future<void> _openPdfInApp(EmployeeWarning w) async {
    try {
      final bytes = await _loadPdfBytes(w);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final media = MediaQuery.sizeOf(dialogContext);
          final isCompact = media.width < 560;
          return Dialog(
            insetPadding: EdgeInsets.all(isCompact ? 8 : 14),
            child: SizedBox(
              width: isCompact ? media.width - 16 : 920,
              height: isCompact ? media.height * 0.92 : 760,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(isCompact ? 10 : 14, 10, 8, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Amonestacion ${w.warningNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isCompact ? 14 : 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$_companyHeaderName | Tel: $_companyHeaderPhone | RNC: $_companyHeaderRnc',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isCompact ? 10 : 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(dialogContext),
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
                      build: (_) async => bytes,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir el PDF: $e')));
    }
  }

  Future<void> _printPdf(EmployeeWarning w) async {
    try {
      final bytes = await _loadPdfBytes(w);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo imprimir el PDF: $e')));
    }
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoPanel({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => _Container(
    title: title,
    child: Column(
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(r.$2, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _TextPanel extends StatelessWidget {
  final String title;
  final String text;
  const _TextPanel({required this.title, required this.text});

  @override
  Widget build(BuildContext context) => _Container(
    title: title,
    child: Text(
      text.trim().isEmpty ? 'No registrado' : text.trim(),
      style: const TextStyle(fontSize: 13, height: 1.45),
    ),
  );
}

class _PdfPanel extends StatelessWidget {
  final VoidCallback? onOpenInApp;
  final VoidCallback? onPrint;
  const _PdfPanel({required this.onOpenInApp, required this.onPrint});

  @override
  Widget build(BuildContext context) => _Container(
    title: 'Documento PDF',
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenInApp,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Ver amonestacion'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Imprimir'),
          ),
        ),
      ],
    ),
  );
}

class _Container extends StatelessWidget {
  final String title;
  final Widget child;
  const _Container({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
