import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _intro;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _intro = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.62, curve: Curves.easeOutCubic),
    );
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560 || size.height < 680;
    final logoSize = compact ? 82.0 : 104.0;
    final ringSize = compact ? 136.0 : 168.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SplashBackground(),
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final introValue = _intro.value;
                  final scale = 0.94 + (introValue * 0.06);
                  return Opacity(
                    opacity: introValue.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - introValue) * 18),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: ringSize,
                          height: ringSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _controller,
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: Size.square(ringSize),
                                    painter: _StartupRingPainter(
                                      progress: _controller.value,
                                    ),
                                  );
                                },
                              ),
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, child) {
                                  final scale =
                                      0.985 +
                                      (math.sin(_pulse.value * math.pi) * 0.03);
                                  return Transform.scale(
                                    scale: scale,
                                    child: child,
                                  );
                                },
                                child: _LogoMark(size: logoSize),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 16 : 20),
                        const Text(
                          'FullPOS Cloud',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          auth.restoringSession
                              ? 'Restaurando sesión'
                              : 'Preparando tu punto de venta',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 18),
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) {
                            return CustomPaint(
                              size: const Size(170, 4),
                              painter: _LoadingTrackPainter(
                                progress: _controller.value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241D4ED8),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.16),
        child: Image.asset(
          'assets/image/logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.storefront_rounded,
              color: Color(0xFF2563EB),
              size: 58,
            );
          },
        ),
      ),
    );
  }
}

class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC), Color(0xFFF7FEE7)],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: CustomPaint(painter: _BackgroundLinesPainter()),
    );
  }
}

class _StartupRingPainter extends CustomPainter {
  const _StartupRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final arcPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0x002563EB),
          Color(0xFF2563EB),
          Color(0xFF14B8A6),
          Color(0x002563EB),
        ],
        stops: [0.0, 0.46, 0.78, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;
    final tickPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - 1, basePaint);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.42, false, arcPaint);
    canvas.restore();

    for (var i = 0; i < 20; i++) {
      final angle = (math.pi * 2 / 20) * i + (progress * math.pi * 0.8);
      final start = Offset(
        center.dx + math.cos(angle) * (radius - 16),
        center.dy + math.sin(angle) * (radius - 16),
      );
      final end = Offset(
        center.dx + math.cos(angle) * (radius - 10),
        center.dy + math.sin(angle) * (radius - 10),
      );
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StartupRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LoadingTrackPainter extends CustomPainter {
  const _LoadingTrackPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(trackRect, Paint()..color = const Color(0xFFE2E8F0));

    final segmentWidth = size.width * 0.38;
    final x = (size.width + segmentWidth) * progress - segmentWidth;
    final segment = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 0, segmentWidth, size.height),
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(segment, paint);
  }

  @override
  bool shouldRepaint(covariant _LoadingTrackPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _BackgroundLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1D4ED8).withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.18 + (i * 0.105));
      final path = Path()
        ..moveTo(-30, y)
        ..cubicTo(
          size.width * 0.28,
          y - 34,
          size.width * 0.62,
          y + 34,
          size.width + 30,
          y - 8,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundLinesPainter oldDelegate) => false;
}
