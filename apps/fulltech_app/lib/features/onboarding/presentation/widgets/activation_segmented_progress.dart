import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Barra de progreso segmentada: un segmento por tarea de la fase.
///
/// Se eligió frente a un porcentaje porque comunica cuántas cosas quedan, no
/// cuánto se ha avanzado. Los tres estados son distinguibles por color y por
/// semántica:
///  - resuelta por datos → verde
///  - omitida           → gris claro con borde discontinuo lógico (tono medio)
///  - pendiente         → gris suave
class ActivationSegmentedProgress extends StatelessWidget {
  const ActivationSegmentedProgress({
    super.key,
    required this.tasks,
    this.height = 6,
    this.gap = 4,
  });

  /// Lista ordenada de estados: `done`, `skipped`, `pending`.
  final List<ActivationTaskVisualState> tasks;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final done = tasks.where((s) => s == ActivationTaskVisualState.done).length;
    final total = tasks.length;
    return Semantics(
      label: '$done de $total completadas',
      child: Row(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: height,
                decoration: BoxDecoration(
                  color: _colorFor(tasks[i]),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _colorFor(ActivationTaskVisualState state) {
    switch (state) {
      case ActivationTaskVisualState.done:
        // Identidad azul FullPOS: el avance se marca en azul corporativo, no
        // en verde. El verde queda reservado a confirmaciones semánticas de
        // otras pantallas.
        return AppColors.primary;
      case ActivationTaskVisualState.skipped:
        return AppColors.surfaceMuted;
      case ActivationTaskVisualState.pending:
        return AppColors.border;
    }
  }
}

enum ActivationTaskVisualState { done, skipped, pending }

/// Anillo compacto de progreso para el acceso flotante.
class ActivationProgressRing extends StatefulWidget {
  const ActivationProgressRing({
    super.key,
    required this.done,
    required this.total,
    this.size = 18,
    this.strokeWidth = 2.4,
    this.animated = false,
  });

  final int done;
  final int total;
  final double size;
  final double strokeWidth;

  /// Añade un arco que crece y se reinicia en bucle: indica que el asistente
  /// está disponible sin llegar nunca a completarse.
  final bool animated;

  @override
  State<ActivationProgressRing> createState() => _ActivationProgressRingState();
}

class _ActivationProgressRingState extends State<ActivationProgressRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(ActivationProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) _syncController();
  }

  void _syncController() {
    if (widget.animated) {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      );
      if (!_controller!.isAnimating) _controller!.repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.total <= 0
        ? 0.0
        : (widget.done / widget.total).clamp(0.0, 1.0);
    final controller = _controller;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: controller == null
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: widget.strokeWidth,
                backgroundColor: AppColors.primarySoft,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            )
          // RepaintBoundary: el bucle sólo repinta este anillo, no el botón.
          : RepaintBoundary(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => CustomPaint(
                  painter: _LiveRingPainter(
                    t: controller.value,
                    ratio: ratio,
                    strokeWidth: widget.strokeWidth,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Dibuja el anillo base, el progreso real tenue y un arco vivo que crece y
/// se desvanece sin cerrar nunca el círculo.
class _LiveRingPainter extends CustomPainter {
  const _LiveRingPainter({
    required this.t,
    required this.ratio,
    required this.strokeWidth,
  });

  final double t;
  final double ratio;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AppColors.primarySoft;
    canvas.drawCircle(center, radius, base);

    if (ratio > 0) {
      final donePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary.withValues(alpha: 0.35);
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * ratio, false, donePaint);
    }

    // De 45° a 272°: siempre deja un hueco, así nunca parece terminado.
    final eased = Curves.easeInOut.transform(t);
    final sweep = (0.125 + 0.63 * eased) * 2 * math.pi;
    final start = -math.pi / 2 + (2 * math.pi * eased * 0.6);
    final pulse = 0.25 + 0.75 * math.sin(math.pi * t);
    final live = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary.withValues(alpha: pulse.clamp(0.15, 1.0));
    canvas.drawArc(rect, start, sweep, false, live);
  }

  @override
  bool shouldRepaint(_LiveRingPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.ratio != ratio ||
      oldDelegate.strokeWidth != strokeWidth;
}
