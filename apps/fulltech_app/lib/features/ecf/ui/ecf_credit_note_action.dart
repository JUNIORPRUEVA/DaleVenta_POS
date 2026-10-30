import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/ecf_repository.dart';

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
  static const _uuid = Uuid();

  bool _running = false;
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
        onPressed: _running ? null : () => _openDialog(),
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
                  _row(dialogContext, 'Saldo disponible', widget.availableAmount),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'TOTAL', label: Text('Total')),
                      ButtonSegment(value: 'PARTIAL', label: Text('Parcial')),
                    ],
                    selected: {_refundKind},
                    onSelectionChanged: (value) =>
                        setDialogState(() => _refundKind = value.first),
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
                          'Código del contrato (1–4). Se elige explícitamente: '
                          'el esquema publicado no documenta su significado.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Código 1')),
                      DropdownMenuItem(value: 2, child: Text('Código 2')),
                      DropdownMenuItem(value: 3, child: Text('Código 3')),
                      DropdownMenuItem(value: 4, child: Text('Código 4')),
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
                    onChanged: (value) => setDialogState(
                      () => _creditNoteIndicator = value ?? 0,
                    ),
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
    setState(() => _running = true);
    try {
      final outcome = await ref.read(ecfRepositoryProvider).prepareCreditNote(
            originalDocumentId: widget.originalId,
            // Identidad de ESTA operación: permite varias notas parciales sobre
            // el mismo original y hace idempotente un reintento.
            clientRequestId: _uuid.v4(),
            refundKind: _refundKind,
            modificationCode: _modificationCode,
            modificationReason: _reason.text.trim(),
            paymentType: _paymentType,
            creditNoteIndicator: _creditNoteIndicator,
            lines: _refundKind == 'PARTIAL' ? _parseLines() : null,
          );
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
      ref.invalidate(ecfEligibleOriginalsProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            outcome.ok ? 'Nota preparada' : 'No se pudo preparar',
          ),
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
    } catch (_) {
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
