import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/auth/auth_provider.dart';

import '../data/ecf_repository.dart';
import '../data/ecf_connection_guard.dart';
import '../data/ecf_pending_credit_request.dart';
import '../../../core/utils/app_feedback.dart';

/// Flujo guiado para preparar una nota de crédito E34 sobre un comprobante
/// original elegible.
///
/// Solo reserva el crédito fiscal: NO crea una devolución financiera, no toca
/// inventario, caja, turnos, pagos ni abonos, y no emite nada. Las líneas y su
/// clasificación fiscal las toma el servidor del comprobante original.
class EcfCreditNoteAction extends ConsumerStatefulWidget {
  const EcfCreditNoteAction({
    super.key,
    required this.originalId,
    required this.originalLabel,
    required this.availableAmount,
  });

  final String originalId;
  final String originalLabel;
  final String availableAmount;

  @override
  ConsumerState<EcfCreditNoteAction> createState() =>
      _EcfCreditNoteActionState();
}

class _EcfCreditNoteActionState extends ConsumerState<EcfCreditNoteAction> {
  bool _running = false;
  String? _requestId;
  bool _uncertain = false;
  String _refundKind = 'TOTAL';
  int _modificationCode = 3;
  int _paymentType = 1;
  int _creditNoteIndicator = 0;
  final _reason = TextEditingController();
  final _lines = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _lines.dispose();
    super.dispose();
  }

  /// Convierte "1:2, 3:1" en `[{lineNumber, quantity}]`. Formato explícito para
  /// no inventar una interfaz de selección que el backend no necesita.
  List<Map<String, dynamic>>? _parseLines() {
    final raw = _lines.text.trim();
    if (raw.isEmpty) return null;
    final parsed = <Map<String, dynamic>>[];
    for (final chunk in raw.split(',')) {
      final parts = chunk.trim().split(':');
      if (parts.length != 2) return null;
      final lineNumber = int.tryParse(parts[0].trim());
      final quantity = parts[1].trim();
      if (lineNumber == null || lineNumber < 1) return null;
      if (double.tryParse(quantity) == null) return null;
      parsed.add({'lineNumber': lineNumber, 'quantity': quantity});
    }
    return parsed.isEmpty ? null : parsed;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _running || _uncertain ? null : () => _openDialog(),
        icon: _running
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.assignment_return_outlined, size: 18),
        label: const Text('Nota de crédito'),
      ),
    );
  }

  Future<void> _openDialog() async {
    _refundKind = 'TOTAL';
    final lines = _parseLines();
    if (_refundKind == 'PARTIAL' && lines == null) _lines.clear();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isPartial = _refundKind == 'PARTIAL';
          final parsed = _parseLines();
          final linesValid = !isPartial || parsed != null;
          final reasonValid = _reason.text.trim().isNotEmpty;
          return AlertDialog(
            title: const Text('Nota de crédito (E34)'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row(dialogContext, 'Original', widget.originalLabel),
                  _row(
                    dialogContext,
                    'Saldo disponible',
                    widget.availableAmount,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'TOTAL', label: Text('Total')),
                      ButtonSegment(value: 'PARTIAL', label: Text('Parcial')),
                    ],
                    selected: {_refundKind},
                    onSelectionChanged: (value) =>
                        setDialogState(() {
                          _refundKind = value.first;
                          if (_refundKind == 'PARTIAL') _modificationCode = 3;
                        }),
                  ),
                  if (isPartial) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _lines,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Líneas a acreditar',
                        hintText: '1:1, 2:3',
                        helperText:
                            'Formato línea:cantidad. La clasificación fiscal y '
                            'el precio los toma el sistema del original.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reason,
                    maxLength: 90,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Motivo de la modificación',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _modificationCode,
                    decoration: const InputDecoration(
                      labelText: 'Código de modificación',
                      helperText:
                          'Selecciona el motivo fiscal de la nota.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      if (!isPartial) const DropdownMenuItem(value: 1, child: Text('Anulación total')),
                      const DropdownMenuItem(value: 3, child: Text('Corrección de montos / devolución')),
                    ],
                    onChanged: (value) => setDialogState(
                      () => _modificationCode = value ?? _modificationCode,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _paymentType,
                    decoration: const InputDecoration(
                      labelText: 'Forma de pago fiscal',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Código 1')),
                      DropdownMenuItem(value: 2, child: Text('Código 2')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => _paymentType = value ?? 1),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _creditNoteIndicator,
                    decoration: const InputDecoration(
                      labelText: 'Indicador de nota de crédito',
                      helperText: 'Campo obligatorio del contrato (0 o 1).',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0')),
                      DropdownMenuItem(value: 1, child: Text('1')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => _creditNoteIndicator = value ?? 0),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Se reservará el crédito fiscal y se creará un BORRADOR. '
                    'No se modifica la venta, ni el inventario, ni la caja.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
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
                onPressed: (!linesValid || !reasonValid)
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: const Text('Preparar nota'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    await _prepare();
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _prepare() async {
    if (_running) return;
    setState(() => _running = true);
    EcfPendingCreditRequest? pending;
    String? scope;
    try {
      final user = ref.read(authStateProvider).user;
      if (user?.companyId == null) throw StateError('No se pudo verificar la empresa.');
      scope = '${user!.companyId}:${user.id}:${widget.originalId}';
      pending = EcfPendingCreditRequest(await SharedPreferences.getInstance());
      _requestId = await pending.obtain(scope, {
        'refundKind': _refundKind, 'modificationCode': _modificationCode,
        'reason': _reason.text.trim(), 'paymentType': _paymentType,
        'creditNoteIndicator': _creditNoteIndicator,
        'lines': _refundKind == 'PARTIAL' ? _parseLines() : null,
      });
      if (!mounted) return;
      final outcome = await ref
          .read(ecfRepositoryProvider)
          .prepareCreditNote(
            originalDocumentId: widget.originalId,
            // Identidad de ESTA operación: permite varias notas parciales sobre
            // el mismo original y hace idempotente un reintento.
            clientRequestId: _requestId!,
            refundKind: _refundKind,
            modificationCode: _modificationCode,
            modificationReason: _reason.text.trim(),
            paymentType: _paymentType,
            creditNoteIndicator: _creditNoteIndicator,
            lines: _refundKind == 'PARTIAL' ? _parseLines() : null,
          );
      await pending.complete(scope, _requestId!);
      _requestId = null;
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
      ref.invalidate(ecfEligibleOriginalsProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(outcome.ok ? 'Nota preparada' : 'No se pudo preparar'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (outcome.ok) ...[
                _row(dialogContext, 'e-NCF', outcome.encf),
                _row(dialogContext, 'Estado', outcome.status),
                const SizedBox(height: 8),
                const Text(
                  'Es un borrador local con el crédito fiscal reservado. No se '
                  'ha enviado al proveedor ni modifica la devolución financiera.',
                ),
              ] else ...[
                _row(dialogContext, 'Código', outcome.code),
                const SizedBox(height: 6),
                Text(outcome.message),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } on EcfConnectionException catch (error) {
      if (!error.uncertain && pending != null && scope != null && _requestId != null) {
        await pending.complete(scope, _requestId!);
        _requestId = null;
      }
      if (!mounted) return;
      setState(() => _uncertain = error.uncertain);
      AppFeedback.showToast(context, title: error.noticeTitle, body: error.message,
        kind: AppFeedbackKind.warning, duration: const Duration(seconds: 4), dedupeKey: 'ecf-connection');
      ref.invalidate(ecfDocumentsProvider);
    } catch (error) {
      if (error is DioException && const {400, 401, 403, 404, 422}.contains(error.response?.statusCode) &&
          pending != null && scope != null && _requestId != null) {
        await pending.complete(scope, _requestId!);
        _requestId = null;
      }
      if (error is StateError && mounted) {
        AppFeedback.showToast(context, title: 'Preparación pendiente', body: error.message.toString(),
          kind: AppFeedbackKind.warning, duration: const Duration(seconds: 4), dedupeKey: 'ecf-connection');
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No se pudo preparar'),
          content: const Text(
            'El comprobante original no cumple la política de saldo o la '
            'operación fue rechazada por el servidor. Revisa el estado del '
            'original antes de reintentar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
