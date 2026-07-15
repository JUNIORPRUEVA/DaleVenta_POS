import 'package:flutter/material.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({
    super.key,
    required this.visible,
    required this.label,
    this.compact = false,
  });

  final bool visible;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 8 : 12),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
