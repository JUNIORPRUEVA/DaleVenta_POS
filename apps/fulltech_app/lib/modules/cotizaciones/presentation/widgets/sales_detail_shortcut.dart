import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Accesos secundarios de la fila de cobro; sus acciones pertenecen al editor.
class SalesDetailShortcut extends StatelessWidget {
  const SalesDetailShortcut({
    super.key,
    required this.tooltip,
    required this.asset,
    required this.onPressed,
    this.label,
    this.width = 40,
    this.iconSize = 28,
  });

  static const calculatorAsset = 'assets/image/detalle-calculadora.png';
  static const salesAsset = 'assets/image/detalle-ventas.png';

  final String tooltip;
  final String asset;
  final VoidCallback? onPressed;
  final String? label;
  final double width;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: label != null,
    child: SizedBox(
      width: width,
      height: 64,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.surface,
          padding: EdgeInsets.zero,
          minimumSize: Size(width, 64),
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImageIcon(AssetImage(asset), size: iconSize),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
