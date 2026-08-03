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
            constraints: const BoxConstraints(maxWidth: 218),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.42),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 126,
                        height: 70,
                        child: Image.asset(
                          'assets/image/logo.png',
                          width: 126,
                          height: 70,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 70,
                              height: 48,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.business,
                                size: 34,
                                color: scheme.onSurface.withValues(alpha: 0.60),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'FullPOS Cloud',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.72),
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
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2.8,
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
