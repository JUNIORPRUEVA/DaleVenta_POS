import 'package:flutter/material.dart';

class AppLoadingScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? statusLabel;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppLoadingScreen({
    super.key,
    this.title = 'Cargando…',
    this.subtitle,
    this.statusLabel,
    this.showProgress = true,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary.withValues(alpha: 0.90),
        scheme.primaryContainer.withValues(alpha: 0.75),
        scheme.surface,
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/image/logo.png',
                          width: 92,
                          height: 92,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.business,
                                size: 42,
                                color: scheme.onSurface.withValues(alpha: 0.60),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'DaleVenta POS',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (statusLabel != null &&
                          statusLabel!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            statusLabel!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      if (showProgress) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.primary,
                            ),
                          ),
                        ),
                      ],
                      if (actionLabel != null &&
                          actionLabel!.trim().isNotEmpty &&
                          onAction != null) ...[
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onAction,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(actionLabel!),
                        ),
                      ],
                    ],
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
