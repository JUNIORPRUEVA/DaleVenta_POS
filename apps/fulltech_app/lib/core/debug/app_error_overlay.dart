import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routing/app_router.dart';
import 'app_diagnostics.dart';
import 'app_error_diagnostics_sheet.dart';
import 'app_error_reporter.dart';

/// Ancho lógico desde el cual el aviso se ancla **abajo a la derecha**.
///
/// Es el mismo umbral con el que el POS decide que está en escritorio
/// (`global_ai_assistant_entry_point.dart`). Por debajo, el pie de la pantalla
/// lo ocupan Cobrar/Cotizar y taparlos sí interrumpiría una venta.
const double kDesktopErrorNoticeMinWidth = 900;

/// Altura reservada en la parte inferior de la ventana para la barra de
/// acciones del POS (Cobrar / Guardar / Limpiar).
///
/// El aviso se ancla **por encima** de esa franja: así queda abajo a la derecha
/// (lo discreto) sin tapar nunca los controles con los que el comercio cobra.
const double kErrorNoticeBottomReservedHeight = 80;

/// Compact, non-blocking notification for incidents.
///
/// Placement: desktop (width >= [kDesktopErrorNoticeMinWidth]) anchors it to the
/// bottom-right corner, above the POS action bar; compact layouts keep it at the
/// top because the cart footer occupies the bottom of the screen.
///
/// Customer-facing rules:
/// - Never shows technical information (exception text, endpoints, status
///   codes, stack traces).
/// - Never uses a centered blocking modal for recoverable errors.
/// - Only one incident is visible at a time (the reporter keeps a single slot
///   and deduplicates repeated incidents).
/// - Technical diagnostics are reachable only when [kAppDiagnosticsUiEnabled]
///   is true, which is never the case in production builds.
class AppErrorOverlay extends StatefulWidget {
  const AppErrorOverlay({super.key});

  @override
  State<AppErrorOverlay> createState() => _AppErrorOverlayState();
}

class _AppErrorOverlayState extends State<AppErrorOverlay> {
  bool _retrying = false;
  AppErrorDetails? _visibleError;

  @override
  void initState() {
    super.initState();
    _visibleError = AppErrorReporter.instance.lastError.value;
    AppErrorReporter.instance.lastError.addListener(_handleErrorChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    AppErrorReporter.instance.lastError.removeListener(_handleErrorChanged);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  void _handleErrorChanged() {
    final next = AppErrorReporter.instance.lastError.value;
    if (_visibleError == null && next != null) {
      _retrying = false;
    }
    _visibleError = next;
  }

  /// ESC dismisses the notification when the incident is not critical.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    final error = _visibleError;
    if (error == null) return false;
    if (error.severity == AppErrorSeverity.fatal) return false;
    AppErrorReporter.instance.clear();
    return true;
  }

  Future<void> _retry(AppErrorDetails error) async {
    final retry = error.onRetry;
    if (retry == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      await retry();
      AppErrorReporter.instance.clear();
    } catch (retryError, retryStack) {
      AppErrorReporter.instance.record(
        retryError,
        retryStack,
        context: error.context,
        title: error.title,
        userMessage: error.userMessage,
        technicalDetails: error.technicalDetails,
        severity: error.severity,
        dedupeKey: 'retry-${error.eventId}',
        retryLabel: error.retryLabel,
        onRetry: error.onRetry,
      );
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      } else {
        _retrying = false;
      }
    }
  }

  Future<void> _openDiagnostics(AppErrorDetails error) async {
    final navigatorContext = appRootNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    await showAppErrorDiagnosticsDialog(navigatorContext, error);
  }

