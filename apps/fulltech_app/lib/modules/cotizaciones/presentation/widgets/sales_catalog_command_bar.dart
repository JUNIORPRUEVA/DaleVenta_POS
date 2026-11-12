import 'package:flutter/material.dart';

import '../../../../core/design_system/icons/app_icon.dart';
import '../../../../core/design_system/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';

/// Barra de catálogo compartida por el editor y su vista previa aislada.
class SalesCatalogCommandBar extends StatelessWidget {
  const SalesCatalogCommandBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.inventoryEnabled,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onNewProduct,
    required this.onStock,
  });

  static const searchAsset = 'assets/image/buscar-productos.png';
  static const controlHeight = 40.0;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool inventoryEnabled;
  final VoidCallback onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onNewProduct;
  final VoidCallback onStock;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(12) > 15;
      final compactStock = constraints.maxWidth < 440 || largeText;
      final compactProduct = constraints.maxWidth < 360 || largeText;
      final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: 0,
      );
      const radius = BorderRadius.all(Radius.circular(4));
      const border = OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border),
      );
      return SizedBox(
        height: controlHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Tooltip(
                message: 'Buscar productos por nombre o código',
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (_) => onSearchChanged(),
                    onSubmitted: (_) => onSearchSubmitted(),
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    style: textStyle,
                    cursorHeight: 18,
                    decoration: InputDecoration(
                      hintText: 'Buscar productos…',
                      hintStyle: textStyle?.copyWith(
                        color: AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      border: border,
                      enabledBorder: border,
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: radius,
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      prefixIcon: const Center(
                        child: ImageIcon(
                          AssetImage(searchAsset),
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: controlHeight,
                      ),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                controller.clear();
                                onSearchChanged();
                                focusNode.requestFocus();
                              },
                              icon: const Icon(Icons.close_rounded, size: 16),
                              padding: EdgeInsets.zero,
                            ),
                      suffixIconConstraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: controlHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (inventoryEnabled) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: compactStock ? 40 : 72,
                child: Tooltip(
                  message: 'Agregar o ajustar stock',
                  child: OutlinedButton(
                    onPressed: onStock,
                    style: _style(context, filled: false),
                    child: compactStock
                        ? const AppIcon(AppIcons.stockAdd, size: 18)
                        : const Text('+ Stock'),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            SizedBox(
              width: compactProduct ? 40 : 124,
              child: Tooltip(
                message: 'Nuevo producto',
                child: OutlinedButton(
                  onPressed: onNewProduct,
                  style: _style(context, filled: true),
                  child: compactProduct
                      ? const AppIcon(AppIcons.productAdd, size: 18)
                      : const Text('Nuevo producto', maxLines: 1),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  ButtonStyle _style(BuildContext context, {required bool filled}) =>
      OutlinedButton.styleFrom(
        backgroundColor: filled ? AppColors.primarySoft : AppColors.surface,
        foregroundColor: AppColors.primary,
        side: BorderSide(
          color: filled ? AppColors.primarySoft : AppColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        minimumSize: const Size(40, controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      );
}
