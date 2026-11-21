import 'dart:ui';

import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import '../theme/role_branding.dart';
import '../theme/app_colors.dart';
import '../utils/native_phone_layout.dart';

class FulltechGlobalBackground extends StatelessWidget {
  final AppRole role;
  final bool enableBlurEffects;

  const FulltechGlobalBackground({
    super.key,
    required this.role,
    this.enableBlurEffects = true,
  });

  @override
  Widget build(BuildContext context) {
    if (usesNativePhoneLayout(context)) {
      return const Positioned.fill(
        child: IgnorePointer(child: ColoredBox(color: AppColors.background)),
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final branding = resolveRoleBranding(role);
    final media = MediaQuery.sizeOf(context);

    Color blendOnWhite(Color color, double amount) {
      return Color.lerp(Colors.white, color, amount) ?? Colors.white;
    }

    final top = blendOnWhite(branding.backgroundTop, 0.94);
    final mid = blendOnWhite(branding.backgroundMiddle, 0.98);
    final bottom = blendOnWhite(branding.backgroundBottom, 0.95);

    final blobA = blendOnWhite(branding.glowA, 0.94).withValues(alpha: 0.22);
    final blobB = blendOnWhite(branding.glowB, 0.95).withValues(alpha: 0.18);
    final blobC = blendOnWhite(branding.glowC, 0.95).withValues(alpha: 0.14);
    final watermarkColor = Color.alphaBlend(
      branding.tertiary.withValues(alpha: 0.16),
      cs.onSurface.withValues(alpha: 0.08),
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [top, mid, bottom],
                ),
              ),
            ),
            if (enableBlurEffects) ...[
              _BlurredCircle(
                alignment: const Alignment(-1.15, -1.10),
                diameter: 520,
                color: blobA,
                blurSigma: 120,
              ),
              _BlurredCircle(
                alignment: const Alignment(1.15, -0.70),
                diameter: 420,
                color: blobB,
                blurSigma: 120,
              ),
              _BlurredCircle(
                alignment: const Alignment(0.85, 1.10),
                diameter: 560,
                color: blobC,
                blurSigma: 140,
              ),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.7),
                  radius: 1.25,
                  colors: [
                    cs.surface.withValues(alpha: 0.00),
                    cs.surface.withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: media.height < 680 ? 16 : 28,
              child: Opacity(
                opacity: 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branding.watermarkTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: media.width < 420 ? 36 : 46,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.4,
                        color: watermarkColor.withValues(alpha: 0.16),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      branding.watermarkSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: watermarkColor.withValues(alpha: 0.28),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredCircle extends StatelessWidget {
  const _BlurredCircle({
    required this.alignment,
    required this.diameter,
    required this.color,
    required this.blurSigma,
  });

  final Alignment alignment;
  final double diameter;
  final Color color;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }
}
