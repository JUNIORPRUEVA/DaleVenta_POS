import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';

/// Revisión de la clasificación fiscal de las partidas de una venta.
///
/// Existe porque una partida fuera de inventario no tiene producto del que
/// heredar si es un bien o un servicio, y el backend se niega —con razón— a
/// adivinarlo. Sin esta revisión, esa venta no puede facturarse electrónicamente.
///
/// Límites que la interfaz respeta deliberadamente:
///
///  * **No decide nada por su cuenta.** `canConfirm` y `fiscallyFrozen` vienen del
///    backend; la pantalla no los recalcula ni los deduce.
///  * **No confirma sin permiso.** Sin `confirmEcfLineClassification` no se
///    ofrece el botón y se explica por qué, en vez de mostrar una acción que el
///    servidor rechazaría.
///  * **No promete lo que no pasó.** Confirmar una clasificación NO emite nada ni
///    equivale a una aprobación de la DGII, y el texto lo dice.
///  * **No reintenta sola** ninguna operación fiscal.
class EcfLineClassificationDialog extends ConsumerStatefulWidget {
  const EcfLineClassificationDialog({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<EcfLineClassificationDialog> createState() =>
      _EcfLineClassificationDialogState();
}

class _EcfLineClassificationDialogState
    extends ConsumerState<EcfLineClassificationDialog> {
  /// Evita que dos pulsaciones rápidas envíen dos decisiones.
  bool _busy = false;
  String? _error;

  Future<void> _confirm(
    EcfPendingClassificationLine line,
    String classification,
    String reason,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ecfRepositoryProvider)
          .confirmLineClassification(
            saleId: widget.saleId,
            saleItemId: line.saleItemId,
            classification: classification,
            reason: reason,
          );
      ref.invalidate(ecfPendingClassificationsProvider(widget.saleId));
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  /// Traduce el fallo a algo accionable sin inventar causas.
  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('403')) {
      return 'No tienes autorización para confirmar la clasificación fiscal. '
          'Pídeselo a un usuario habilitado.';
    }
    if (text.contains('fue enviado o está en revisión')) {
      return 'El comprobante ya salió del equipo: su clasificación no puede '
          'cambiarse. Requiere revisión humana.';
    }
    if (text.contains('misma clasificación')) {
      return 'La partida ya tiene confirmada esa misma clasificación.';
    }
    if (text.contains('401')) {
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    }
    return 'No se pudo confirmar la clasificación. Inténtalo de nuevo.';
  }

  Future<void> _openReview(
    EcfPendingClassificationLine line, {
    required bool canConfirm,
  }) async {
    final decision = await showDialog<_ClassificationDecision>(
      context: context,
      builder: (context) => _ClassificationDecisionDialog(line: line),
    );
    if (decision == null) return;
    await _confirm(line, decision.classification, decision.reason);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    final canConfirm = hasUserPermission(
      user,
      AppPermission.confirmEcfLineClassification,
    );
    final pending = ref.watch(
      ecfPendingClassificationsProvider(widget.saleId),
    );

    return AlertDialog(
      title: const Text('Clasificación fiscal de las partidas'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: pending.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No se pudo consultar el estado de las partidas.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(
                    ecfPendingClassificationsProvider(widget.saleId),
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
            data: (state) => _Body(
              state: state,
              canConfirm: canConfirm,
              busy: _busy,
              error: _error,
              onReview: (line) => _openReview(line, canConfirm: canConfirm),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.canConfirm,
    required this.busy,
    required this.onReview,
    this.error,
  });

  final EcfPendingClassifications state;
  final bool canConfirm;
  final bool busy;
  final ValueChanged<EcfPendingClassificationLine> onReview;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.lines.isEmpty) {
      return Text(
        'Esta venta no tiene partidas fiscales que revisar.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (state.pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Esta venta contiene una partida que necesita clasificación '
              'fiscal antes de preparar el comprobante electrónico.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (state.fiscallyFrozen)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Un comprobante de esta venta ya salió del equipo: la '
              'clasificación ya no puede cambiarse sin revisión humana.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (final line in state.lines) _LineTile(line: line),
        const SizedBox(height: 10),
        if (!canConfirm && state.pending.isNotEmpty)
          Text(
            'Necesitas el permiso de clasificación fiscal para confirmarla. '
            'Solicítalo a un usuario habilitado.',
            style: theme.textTheme.bodySmall,
          )
        else if (canConfirm && state.pending.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final line in state.pending)
                  if (line.canConfirm)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : () => onReview(line),
                      icon: const Icon(Icons.rule, size: 18),
                      label: Text(
                        line.name.isEmpty
                            ? 'Revisar clasificación fiscal'
                            : 'Clasificar ${line.name}',
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final EcfPendingClassificationLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = line.needsClassification;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pending ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: pending
                ? theme.colorScheme.error
                : const Color(0xFF1B7F3B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name.isEmpty ? 'Partida sin descripción' : line.name,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Cantidad ${line.quantity} · Precio ${line.unitPrice}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Clasificación: ${line.statusLabel}',
                  style: theme.textTheme.bodySmall,
                ),
                if (line.supervisedReason != null)
                  Text(
                    'Motivo registrado: ${line.supervisedReason}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassificationDecision {
  const _ClassificationDecision({
    required this.classification,
    required this.reason,
  });

  final String classification;
  final String reason;
}

/// Elección explícita de bien o servicio, con motivo obligatorio.
class _ClassificationDecisionDialog extends StatefulWidget {
  const _ClassificationDecisionDialog({required this.line});

  final EcfPendingClassificationLine line;

  @override
  State<_ClassificationDecisionDialog> createState() =>
      _ClassificationDecisionDialogState();
}

class _ClassificationDecisionDialogState
    extends State<_ClassificationDecisionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  // Sin valor preseleccionado: la clasificación la decide la persona, no el
  // formulario. Preseleccionar «Bien» empujaría a aceptar sin pensar.
  String? _classification;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return AlertDialog(
      title: const Text('Clasificación fiscal de la partida'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name.isEmpty ? 'Partida sin descripción' : line.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cantidad ${line.quantity} · Precio ${line.unitPrice}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Indica si la partida es un BIEN o un SERVICIO. Queda '
                  'registrado con tu usuario, la fecha y el motivo, y se usa '
                  'solo para preparar el comprobante: no emite nada ni sustituye '
                  'ninguna autorización de la DGII.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _classification,
                  decoration: const InputDecoration(
                    labelText: 'Clasificación',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'PRODUCT', child: Text('Bien')),
                    DropdownMenuItem(value: 'SERVICE', child: Text('Servicio')),
                  ],
                  validator: (value) =>
                      value == null ? 'Elige BIEN o SERVICIO' : null,
                  onChanged: (value) =>
                      setState(() => _classification = value),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    hintText: 'Por qué se clasifica así (queda en la auditoría)',
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.length < 3) {
                      return 'El motivo es obligatorio (mínimo 3 caracteres)';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              _ClassificationDecision(
                classification: _classification!,
                reason: _reason.text.trim(),
              ),
            );
          },
          child: const Text('Confirmar clasificación'),
        ),
      ],
    );
  }
}
