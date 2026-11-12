import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Superficie visual; la acción y el estado pertenecen al menú que la contiene.
class RefinedTopbarSurface extends StatefulWidget {
  const RefinedTopbarSurface({
    super.key,
    required this.child,
    this.height = 36,
    this.width,
    this.background = AppColors.surface,
    this.outlined = true,
  });

  final Widget child;
  final double height;
  final double? width;
  final Color background;
  final bool outlined;

  @override
  State<RefinedTopbarSurface> createState() => _RefinedTopbarSurfaceState();
}

class _RefinedTopbarSurfaceState extends State<RefinedTopbarSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: SizedBox(
      height: 40,
      width: widget.width,
      child: Center(
        widthFactor: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.primarySoft : widget.background,
            borderRadius: BorderRadius.circular(8),
            border: widget.outlined
                ? Border.all(color: AppColors.border)
                : null,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class RefinedTurnChip extends StatelessWidget {
  const RefinedTurnChip({
    super.key,
    required this.open,
    required this.unverified,
    required this.activity,
  });

  final bool open;
  final bool unverified;
  final Widget activity;

  @override
  Widget build(BuildContext context) => RefinedTopbarSurface(
    height: 32,
    background: open ? AppColors.primarySoft : AppColors.surfaceAlt,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          activity,
          const SizedBox(width: 7),
          Text(
            open ? 'Turno abierto' : 'Turno cerrado',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: open ? AppColors.primaryDark : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (unverified) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.cloud_off_outlined,
              size: 14,
              color: AppColors.warning,
            ),
          ],
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}

class RefinedSyncIndicator extends StatelessWidget {
  const RefinedSyncIndicator({
    super.key,
    required this.glyph,
    required this.label,
    this.badge,
    this.badgeColor = AppColors.warning,
  });

  final Widget glyph;
  final String label;
  final String? badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: RefinedTopbarSurface(
      height: 40,
      width: 40,
      outlined: false,
      background: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          glyph,
          if (badge != null)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 14),
                height: 14,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: badgeColor == AppColors.warning
                          ? AppColors.textPrimary
                          : AppColors.surface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class RefinedCompanyLabel extends StatelessWidget {
  const RefinedCompanyLabel({
    super.key,
    required this.label,
    required this.logo,
  });

  final String label;
  final Widget logo;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 126, maxWidth: 240),
    child: RefinedTopbarSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