  Color _severityColor(BuildContext context, AppErrorSeverity severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case AppErrorSeverity.warning:
        // Neutro a propósito: un fallo recuperable (por ejemplo el actualizador)
        // no debe alarmar al comercio. `error` y `fatal` conservan el rojo del
        // tema porque exigen intervención.
        return scheme.onSurfaceVariant;
      case AppErrorSeverity.fatal:
      case AppErrorSeverity.error:
        return scheme.error;
    }
  }

  IconData _severityIcon(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.warning:
        return Icons.info_outline_rounded;
      case AppErrorSeverity.fatal:
        return Icons.dangerous_rounded;
      case AppErrorSeverity.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppErrorDetails?>(
      valueListenable: AppErrorReporter.instance.lastError,
      builder: (context, error, _) {
        if (error == null) return const SizedBox.shrink();
        return _NotificationBanner(
          error: error,
          retrying: _retrying,
          severityColor: _severityColor(context, error.severity),
          severityIcon: _severityIcon(error.severity),
          onRetry: error.onRetry == null ? null : () => _retry(error),
          onDismiss: AppErrorReporter.instance.clear,
          onDiagnostics: kAppDiagnosticsUiEnabled
              ? () => _openDiagnostics(error)
              : null,
        );
      },
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.error,
    required this.retrying,
    required this.severityColor,
    required this.severityIcon,
    required this.onRetry,
    required this.onDismiss,
    required this.onDiagnostics,
  });

  final AppErrorDetails error;
  final bool retrying;
  final Color severityColor;
  final IconData severityIcon;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;
  final VoidCallback? onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final isCompact = width < 600;
    final topOffset = mediaQuery.viewPadding.top + kToolbarHeight + 8;
    // Escritorio (Windows): el aviso se ancla en la esquina inferior derecha,
    // lejos de la barra superior y del buscador. En layouts compactos el pie de
    // la pantalla lo ocupan Cobrar/Cotizar, así que ahí se mantiene arriba.
    final isDesktopLayout = width >= kDesktopErrorNoticeMinWidth;
    // Aviso **recuperable** (`warning`) y **sin acción posible**: dos líneas
    // exactas, sin fila de acciones. Un fallo del actualizador no interrumpe: el
    // comercio solo necesita saber que puede seguir trabajando. Si el usuario SÍ
    // puede actuar (reintentar una impresión, por ejemplo) se mantiene el diseño
    // completo, y `error`/`fatal` conservan siempre su fila de acciones.
    final isNeutralNotice =
        error.severity == AppErrorSeverity.warning && onRetry == null;
    final showActions =
        onRetry != null || (onDiagnostics != null && !isNeutralNotice);

    final card = Semantics(
      liveRegion: true,
      container: true,
      label: '${error.title}. ${error.userMessage}',
      child: Material(
        color: scheme.surface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(isNeutralNotice ? 12 : 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isNeutralNotice ? 12 : 14),
            border: Border(left: BorderSide(color: severityColor, width: 3)),
          ),
          padding: isNeutralNotice
              ? const EdgeInsets.fromLTRB(10, 6, 2, 6)
              : const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: isNeutralNotice
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: isNeutralNotice ? 0 : 1),
                child: Icon(
                  severityIcon,
                  size: isNeutralNotice ? 16 : 18,
                  color: severityColor,
                ),
              ),
              SizedBox(width: isNeutralNotice ? 7 : 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error.title,
                      maxLines: isNeutralNotice ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: isNeutralNotice
                          ? TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              letterSpacing: 0,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            )
                          : theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                    ),
                    if (error.userMessage.trim().isNotEmpty) ...[
                      SizedBox(height: isNeutralNotice ? 1 : 2),
                      Text(
                        error.userMessage,
                        maxLines: isNeutralNotice ? 1 : (isCompact ? 3 : 2),
                        overflow: TextOverflow.ellipsis,
                        style: isNeutralNotice
                            ? TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              )
                            : theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                      ),
                    ],
                    if (showActions) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (onRetry != null)
                            _BannerAction(
                              onPressed: retrying ? null : onRetry,
                              busy: retrying,
                              filled: true,
                              label: error.retryLabel ?? 'Reintentar',
                            ),
                          if (onDiagnostics != null)
                            _BannerAction(
                              onPressed: onDiagnostics,
                              filled: false,
                              label: 'Detalles',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // SIN `tooltip:` a propósito.
              //
              // Este banner vive en el `builder` de MaterialApp, es
              // decir POR ENCIMA del Navigator, donde no existe ningún
              // Overlay. `Tooltip`/`RawTooltip` exige un Overlay
              // ancestro y, al mostrarse (hover/tap), lanza un
              // FlutterError duro (también en release) que taparía el
              // error original con un segundo error del propio sistema
              // de errores. La accesibilidad se conserva etiquetando
              // el icono (`Icon.semanticLabel`), que no necesita
              // Overlay.
              IconButton(
                onPressed: onDismiss,
                padding: isNeutralNotice ? EdgeInsets.zero : null,
                constraints: isNeutralNotice
                    ? const BoxConstraints(minWidth: 28, minHeight: 28)
                    : null,
                visualDensity: VisualDensity.compact,
                iconSize: isNeutralNotice ? 16 : 18,
                icon: Icon(
                  Icons.close_rounded,
                  semanticLabel: 'Cerrar',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isDesktopLayout) {
      // El desplazamiento respeta la barra de tareas y el escalado DPI, y sube
      // por encima de la franja de acciones del POS. El aviso ocupa SÓLO su
      // propia caja: nunca captura clics fuera de ella, así que no bloquea la
      // navegación ni una venta en curso.
      return Positioned(
        right: 16 + mediaQuery.viewPadding.right,
        bottom:
            16 +
            mediaQuery.viewPadding.bottom +
            kErrorNoticeBottomReservedHeight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: card,
        ),
      );
    }

    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerAction extends StatelessWidget {
  const _BannerAction({
    required this.onPressed,
    required this.label,
    required this.filled,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (filled) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          textStyle: const TextStyle(fontSize: 12),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      );
    }
    return TextButton(onPressed: onPressed, style: style, child: child);
  }
}
