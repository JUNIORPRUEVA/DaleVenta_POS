import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

double salesDetailPanelWidth(double availableWidth) => (availableWidth * 0.4)
    .clamp(480.0, 550.0)
    .clamp(0.0, availableWidth)
    .toDouble();

class SalesDetailField extends StatelessWidget {
  const SalesDetailField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ),
      Container(
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      ),
    ],
  );
}

class SalesDetailHeader extends StatelessWidget {
  const SalesDetailHeader({
    super.key,
    required this.clientSelector,
    required this.fiscalLabel,
    required this.hasNote,
    required this.onQuote,
    required this.onOpenFiscalData,
    required this.onOpenNote,
    required this.onPdf,
    this.priceListSelector,
  });

  final Widget clientSelector;
  final String fiscalLabel;
  final bool hasNote;
  final VoidCallback onQuote;
  final VoidCallback? onOpenFiscalData;
  final VoidCallback onOpenNote;
  final VoidCallback onPdf;
  final Widget? priceListSelector;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'Factura actual',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _HeaderAction(
                tooltip: 'Guardar cotización',
                icon: Icons.request_quote_outlined,
                onPressed: onQuote,
              ),
              _HeaderAction(
                tooltip: hasNote ? 'Editar nota' : 'Agregar nota',
                icon: hasNote
                    ? Icons.sticky_note_2_rounded
                    : Icons.sticky_note_2_outlined,
                onPressed: onOpenNote,
                active: hasNote,
              ),
              _HeaderAction(
                tooltip: 'Ver PDF',
                icon: Icons.picture_as_pdf_outlined,
                onPressed: onPdf,
              ),
            ],
          ),
        ),
        if (priceListSelector != null || onOpenFiscalData != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (priceListSelector != null)
                Expanded(child: priceListSelector!),
              if (onOpenFiscalData != null)
                Expanded(
                  child: SalesDetailField(
                    label: 'Comprobante',
                    child: Tooltip(
                      message: 'Tipo de factura: $fiscalLabel',
                      child: InkWell(
                        onTap: onOpenFiscalData,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fiscalLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Cliente',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(child: clientSelector),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    ),
  );
}

class SalesDetailPriceListSelector extends StatelessWidget {
  const SalesDetailPriceListSelector({
    super.key,
    required this.value,
    required this.options,
    required this.busy,
    required this.onChanged,
  });
  final String? value;
  final List<DropdownMenuItem<String?>> options;
  final bool busy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SalesDetailField(
    label: 'Mayoreo',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                items: options,
                onChanged: busy ? null : onChanged,
                isExpanded: true,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    ),
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 40,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        foregroundColor: active ? AppColors.primary : AppColors.textSecondary,
        hoverColor: AppColors.primarySoft,
        shape: const RoundedRectangleBorder(),
      ),
    ),
  );
}

/// Mantiene los nombres completos arriba cuando la columna se estrecha.
class SalesDetailLineLayout extends StatelessWidget {
  const SalesDetailLineLayout({
    super.key,
    required this.description,
    required this.unitPrice,
    required this.quantity,
    required this.total,
    required this.remove,
  });
  final Widget description;
  final Widget unitPrice;
  final Widget quantity;
  final Widget total;
  final Widget remove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 440;
      final controls = Row(
        children: [
          if (!narrow) ...[
            Expanded(child: description),
            const SizedBox(width: 8),
          ],
          if (narrow)
            Expanded(child: unitPrice)
          else
            SizedBox(width: 64, child: unitPrice),
          const SizedBox(width: 8),
          quantity,
          const SizedBox(width: 8),
          SizedBox(width: 92, child: total),
          const SizedBox(width: 4),
          remove,
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (narrow) ...[description, const SizedBox(height: 8)],
          controls,
        ],
      );
    },
  );
}
