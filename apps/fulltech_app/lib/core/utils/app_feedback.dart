import 'dart:async';

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
  });

  final String title;
  final String body;
  final AppFeedbackKind kind;
}

class AppFeedback {
  static OverlayEntry? _persistentEntry;

  /// Avisos flotantes activos. Se limita el apilado para no tapar la pantalla.
  static final ValueNotifier<List<_ToastItem>> _toasts =
      ValueNotifier<List<_ToastItem>>(const <_ToastItem>[]);
  static OverlayEntry? _toastEntry;
  static const int _maxVisibleToasts = 3;

  /// Aviso flotante en la esquina superior derecha.
  ///
  /// No es un modal ni una barra inferior: es un aviso pequeño que no bloquea
  /// formularios ni botones, desaparece solo cuando el mensaje es informativo o
  /// de éxito, y en los errores dura lo suficiente para leerse y cerrarse a mano.
  ///
  /// `dedupeKey` evita apilar el mismo aviso cuando una reconstrucción de
  /// Flutter vuelve a pedirlo: se reinicia su tiempo en lugar de duplicarlo.
  static void showToast(
    BuildContext context, {
    required String title,
    required String body,
    AppFeedbackKind kind = AppFeedbackKind.info,
    Duration? duration,
    String? dedupeKey,
    BuildContext? fallbackContext,
    String scope = 'AppFeedback',
  }) {
    final overlay = _resolveOverlay(context) ?? _resolveOverlay(fallbackContext);
    if (overlay == null) {
      // Sin overlay no se sustituye por un diálogo: un aviso nunca debe
      // bloquear la pantalla que el usuario está usando.
      TraceLog.log(scope, 'toast dropped: no overlay available');
      return;
    }
    showToastOnOverlay(
      overlay,
      title: title,
      body: body,
      kind: kind,
      duration: duration,
      dedupeKey: dedupeKey,
      scope: scope,
    );
  }

  /// Igual que [showToast], pero sobre un `OverlayState` ya resuelto.
  ///
  /// Sirve cuando el aviso se muestra después de cerrar una pantalla: el
  /// `OverlayState` del `Navigator` raíz sigue siendo válido aunque el widget
  /// que lo pidió ya no exista.
  static void showToastOnOverlay(
    OverlayState? overlay, {
    required String title,
    required String body,
    AppFeedbackKind kind = AppFeedbackKind.info,
    Duration? duration,
    String? dedupeKey,
    String scope = 'AppFeedback',
  }) {
    if (overlay == null) {
      TraceLog.log(scope, 'toast dropped: overlay is null');
      return;
    }

    final notification = AppFeedbackNotification(
      title: title,
      body: body,
      kind: kind,
    );
    final hold = duration ?? _holdFor(kind);
    final id = dedupeKey ?? '${kind.name}|$title|$body';

    final next = List<_ToastItem>.of(_toasts.value);
    final existingIndex = next.indexWhere((item) => item.id == id);
    if (existingIndex >= 0) {
      // El mismo aviso repetido se reemplaza por una instancia nueva: la pila
      // reinicia su tiempo en lugar de duplicarlo.
      next.removeAt(existingIndex);
      TraceLog.log(scope, 'toast deduped id="$id"');
    }
    next.add(
      _ToastItem(id: id, notification: notification, hold: hold),
    );

    while (next.length > _maxVisibleToasts) {
      next.removeAt(0);
    }

    _toasts.value = List<_ToastItem>.unmodifiable(next);
    _ensureToastEntry(overlay);
  }

  static Duration _holdFor(AppFeedbackKind kind) {
    switch (kind) {
      case AppFeedbackKind.success:
        return const Duration(seconds: 4);
      case AppFeedbackKind.info:
        return const Duration(seconds: 4);
      case AppFeedbackKind.warning:
        return const Duration(seconds: 6);
      case AppFeedbackKind.error:
        // Los errores se leen, no se parpadean: más tiempo y cierre manual.
        return const Duration(seconds: 10);
    }
  }

