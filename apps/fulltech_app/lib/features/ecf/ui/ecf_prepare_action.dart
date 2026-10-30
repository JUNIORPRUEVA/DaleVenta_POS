import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import 'ecf_line_classification_dialog.dart';

/// Acción contextual **Preparar e-CF** para una venta.
///
/// No renderiza nada salvo que se cumplan TODAS las condiciones:
///   * la empresa tiene e-CF habilitado (`capabilities.enabled`);
///   * el usuario tiene el permiso `prepareEcfDocuments`;
///   * el backend declara el tipo documental utilizable.
///
/// Preparar NO emite: crea un borrador local y consume numeración. La
/// elegibilidad fiscal definitiva la decide el backend; cuando la venta no es
/// elegible devuelve un código y un motivo que aquí se muestran tal cual.
class EcfPrepareAction extends ConsumerStatefulWidget {
  const EcfPrepareAction({
    super.key,
    required this.saleId,
    required this.total,
    this.customerName,
  });

  final String saleId;
  final String total;
  final String? customerName;

  @override
  ConsumerState<EcfPrepareAction> createState() => _EcfPrepareActionState();
}

class _EcfPrepareActionState extends ConsumerState<EcfPrepareAction> {
  bool _running = false;
  int? _paymentType;
  /// Tipo documental elegido EXPLÍCITAMENTE por el usuario. Es `null` mientras
  /// no elija: la aplicación nunca deduce E31/E32 por su cuenta.
  String? _documentType;
  int _incomeType = 1;
  final _sequenceDueDate = TextEditingController();

  @override
  void dispose() {
    _sequenceDueDate.dispose();
    super.dispose();
  }

