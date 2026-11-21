import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

/// Obscures the POS while keeping the assistant's surface crisp.
class AiAssistantFocusBackdrop extends StatefulWidget {
  const AiAssistantFocusBackdrop({super.key, required this.onDismiss});
  final VoidCallback onDismiss;
  @override
  State<AiAssistantFocusBackdrop> createState() => _FocusBackdropState();
}

class _FocusBackdropState extends State<AiAssistantFocusBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this, duration: const Duration(seconds: 16),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }
  @override
  void dispose() { _motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.surface.withValues(alpha: .10),
            AppColors.primarySoft.withValues(alpha: .14),
            AppColors.primary.withValues(alpha: .035)],
        ))),
        RepaintBoundary(child: CustomPaint(painter: _BlueWaves(_motion))),
        ModalBarrier(color: Colors.transparent, dismissible: true,
          semanticsLabel: 'Cerrar FullPOS IA', onDismiss: widget.onDismiss),
      ]),
    ),
  );
}

class _BlueWaves extends CustomPainter {
  _BlueWaves(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  @override
  void paint(Canvas canvas, Size size) {
    for (var band = 0; band < 3; band++) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width + 16; x += 16) {
        final wave = math.sin(x / math.max(size.width, 1) * math.pi * 2 +
            motion.value * math.pi * 2 + band * 1.5);
        path.lineTo(x, size.height * (.48 + band * .12) + wave * size.height * .07);
      }
      path..lineTo(size.width, size.height)..close();
      canvas.drawPath(path, Paint()..color = AppColors.primary.withValues(alpha: .012 + band * .006));
    }
  }
  @override
  bool shouldRepaint(_BlueWaves oldDelegate) => oldDelegate.motion != motion;
}