  static void _ensureToastEntry(OverlayState overlay) {
    final existing = _toastEntry;
    if (existing != null && existing.mounted) return;
    // Entrada de un árbol anterior (reconstrucción o cierre de la app): se
    // descarta en lugar de reutilizarla.
    _toastEntry = null;
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<List<_ToastItem>>(
        valueListenable: _toasts,
        builder: (context, items, __) => _ToastStack(
          items: items,
          onDismiss: _removeToast,
        ),
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }

  static void _removeToast(String id) {
    final next = _toasts.value
        .where((item) => item.id != id)
        .toList(growable: false);
    _toasts.value = next;
    if (next.isEmpty) _disposeToastEntry();
  }

  static void _disposeToastEntry() {
    final entry = _toastEntry;
    _toastEntry = null;
    // Retirar una entrada que ya no está montada lanzaría una aserción.
    if (entry != null && entry.mounted) entry.remove();
  }

  /// Retira todos los avisos visibles (cambio de pantalla, cierre de sesión).
  static void clearToasts() {
    _toasts.value = const <_ToastItem>[];
    _disposeToastEntry();
  }

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
    final cardWidth = (isNarrow ? availableWidth : 420.0)
        .clamp(0.0, 420.0)
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
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  AppFeedback._iconFor(notification.kind),
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar notificación',
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _backgroundFor(AppFeedbackKind kind) =>
      _softBackgroundFor(kind);
}

/// Fondo discreto del aviso, según su tipo. Compartido por las dos
/// presentaciones (tarjeta persistente y aviso flotante).
Color _softBackgroundFor(AppFeedbackKind kind) {
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

/// Un aviso flotante y el tiempo que debe permanecer visible.
class _ToastItem {
  const _ToastItem({
    required this.id,
    required this.notification,
    required this.hold,
  });

  final String id;
  final AppFeedbackNotification notification;
  final Duration hold;
}

/// Pila de avisos en la esquina superior derecha.
///
/// Los temporizadores viven en el `State` para que se cancelen al desmontar:
/// un `Timer` estático que sobreviva al árbol de widgets es una fuga real.
class _ToastStack extends StatefulWidget {
  const _ToastStack({required this.items, required this.onDismiss});

  final List<_ToastItem> items;
  final void Function(String id) onDismiss;

  @override
  State<_ToastStack> createState() => _ToastStackState();
}

class _ToastStackState extends State<_ToastStack> {
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, _ToastItem> _scheduled = <String, _ToastItem>{};

  @override
  void initState() {
    super.initState();
    _syncTimers();
  }

  @override
  void didUpdateWidget(covariant _ToastStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimers();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _scheduled.clear();
    super.dispose();
  }

  void _syncTimers() {
    final visible = <String, _ToastItem>{
      for (final item in widget.items) item.id: item,
    };
    for (final id in _timers.keys.toList(growable: false)) {
      if (!visible.containsKey(id)) {
        _timers.remove(id)?.cancel();
        _scheduled.remove(id);
      }
    }
    for (final entry in visible.entries) {
      if (identical(_scheduled[entry.key], entry.value)) continue;
      // Aviso nuevo, o el mismo repetido: se reinicia su tiempo.
      _timers.remove(entry.key)?.cancel();
      _scheduled[entry.key] = entry.value;
      final id = entry.key;
      _timers[id] = Timer(entry.value.hold, () {
        _timers.remove(id);
        _scheduled.remove(id);
        widget.onDismiss(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 640;
    final rightMargin = (narrow ? 12.0 : 24.0) + media.padding.right;
    final leftMargin = narrow ? 12.0 : 24.0;
    // Debajo de la barra superior estándar para no tapar encabezados.
    final top = media.padding.top + kToolbarHeight + (narrow ? 8.0 : 12.0);
    final available = media.size.width - rightMargin - leftMargin;
    final width = (narrow ? available : 360.0).clamp(200.0, 360.0).toDouble();

    return Positioned(
      top: top,
      right: rightMargin,
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items) ...[
              _ToastCard(
                notification: item.notification,
                onClose: () => widget.onDismiss(item.id),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso pequeño: párrafo corto, icono por tipo y cierre manual.
class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.notification, required this.onClose});

  final AppFeedbackNotification notification;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppFeedback._colorFor(notification.kind);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        key: ValueKey<String>('app_feedback_toast_${notification.title}'),
        color: AppColors.surface,
        elevation: 8,
        shadowColor: AppColors.shadow,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: _softBackgroundFor(notification.kind),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  AppFeedback._iconFor(notification.kind),
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      softWrap: true,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.3,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar aviso',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