  /// Tipos documentales que esta empresa puede preparar hoy.
  ///
  /// E31 (crédito fiscal) y E32 (consumo) se ofrecen por separado: cuál
  /// corresponde es una decisión del usuario, no una inferencia de la app.
  List<String> _availableTypes(EcfCapabilities? caps) {
    if (caps == null || !caps.enabled) return const <String>[];
    return <String>[
      for (final type in caps.documentTypes)
        if (type.allowedForCompany &&
            const ['E31', 'E32'].contains(type.documentType))
          type.documentType,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(ecfCapabilitiesProvider);
    final user = ref.watch(authStateProvider).user;

    // Silencio deliberado: si e-CF no está habilitado no se ofrece ninguna
    // operación e-CF en la pantalla de ventas (la configuración sigue siendo
    // accesible desde su propia pantalla).
    final caps = capabilities.valueOrNull;
    if (caps == null || !caps.enabled) return const SizedBox.shrink();
    if (!hasUserPermission(user, AppPermission.prepareEcfDocuments)) {
      return const SizedBox.shrink();
    }
    if (_availableTypes(caps).isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _running ? null : () => _openDialog(context),
        icon: _running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Preparar e-CF'),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    _paymentType = null;
    final available = _availableTypes(
      ref.read(ecfCapabilitiesProvider).valueOrNull,
    );
    // Con un solo tipo disponible no hay elección que hacer; con dos, el usuario
    // debe elegir antes de poder preparar.
    _documentType = available.length == 1 ? available.single : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Preparar comprobante electrónico'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (available.length > 1)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'E31',
                        label: Text('E31 · Crédito fiscal'),
                      ),
                      ButtonSegment(value: 'E32', label: Text('E32 · Consumo')),
                    ],
                    selected: {if (_documentType != null) _documentType!},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (value) => setDialogState(
                      () => _documentType = value.isEmpty ? null : value.first,
                    ),
                  )
                else
                  _Row(
                    label: 'Tipo documental',
                    value: _documentType == 'E32'
                        ? 'E32 · Consumo'
                        : 'E31 · Crédito fiscal',
                  ),
                // E32 es consumo final: no exige identificar al receptor.
                if (_documentType != 'E32')
                  _Row(
                    label: 'Cliente',
                    value: (widget.customerName ?? '').trim().isEmpty
                        ? 'Sin cliente'
                        : widget.customerName!,
                  ),
                _Row(label: 'Total', value: widget.total),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _paymentType,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pago fiscal',
                    helperText:
                        'Código del contrato. Se elige explícitamente porque no '
                        'hay un mapeo oficial con el método de pago de la venta.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Código 1')),
                    DropdownMenuItem(value: 2, child: Text('Código 2')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => _paymentType = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _incomeType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de ingreso',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Código 1')),
                    DropdownMenuItem(value: 2, child: Text('Código 2')),
                    DropdownMenuItem(value: 3, child: Text('Código 3')),
                    DropdownMenuItem(value: 4, child: Text('Código 4')),
                    DropdownMenuItem(value: 5, child: Text('Código 5')),
                    DropdownMenuItem(value: 6, child: Text('Código 6')),
                  ],
                  onChanged: (value) => setDialogState(
                    () => _incomeType = value ?? _incomeType,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _sequenceDueDate,
                  decoration: const InputDecoration(
                    labelText: 'Vence la secuencia (AAAA-MM-DD)',
                    helperText: 'Exigido por el contrato para E31.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _documentType == 'E32'
                      ? 'Se creará un BORRADOR local SIN numeración: E32 usa su '
                            'propio cupo de sandbox. No se envía nada al proveedor.'
                      : 'Se creará un BORRADOR local y se consumirá un e-NCF del '
                            'rango de la empresa. No se envía nada al proveedor.',
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
              onPressed: (_paymentType == null || _documentType == null)
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Preparar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _prepare(_documentType!, _paymentType!);
  }

  /// Usa el `context` del propio State (no uno capturado) y comprueba `mounted`
  /// antes de cada uso posterior a un `await`, que es la forma correcta de
  /// navegar después de una operación asíncrona.
  Future<void> _prepare(String documentType, int paymentType) async {
    setState(() => _running = true);
    try {
      final repository = ref.read(ecfRepositoryProvider);
      // E32 va por su flujo propio: no consume numeración de la empresa ni el
      // cupo único de sandbox, y devuelve el borrador sin e-NCF.
      final outcome = documentType == 'E32'
          ? await repository.prepareConsumoFromSale(
              saleId: widget.saleId,
              paymentType: paymentType,
              incomeType: _incomeType,
            )
          : await repository.prepareFromSale(
              saleId: widget.saleId,
              paymentType: paymentType,
              incomeType: _incomeType,
              sequenceDueDate: _sequenceDueDate.text.trim(),
            );
      // La bandeja y los contadores reflejan el nuevo borrador.
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
      if (!mounted) return;
      await _showOutcome(outcome);
    } catch (error) {
      if (!mounted) return;
      await _showOutcome(
        EcfPreparationOutcome.failure(
          code: 'ECF_PREPARATION_UNAVAILABLE',
          message: 'No se pudo contactar al servidor. Revisa la conexión.',
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showOutcome(EcfPreparationOutcome outcome) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(outcome.ok ? 'Borrador preparado' : 'No se pudo preparar'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (outcome.ok) ...[
              _Row(label: 'e-NCF', value: outcome.encf),
              _Row(label: 'Estado', value: outcome.status),
              const SizedBox(height: 8),
              const Text(
                'Es un borrador local: todavía no se ha enviado al proveedor ni '
                'declarado aceptado.',
              ),
            ] else ...[
              _Row(label: 'Código', value: outcome.code),
              const SizedBox(height: 6),
              Text(outcome.message),
              // Cuando el bloqueo es la falta de clasificación fiscal hay salida:
              // se ofrece revisarla. No se reintenta sola ninguna operación.
              if (outcome.code == 'ECF_LINE_CLASSIFICATION_UNCONFIRMED') ...[
                const SizedBox(height: 8),
                const Text(
                  'Después de confirmarla, vuelve a pulsar «Preparar».',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ],
          ],
        ),
        actions: [
          if (outcome.code == 'ECF_LINE_CLASSIFICATION_UNCONFIRMED')
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) =>
                      EcfLineClassificationDialog(saleId: widget.saleId),
                );
              },
              icon: const Icon(Icons.rule, size: 18),
              label: const Text('Revisar clasificación fiscal'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
