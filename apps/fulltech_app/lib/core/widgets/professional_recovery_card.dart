import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:flutter/material.dart';

import '../errors/user_facing_error.dart';

class ProfessionalRecoveryCard extends StatelessWidget {
  const ProfessionalRecoveryCard({
    super.key,
    required this.error,
    required this.onRetryNow,
    this.autoRetryCountdown,
    this.isRetrying = false,
  });

  final UserFacingError error;
  final VoidCallback onRetryNow;
  final int? autoRetryCountdown;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCountdown = (autoRetryCountdown ?? 0) > 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.health_and_safety_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        error.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(error.message, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  error.helpText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hasCountdown) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reintentando automáticamente en ${autoRetryCountdown!} s...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: isRetrying ? null : onRetryNow,
                      icon: const MobileActionIcon(Icons.refresh_rounded),
                      label: const Text('Reintentar ahora'),
                    ),
                    if (error.autoRetry)
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.autorenew_rounded),
                        label: const Text('Autorecuperación activa'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
