import 'package:flutter/material.dart';

import '../../../../core/support/support_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/safe_url_launcher.dart';

/// Optional assistance; opening WhatsApp never starts the fiscal process.
class EcfManagedSetupOffer extends StatelessWidget {
  const EcfManagedSetupOffer({super.key, this.onContact});

  final VoidCallback? onContact;

  static const message =
      'Hola, me interesa el servicio de FullPOS para que hagan por mí el '
      'proceso de postulación y configuración de facturación electrónica, '
      'con un pago único de US\$150. Quisiera conocer cómo comenzar.';

  static Uri get contactUri => SupportConfig.whatsappUri(message);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: 0.65 + value * 0.35,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 6),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextButton(
          onPressed: onContact ?? () => safeOpenWhatsApp(context, contactUri),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.support_agent_outlined, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿Prefieres que lo hagamos por ti?',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nos encargamos del proceso · Pago único de US\$150',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Consultar por WhatsApp',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_outward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
