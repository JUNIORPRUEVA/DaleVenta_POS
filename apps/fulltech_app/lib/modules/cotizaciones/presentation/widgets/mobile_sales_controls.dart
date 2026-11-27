import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/square_pos_dialog.dart';

class MobileSalesActionRow extends StatelessWidget {
  const MobileSalesActionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Material(
      color: AppColors.surface,
      shape: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 18, height: 24, child: Center(child: icon)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MobileSalesSelector extends StatelessWidget {
  const MobileSalesSelector({
    super.key,
    required this.title,
    required this.label,
    required this.icon,
    this.iconAsset,
    this.onTap,
  });
  final String title;
  final String label;
  final IconData icon;
  final String? iconAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (iconAsset == null)
                Icon(icon, size: 18, color: AppColors.primary)
              else
                ImageIcon(
                  AssetImage(iconAsset!),
                  size: 18,
                  color: AppColors.primary,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MobileSalesProductCard extends StatelessWidget {
  const MobileSalesProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.image,
    required this.onTap,
    required this.onImageTap,
    this.stock,
  });
  final String name;
  final String price;
  final String? stock;
  final Widget image;
  final VoidCallback onTap;
  final VoidCallback onImageTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  SizedBox(
                    key: const ValueKey('phone-product-image'),
                    width: 60,
                    height: 60,
                    child: GestureDetector(
                      onTap: onImageTap,
                      child: ColoredBox(
                        color: AppColors.surfaceSubtle,
                        child: image,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (stock != null)
                        Text(
                          stock!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: 'Agregar $name',
                    onPressed: onTap,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceSubtle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class MobileSalesCheckoutSummary extends StatelessWidget {
  const MobileSalesCheckoutSummary({
    super.key,
    required this.clientName,
    this.priceLabel,
    this.voucherSelector,
    this.showVoucher = true,
  });
  final String clientName;
  final String? priceLabel;
  final Widget? voucherSelector;
  final bool showVoucher;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    Widget text(String value) => Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
    return Container(
      key: const ValueKey('phone-checkout-sale-summary'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: SquarePosDialog.active(context) ? SquarePosDialog.corners : BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Cliente', text(clientName)),
          if (showVoucher) row('Comprobante', voucherSelector ?? text('Normal')),
          if (priceLabel != null) row('Precios', text(priceLabel!)),
        ],
      ),
    );
  }
}

class MobileSalesLineEditorContent extends StatelessWidget {
  const MobileSalesLineEditorContent({
    super.key,
    required this.compact,
    required this.child,
  });
  final bool compact;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!compact) return child;
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: SquarePosDialog.active(context) ? SquarePosDialog.corners : BorderRadius.circular(4),
    );
    return Theme(
      data: theme.copyWith(
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: (theme.segmentedButtonTheme.style ?? const ButtonStyle()).copyWith(shape: WidgetStatePropertyAll(shape)),
        ),
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}

class MobileSalesFloatingTools extends StatelessWidget {
  const MobileSalesFloatingTools({
    super.key,
    required this.onAssistant,
    required this.onCalculator,
    required this.assistantAsset,
  });
  final VoidCallback onAssistant;
  final VoidCallback onCalculator;
  final String assistantAsset;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, Widget icon, VoidCallback onTap) => Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: 64,
        child: Material(
          color: AppColors.primary,
          elevation: 3,
          shadowColor: AppColors.primary.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(10), child: icon),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('Asistente IA', Image.asset(assistantAsset), onAssistant),
        const SizedBox(height: 12),
        button(
          'Abrir calculadora',
          const Icon(Icons.calculate_outlined, color: Colors.white, size: 32),
          onCalculator,
        ),
      ],
    );
  }
}

class MobileSalesEdgeHint extends StatelessWidget {
  const MobileSalesEdgeHint({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Desliza a la izquierda para abrir Acciones',
    button: true,
    child: Tooltip(
      message: 'Desliza a la izquierda para ver Acciones',
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.94),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 20,
            height: 82,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.chevron_left,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 3),
                RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'Acciones',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
