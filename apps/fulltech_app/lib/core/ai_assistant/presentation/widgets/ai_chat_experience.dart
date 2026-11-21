import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'ai_assistant_dock_button.dart';

class AiChatWelcome extends StatelessWidget {
  const AiChatWelcome({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 88, height: 88, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(6)),
        child: Image.asset(AiAssistantDockButton.imageAsset, excludeFromSemantics: true)),
      const SizedBox(height: 24),
      Text('Hola, soy FullPOS IA', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700, color: AppColors.primaryDark, letterSpacing: -.5)),
      const SizedBox(height: 12),
      Text('Te ayudo a usar FullPOS, resolver dudas y encontrar el siguiente paso para tu negocio.',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.65, color: AppColors.textSecondary)),
      const SizedBox(height: 20),
      Text('Cuéntame qué necesitas hacer.', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
    ]),
  );
}

class AiTypingBubble extends StatefulWidget {
  const AiTypingBubble({super.key});
  @override
  State<AiTypingBubble> createState() => _TypingBubbleState();
}
class _TypingBubbleState extends State<AiTypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { _motion.stop(); }
    else if (!_motion.isAnimating) { _motion.repeat(); }
  }
  @override
  void dispose() { _motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'FullPOS IA está escribiendo', liveRegion: true,
    child: Align(alignment: Alignment.centerLeft, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface,
        border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(animation: _motion, builder: (_, child) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final pulse = (math.sin(_motion.value * math.pi * 2 - i * .8) + 1) / 2;
            return Transform.translate(offset: Offset(0, -3 * pulse), child: Container(
              width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .3 + pulse * .7),
                shape: BoxShape.circle)));
          }),
        )),
        const SizedBox(width: 8),
        Text('Preparando tu respuesta', style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary)),
      ]),
    )),
  );
}
