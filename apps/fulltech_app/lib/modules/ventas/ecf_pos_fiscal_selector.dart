import 'package:flutter/material.dart';

import 'ecf_pos_fiscal.dart';

/// Selector fiscal del POS para empresas que facturan electrónicamente.
///
/// Reemplaza visualmente al selector B01/B02: mismos gestos (chip que abre una
/// hoja inferior), pero las opciones son E31/E32 y, solo si la empresa habilitó
/// la excepción, «Normal». El aviso rojo de la excepción se muestra en el propio
/// selector para que nadie cierre una venta sin comprobante sin haberlo leído.
class EcfPosFiscalSelector extends StatelessWidget {
  const EcfPosFiscalSelector({
    super.key,
    required this.modes,
    required this.selected,
    required this.warning,
    required this.onSelected,
    this.missingBuyer = false,
    this.compact = false,
  });

  final List<EcfPosFiscalMode> modes;
  final EcfPosFiscalMode? selected;

  /// Aviso fiscal que envía el servidor. Se muestra íntegro, sin recortar.
  final String warning;

  final ValueChanged<EcfPosFiscalMode> onSelected;

  /// El modo elegido exige receptor y todavía no está identificado.
  final bool missingBuyer;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) return const SizedBox.shrink();
    final current = selected;
    final showWarning =
        current == EcfPosFiscalMode.normal && warning.isNotEmpty;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _open(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Comprobante electrónico',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 4 : 6,
              ),
              border: const OutlineInputBorder(),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: compact ? 15 : 17,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    current?.label ?? 'Selecciona el comprobante',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (missingBuyer) ...[
          const SizedBox(height: 4),
          Text(
            'E31 exige un cliente con RNC/Cédula y nombre.',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
          ),
        ],
        if (showWarning) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<EcfPosFiscalMode>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in modes)
                ListTile(
                  leading: Icon(
                    mode == EcfPosFiscalMode.normal
                        ? Icons.receipt_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(mode.label),
                  subtitle:
                      mode == EcfPosFiscalMode.normal && warning.isNotEmpty
                      ? const Text(
                          'Requiere un motivo y queda registrada para auditoría.',
                        )
                      : null,
                  selected: this.selected == mode,
                  onTap: () => Navigator.of(context).pop(mode),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) onSelected(selected);
  }
}
