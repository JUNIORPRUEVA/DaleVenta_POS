import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Compact visual track with a full-size touch and keyboard target.
class CompactSquareSwitch extends StatelessWidget {
  const CompactSquareSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final primary = Theme.of(context).colorScheme.primary;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    void toggle() => onChanged?.call(!value);
    return Semantics(
      label: label,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? toggle : null,
          borderRadius: BorderRadius.circular(6),
          focusColor: AppColors.primarySoft,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Center(
              child: AnimatedContainer(
                duration: duration,
                width: 32,
                height: 18,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: value
                      ? primary.withValues(alpha: enabled ? 1 : 0.45)
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: value ? primary : AppColors.borderStrong,
                  ),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: value ? AppColors.surface : AppColors.textMuted,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
