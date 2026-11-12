import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Acceso compacto al menú: logotipo y navegación visibles en un solo botón.
class BrandedMenuButton extends StatefulWidget {
  const BrandedMenuButton({
    super.key,
    required this.onPressed,
    this.onDark = false,
  });

  final VoidCallback onPressed;
  final bool onDark;

  @override
  State<BrandedMenuButton> createState() => _BrandedMenuButtonState();
}

class _BrandedMenuButtonState extends State<BrandedMenuButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused || _pressed;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: 'Abrir menú principal de FullPOS',
      onTap: widget.onPressed,
      child: Tooltip(
        message: 'Abrir menú principal',
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: _focused
                  ? (widget.onDark ? AppColors.surface : AppColors.primary)
                  : (widget.onDark
                        ? AppColors.surface.withValues(alpha: 0.22)
                        : AppColors.border),
            ),
          ),
          child: Material(
            color: active
                ? (widget.onDark
                      ? AppColors.surface.withValues(alpha: 0.12)
                      : AppColors.primarySoft)
                : (widget.onDark
                      ? AppColors.surface.withValues(alpha: 0.08)
                      : AppColors.surfaceAlt),
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              excludeFromSemantics: true,
              borderRadius: radius,
              mouseCursor: SystemMouseCursors.click,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/image/nuevologo.png',
                      width: 36,
                      height: 36,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 1,
                      height: 20,
                      child: ColoredBox(
                        color: widget.onDark
                            ? AppColors.surface.withValues(alpha: 0.22)
                            : AppColors.border,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.menu_rounded,
                        size: 20,
                        color: widget.onDark
                            ? AppColors.surface
                            : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
