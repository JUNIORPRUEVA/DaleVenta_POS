import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error_reporter.dart';

/// Internal diagnostic surface for a captured incident.
///
/// IMPORTANT: This widget exposes technical information (raw exception text,
/// endpoint, stack trace). It must only be reachable when
/// `kAppDiagnosticsUiEnabled` is true, which is never the case in production
/// builds. See `app_diagnostics.dart`.
Future<void> showAppErrorDiagnosticsDialog(
  BuildContext context,
  AppErrorDetails error,
) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final scheme = theme.colorScheme;
      final mediaQuery = MediaQuery.of(dialogContext);
      final maxDialogHeight =
          mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32;
      final full = error.toClipboardString();

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: maxDialogHeight.clamp(280.0, 760.0),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    'Diagnóstico interno',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Section(
                          label: 'Error real',
                          value: error.primaryTechnicalMessage,
                        ),
                        if (error.message.trim().isNotEmpty &&
                            error.message.trim() !=
                                error.primaryTechnicalMessage)
                          _Section(
                            label: 'Resumen técnico',
                            value: error.message,
                          ),
                        _Section(label: 'Tipo', value: error.errorType),
                        if ((error.context ?? '').trim().isNotEmpty)
                          _Section(label: 'Contexto', value: error.context!),
                        if ((error.method ?? '').trim().isNotEmpty)
                          _Section(label: 'Método', value: error.method!),
                        if ((error.endpointUrl ?? '').trim().isNotEmpty)
                          _Section(label: 'Endpoint', value: error.endpointUrl!),
                        if ((error.apiResponse ?? '').trim().isNotEmpty)
                          _Section(
                            label: 'Respuesta API',
                            value: error.apiResponse!,
                          ),
                        if ((error.technicalDetails ?? '').trim().isNotEmpty)
                          _Section(
                            label: 'Detalle técnico',
                            value: error.technicalDetails!,
                          ),
                        if (error.stackTrace.trim().isNotEmpty)
                          _Section(
                            label: 'Stack trace',
                            value: error.stackTrace,
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: full));
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.maybeOf(
                            dialogContext,
                          )?.showSnackBar(
                            const SnackBar(
                              content: Text('Reporte copiado'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_rounded),
                        label: const Text('Copiar reporte'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(dialogContext, rootNavigator: true)
                                .pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Section extends StatelessWidget {
  final String label;
  final String value;

  const _Section({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
