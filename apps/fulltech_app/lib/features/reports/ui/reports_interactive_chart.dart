import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money_formatters.dart';

/// Presentation only: values and dates are the report's server series.
class ReportsInteractiveChart extends StatefulWidget {
  const ReportsInteractiveChart({
    super.key,
    required this.points,
    required this.label,
    required this.color,
    this.line = false,
  });
  final List<({String label, double value})> points;
  final String label;
  final Color color;
  final bool line;
  @override
  State<ReportsInteractiveChart> createState() =>
      _ReportsInteractiveChartState();
}

class _ReportsInteractiveChartState extends State<ReportsInteractiveChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant ReportsInteractiveChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _selected = null;
  }

  void _select(double x, double width) {
    if (widget.points.isEmpty) return;
    final available = math.max(1.0, width - 82);
    final fraction = ((x - 66) / available).clamp(0.0, 1.0);
    final index = widget.line
        ? (fraction * (widget.points.length - 1)).round()
        : (fraction * widget.points.length).floor().clamp(
            0,
            widget.points.length - 1,
          );
    if (_selected != index) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const Center(
        child: Text(
          'Sin datos en el rango seleccionado',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      );
    }
    final selected = _selected == null ? null : widget.points[_selected!];
    return LayoutBuilder(
      builder: (context, constraints) => Semantics(
        label:
            '${widget.label}. ${widget.points.length} puntos. Usa las flechas para consultar los valores.',
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final direction = event.logicalKey == LogicalKeyboardKey.arrowRight
                ? 1
                : event.logicalKey == LogicalKeyboardKey.arrowLeft
                ? -1
                : 0;
            if (direction == 0) return KeyEventResult.ignored;
            setState(
              () => _selected = ((_selected ?? -1) + direction).clamp(
                0,
                widget.points.length - 1,
              ),
            );
            return KeyEventResult.handled;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) =>
                _select(event.localPosition.dx, constraints.maxWidth),
            onExit: (_) => setState(() => _selected = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _select(details.localPosition.dx, constraints.maxWidth),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SeriesPainter(
                        points: widget.points,
                        color: widget.color,
                        line: widget.line,
                        selected: _selected,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: math.max(0, constraints.maxWidth - 66),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        color: selected == null
                            ? Colors.transparent
                            : AppColors.surfaceSubtle,
                        child: Text(
                          selected == null
                              ? 'Toca o pasa el cursor para explorar'
                              : '${_dateLabel(selected.label)} · ${formatRdCurrencyAccounting(selected.value)}',
                          key: ValueKey('reports-chart-value-${widget.label}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: selected == null
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(String label) {
  final date = DateTime.tryParse(label);
  return date == null ? label : DateFormat('dd/MM/yyyy').format(date);
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.points,
    required this.color,
    required this.line,
    required this.selected,
  });
  final List<({String label, double value})> points;
  final Color color;
  final bool line;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      66,
      38,
      math.max(67, size.width - 16),
      math.max(39, size.height - 30),
    );
    final min = points.fold<double>(0, (v, p) => math.min(v, p.value));
    final max = points.fold<double>(0, (v, p) => math.max(v, p.value));
    final span = max == min ? 1.0 : max - min;
    double y(double value) => rect.bottom - (value - min) / span * rect.height;
    double x(int index) => line
        ? rect.left +
              (points.length == 1
                  ? rect.width / 2
                  : rect.width * index / (points.length - 1))
        : rect.left + rect.width * (index + .5) / points.length;
    final zero = y(0);
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = .7;
    final formatter = NumberFormat.compact(locale: 'en_US');
    void text(String value, Offset at, {double width = 62}) {
      final painter = TextPainter(
        textDirection: ui.TextDirection.ltr,
        text: TextSpan(
          text: value,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width);
      painter.paint(canvas, at);
    }

    for (var i = 0; i <= 4; i++) {
      final value = min + span * i / 4;
      final yy = y(value);
      canvas.drawLine(Offset(rect.left, yy), Offset(rect.right, yy), grid);
      text('RD\$ ${formatter.format(value)}', Offset(0, yy - 6));
    }
    canvas.drawLine(
      Offset(rect.left, zero),
      Offset(rect.right, zero),
      Paint()
        ..color = AppColors.textMuted
        ..strokeWidth = .8,
    );
    final labelStep = math.max(
      1,
      (points.length / math.max(2, rect.width / 70)).ceil(),
    );
    for (var i = 0; i < points.length; i++) {
      final negative = points[i].value < 0;
      final ink = negative ? AppColors.error : color;
      final xx = x(i), yy = y(points[i].value);
      if (!line) {
        final width = math.min(32.0, rect.width / points.length * .6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              xx - width / 2,
              math.min(yy, zero),
              xx + width / 2,
              math.max(yy, zero),
            ),
            const Radius.circular(2),
          ),
          Paint()
            ..color = selected == null || selected == i
                ? ink
                : ink.withValues(alpha: .35),
        );
      } else {
        if (i > 0) {
          canvas.drawLine(
            Offset(x(i - 1), y(points[i - 1].value)),
            Offset(xx, yy),
            Paint()
              ..color = ink
              ..strokeWidth = 2.3
              ..strokeCap = StrokeCap.round,
          );
        }
        if (points.length == 1 || selected == i) {
          canvas.drawCircle(Offset(xx, yy), 4, Paint()..color = ink);
        }
      }
      if (i % labelStep == 0) {
        final date = DateTime.tryParse(points[i].label);
        text(
          date == null ? points[i].label : DateFormat('dd/MM').format(date),
          Offset((xx - 20).clamp(rect.left, rect.right - 42), rect.bottom + 10),
          width: 48,
        );
      }
    }
    if (selected != null) {
      final xx = x(selected!);
      canvas.drawLine(
        Offset(xx, rect.top),
        Offset(xx, rect.bottom),
        Paint()
          ..color = color.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(xx, y(points[selected!].value)),
        4,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.color != color ||
      old.line != line;
}
