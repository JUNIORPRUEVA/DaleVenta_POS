import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/utils/app_feedback.dart';

class ProductLifecycleFeedback {
  static OverlayEntry? _notice;
  static Timer? _noticeTimer;
  static void dismissNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    final entry = _notice;
    _notice = null;
    if (entry != null && entry.mounted) entry.remove();
  }

  static String title(String action) => switch (action) {
    'delete' => 'Eliminar producto',
    'annul' => 'Anular alta',
    'restore' => 'Restaurar producto',
    _ => 'Archivar producto',
  };
  static String label(String action) => switch (action) {
    'delete' => 'Eliminar',
    'annul' => 'Anular alta',
    'restore' => 'Restaurar',
    _ => 'Archivar',
  };
  static String message(String action) => switch (action) {
    'delete' =>
      'Se eliminará este producto sin existencias ni historial. Esta acción es definitiva.',
    'annul' =>
      'Se compensará únicamente la carga inicial y se retirará el producto. El Kardex y el código se conservarán. Esta acción no se puede deshacer.',
    'restore' =>
      'Volverá al catálogo con el mismo código, existencias e historial. Se comprobará el límite del plan.',
    _ =>
      'Se ocultará para nuevas operaciones. Sus existencias e historial se conservarán.',
  };
  static Future<bool?> confirm(BuildContext context, String action) => _confirm(
    context,
    title: title(action),
    message: message(action),
    confirmText: label(action),
  );
  static String success(String action) => switch (action) {
    'delete' => 'Producto eliminado',
    'annul' => 'Alta anulada',
    'restore' => 'Producto restaurado',
    _ => 'Producto archivado',
  };
  static void notice(
    BuildContext context,
    String text, {
    bool warning = false,
  }) {
    dismissNotice();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _notice = OverlayEntry(
      builder: (context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) => AppFeedbackNotice(
          notification: AppFeedbackNotification(
            title: warning ? 'Atención' : 'Listo',
            body: text,
            kind: warning ? AppFeedbackKind.warning : AppFeedbackKind.success,
            compact: true,
            paragraph: true,
          ),
          onClose: dismissNotice,
          bottomRight: true,
          animationProgress: progress,
        ),
      ),
    );
    overlay.insert(_notice!);
    _noticeTimer = Timer(Duration(seconds: warning ? 6 : 4), dismissNotice);
  }

  static Future<bool?> confirmBulk(
    BuildContext context, {
    required bool archive,
    required int eligible,
    required int total,
  }) => _confirm(
    context,
    title: archive ? 'Archivar selección' : 'Eliminar selección',
    message:
        '$eligible de $total productos aptos.\n${archive ? 'Conservarán existencias e historial.' : 'Solo se eliminarán productos sin existencias ni historial.'}\n${total - eligible} se conservarán sin cambios. Se volverá a comprobar cada producto.',
    confirmText: archive ? 'Archivar' : 'Eliminar',
  );

  static Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Text(title),
      scrollable: true,
      content: Text(message),
      actions: [
        TextButton(
          style: TextButton.styleFrom(shape: const RoundedRectangleBorder()),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
}

class ProductLifecycleResultsDialog extends StatelessWidget {
  const ProductLifecycleResultsDialog({super.key, required this.results});
  final List<String> results;
  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: const RoundedRectangleBorder(),
    title: const Text('Resultado por producto'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(child: Text(results.join('\n\n'))),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
