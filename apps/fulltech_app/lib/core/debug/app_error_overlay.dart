import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error_reporter.dart';

class AppErrorOverlay extends StatefulWidget {
  const AppErrorOverlay({super.key});

  @override
  State<AppErrorOverlay> createState() => _AppErrorOverlayState();
}

class _AppErrorOverlayState extends State<AppErrorOverlay> {
  bool _retrying = false;

  Future<void> _copyError(BuildContext context, AppErrorDetails error) async {
    await Clipboard.setData(ClipboardData(text: error.toClipboardString()));
  }

  Future<void> _showDetails(BuildContext context, AppErrorDetails error) async {
    final full = error.toClipboardString();
    final technicalSections = <Widget>[
      _Section(label: 'Error real', value: error.primaryTechnicalMessage),
      if (error.message.trim().isNotEmpty &&
          error.message.trim() != error.primaryTechnicalMessage)
        _Section(label: 'Resumen tecnico', value: error.message),
      if ((error.endpointUrl ?? '').trim().isNotEmpty)
        _Section(label: 'Endpoint', value: error.endpointUrl!),
      if ((error.method ?? '').trim().isNotEmpty)
        _Section(label: 'Método', value: error.method!),
      if ((error.apiResponse ?? '').trim().isNotEmpty)
        _Section(label: 'Respuesta API', value: error.apiResponse!),
      if ((error.technicalDetails ?? '').trim().isNotEmpty)
        _Section(label: 'Detalle técnico', value: error.technicalDetails!),
      if (error.stackTrace.trim().isNotEmpty)
        _Section(label: 'Stack trace', value: error.stackTrace),
    ];
    final severityColor = _severityColor(context, error.severity);
    final severityIcon = _severityIcon(error.severity);
    final canRetry = error.onRetry != null;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        final mediaQuery = MediaQuery.of(dialogContext);
        final maxDialogHeight =
            mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 500,
                  maxHeight: maxDialogHeight.clamp(280.0, 760.0),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.985),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.zero,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    20,
                                    22,
                                    18,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        severityColor.withValues(alpha: 0.14),
                                        scheme.surface,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              severityColor.withValues(
                                                alpha: 0.22,
                                              ),
                                              severityColor.withValues(
                                                alpha: 0.08,
                                              ),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Icon(
                                          severityIcon,
                                          color: severityColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              error.title,
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.2,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _subtitleFor(error),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _OverlayCloseButton(
                                        onTap: () {
                                          AppErrorReporter.instance.clear();
                                          Navigator.of(
                                            dialogContext,
                                            rootNavigator: true,
                                          ).pop();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    18,
                                    22,
                                    10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        error.userMessage,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              height: 1.45,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.92),
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      _Section(
                                        label: 'Error real para copiar',
                                        value: error.primaryTechnicalMessage,
                                        dense: true,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest
                                              .withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.shield_outlined,
                                              size: 18,
                                              color: severityColor,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                canRetry
                                                    ? 'Puedes intentar nuevamente sin salir de la pantalla.'
                                                    : 'Tu informacion sigue protegida y ya puedes copiar el error completo para revisarlo.',
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ...technicalSections,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: full),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_rounded),
                                label: const Text('Copiar reporte'),
                              ),
                              if (canRetry)
                                OutlinedButton.icon(
                                  onPressed: _retrying
                                      ? null
                                      : () async {
                                          setDialogState(
                                            () => _retrying = true,
                                          );
                                          try {
                                            await error.onRetry!.call();
                                            AppErrorReporter.instance.clear();
                                            if (!dialogContext.mounted) return;
                                            Navigator.of(
                                              dialogContext,
                                              rootNavigator: true,
                                            ).pop();
                                          } catch (retryError, retryStack) {
                                            AppErrorReporter.instance.record(
                                              retryError,
                                              retryStack,
                                              context: error.context,
                                              title: error.title,
                                              userMessage: error.userMessage,
                                              technicalDetails:
                                                  error.technicalDetails,
                                              severity: error.severity,
                                              dedupeKey:
                                                  'retry-${error.eventId}',
                                              retryLabel: error.retryLabel,
                                              onRetry: error.onRetry,
                                            );
                                          } finally {
                                            if (dialogContext.mounted) {
                                              setDialogState(
                                                () => _retrying = false,
                                              );
                                            } else {
                                              _retrying = false;
                                            }
                                          }
                                        },
                                  icon: _retrying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh_rounded),
                                  label: Text(error.retryLabel ?? 'Reintentar'),
                                ),
                              FilledButton.icon(
                                onPressed: () {
                                  AppErrorReporter.instance.clear();
                                  Navigator.of(
                                    dialogContext,
                                    rootNavigator: true,
                                  ).pop();
                                },
                                icon: const Icon(Icons.check_rounded),
                                label: Text(
                                  canRetry ? 'Ahora no' : 'Entendido',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _severityColor(BuildContext context, AppErrorSeverity severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case AppErrorSeverity.warning:
        return Colors.orange.shade700;
      case AppErrorSeverity.fatal:
        return scheme.error;
      case AppErrorSeverity.error:
        return scheme.error;
    }
  }

  IconData _severityIcon(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.warning:
        return Icons.warning_amber_rounded;
      case AppErrorSeverity.fatal:
        return Icons.dangerous_rounded;
      case AppErrorSeverity.error:
        return Icons.error_outline_rounded;
    }
  }

  String _subtitleFor(AppErrorDetails error) {
    if (error.onRetry != null) {
      return 'Puedes intentar nuevamente ahora.';
    }

    switch (error.severity) {
      case AppErrorSeverity.warning:
        return 'La aplicacion puede seguir funcionando.';
      case AppErrorSeverity.fatal:
        return 'Necesita atencion antes de continuar.';
      case AppErrorSeverity.error:
        return 'El sistema detecto una incidencia controlada.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppErrorDetails?>(
      valueListenable: AppErrorReporter.instance.lastError,
      builder: (context, error, _) {
        if (error == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final severityColor = _severityColor(context, error.severity);
        final severityIcon = _severityIcon(error.severity);

        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth >= 700;

        if (isDesktop) {
          // Desktop: small toast at bottom-right, never covers main content
          return SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, bottom: 16),
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: 0.98),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                severityIcon,
                                size: 15,
                                color: severityColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  error.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              _OverlayCloseButton(
                                compact: true,
                                onTap: AppErrorReporter.instance.clear,
                              ),
                            ],
                          ),
                          Text(
                            error.userMessage,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _copyError(context, error),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                child: const Text('Copiar'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton.tonal(
                                onPressed: () => _showDetails(context, error),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                child: const Text('Ver error'),
                              ),
                            ],
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

        // Mobile: small elegant centered card
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(severityIcon, size: 14, color: severityColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              error.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: AppErrorReporter.instance.clear,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        error.userMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _copyError(context, error),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Copiar'),
                          ),
                          const SizedBox(width: 4),
                          FilledButton.tonal(
                            onPressed: () => _showDetails(context, error),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Ver error'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String value;
  final bool dense;

  const _Section({
    required this.label,
    required this.value,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(dense ? 10 : 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              softWrap: true,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayCloseButton extends StatelessWidget {
  const _OverlayCloseButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = compact ? 28.0 : 36.0;
    final iconSize = compact ? 14.0 : 18.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close_rounded,
            size: iconSize,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
