import 'package:flutter/material.dart';

import '../debug/trace_log.dart';
import '../theme/app_colors.dart';
import '../widgets/fulltech_dialog.dart';

enum AppFeedbackKind { success, warning, error, info }

class AppFeedbackNotification {
  const AppFeedbackNotification({
    required this.title,
    required this.body,
    this.kind = AppFeedbackKind.info,
    this.compact = false,
  });

  final String title;
  final String body;
  final AppFeedbackKind kind;
  final bool compact;
}

class AppFeedback {
  static OverlayEntry? _persistentEntry;

  static Future<void> showInfo(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    return _showMessage(
      context,
      message,
      fallbackContext: fallbackContext,
      scope: scope,
    );
  }

  static Future<void> showError(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    return _showMessage(
      context,
      message,
      fallbackContext: fallbackContext,
      scope: scope,
      isError: true,
    );
  }

  static void showPersistentNotification(
    BuildContext context,
    AppFeedbackNotification notification, {
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    final seq = TraceLog.nextSeq();
    TraceLog.log(
      scope,
      'persistent feedback requested title="${notification.title}" primaryMounted=${context.mounted} fallbackMounted=${fallbackContext?.mounted ?? false}',
      seq: seq,
    );

    final overlay =
        _resolveOverlay(context) ?? _resolveOverlay(fallbackContext);
    if (overlay == null) {
      TraceLog.log(scope, 'persistent feedback fallback via dialog', seq: seq);
      final dialogContext =
          _resolveContext(fallbackContext) ?? _resolveContext(context);
      if (dialogContext == null) return;
      FullTechConfirmDialog.show(
        dialogContext,
        title: notification.title,
        message: notification.body,
        confirmText: 'Aceptar',
        cancelText: '',
        icon: _iconFor(notification.kind),
        iconColor: _colorFor(notification.kind),
      );
      return;
    }

    _persistentEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _PersistentFeedbackCard(
        notification: notification,
        onClose: () {
          if (_persistentEntry == entry) _persistentEntry = null;
          entry.remove();
        },
      ),
    );
    _persistentEntry = entry;
    overlay.insert(entry);
  }

  static void dismissPersistentNotification() {
    _persistentEntry?.remove();
    _persistentEntry = null;
  }

  static Future<void> _showMessage(
    BuildContext context,
    String message, {
    BuildContext? fallbackContext,
    required String scope,
    bool isError = false,
  }) async {
    final seq = TraceLog.nextSeq();
    TraceLog.log(
      scope,
      'feedback requested message="$message" primaryMounted=${context.mounted} fallbackMounted=${fallbackContext?.mounted ?? false}',
      seq: seq,
    );

    final messenger =
        _resolveMessenger(context) ?? _resolveMessenger(fallbackContext);
    if (messenger != null) {
      TraceLog.log(scope, 'feedback via SnackBar', seq: seq);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red.shade700 : null,
          ),
        );
      return;
    }

    final dialogContext =
        _resolveContext(fallbackContext) ?? _resolveContext(context);
    if (dialogContext == null) {
      TraceLog.log(
        scope,
        'feedback dropped: no valid context available',
        seq: seq,
      );
      return;
    }

    TraceLog.log(scope, 'feedback via FullTechDialog fallback', seq: seq);
    await FullTechConfirmDialog.show(
      dialogContext,
      title: isError ? 'Error' : 'Mensaje',
      message: message,
      confirmText: 'Aceptar',
      cancelText: '',
      icon: isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
      iconColor: isError
          ? FullTechDialogTokens.errorColor
          : FullTechDialogTokens.primaryButtonColor,
    );
  }

  static ScaffoldMessengerState? _resolveMessenger(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return ScaffoldMessenger.maybeOf(context);
  }

  static OverlayState? _resolveOverlay(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return Overlay.maybeOf(context, rootOverlay: true);
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return context;
  }

  static IconData _iconFor(AppFeedbackKind kind) {
    switch (kind) {
      case AppFeedbackKind.success:
        return Icons.check_circle_outline_rounded;
      case AppFeedbackKind.warning:
        return Icons.warning_amber_rounded;
      case AppFeedbackKind.error:
        return Icons.error_outline_rounded;
      case AppFeedbackKind.info:
        return Icons.info_outline_rounded;
    }
  }

  static Color _colorFor(AppFeedbackKind kind) {
    switch (kind) {
      case AppFeedbackKind.success:
        return AppColors.success;
      case AppFeedbackKind.warning:
        return AppColors.warning;
      case AppFeedbackKind.error:
        return AppColors.error;
      case AppFeedbackKind.info:
        return AppColors.secondary;
    }
  }
}

class _PersistentFeedbackCard extends StatelessWidget {
  const _PersistentFeedbackCard({
    required this.notification,
    required this.onClose,
  });

  final AppFeedbackNotification notification;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isNarrow = media.size.width < 640;
    // Notificaciones en la esquina SUPERIOR DERECHA en desktop, con posición
    // responsiva y segura en pantallas angostas. La tarjeta se coloca debajo
    // de la barra superior estándar (kToolbarHeight) para no tapar encabezados
    // ni AppBars, con separación segura de los bordes superior y derecho.
    final rightMargin = (isNarrow ? 12.0 : 24.0) + media.padding.right;
    final leftMargin = isNarrow ? 12.0 : 24.0;
    final top = media.padding.top + kToolbarHeight + (isNarrow ? 8.0 : 12.0);
    final availableWidth = media.size.width - rightMargin - leftMargin;
    final maxWidth = notification.compact ? 280.0 : 420.0;
    final cardWidth = (isNarrow ? availableWidth : maxWidth)
        .clamp(0.0, maxWidth)
        .toDouble();
    final color = AppFeedback._colorFor(notification.kind);
    final background = _backgroundFor(notification.kind);

    return Positioned(
      right: rightMargin,
      top: top,
      width: cardWidth,
      child: Material(
        key: const ValueKey('persistent_feedback_card'),
        color: AppColors.surface,
        elevation: 10,
        shadowColor: AppColors.shadow,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.34)),
          ),
          padding: notification.compact
              ? const EdgeInsets.fromLTRB(10, 7, 4, 7)
              : const EdgeInsets.fromLTRB(14, 12, 8, 14),
          child: Row(
            crossAxisAlignment: notification.compact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: notification.compact ? 0 : 2),
                child: Icon(
                  AppFeedback._iconFor(notification.kind),
                  color: color,
                  size: notification.compact ? 16 : 22,
                ),
              ),
              SizedBox(width: notification.compact ? 7 : 10),
              Expanded(
                child: notification.compact
                    ? Text(
                        '${notification.title}: ${notification.body}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            notification.body,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
              ),
              IconButton(
                tooltip: 'Cerrar notificación',
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: notification.compact ? 28 : 40,
                  height: notification.compact ? 28 : 40,
                ),
                iconSize: notification.compact ? 16 : 24,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _backgroundFor(AppFeedbackKind kind) {
    switch (kind) {
      case AppFeedbackKind.success:
        return AppColors.successSoft;
      case AppFeedbackKind.warning:
        return AppColors.warningSoft;
      case AppFeedbackKind.error:
        return AppColors.errorSoft;
      case AppFeedbackKind.info:
        return AppColors.surface;
    }
  }
}
