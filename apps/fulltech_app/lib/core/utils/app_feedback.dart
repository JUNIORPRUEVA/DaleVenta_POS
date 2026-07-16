import 'package:flutter/material.dart';

import '../debug/trace_log.dart';
import '../widgets/fulltech_dialog.dart';

class AppFeedback {
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

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    return context;
  }
}
