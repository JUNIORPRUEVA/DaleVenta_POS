import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Bienvenida inicial del onboarding de activación.
///
/// Una sola decisión y un solo botón primario: o empezar, o posponer. No pide
/// datos (los datos de la bienvenida del sitio web ya viven en otro flujo).
class ActivationWelcomeCard extends StatelessWidget {
  const ActivationWelcomeCard({
    super.key,
    required this.companyName,
    required this.remainingTasks,
    required this.onStart,
    required this.onLater,
  });

  final String companyName;
  final int remainingTasks;
  final VoidCallback onStart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width < 460 ? width - 32 : 404.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardWidth),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      // Azul corporativo FullPOS: primary -> primaryDark.
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Bienvenido a FullPOS',
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  remainingTasks <= 1
                      ? 'Solo falta un paso para dejar $companyName listo para vender.'
                      : 'Te acompañamos a dejar $companyName listo para vender en $remainingTasks pasos cortos.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const _Benefit(
                  icon: Icons.bolt_rounded,
                  text: 'Puedes cobrar desde el primer paso.',
                ),
                const SizedBox(height: 8),
                const _Benefit(
                  icon: Icons.tune_rounded,
                  text: 'Omite lo que no uses ahora y retómalo después.',
                ),
                const SizedBox(height: 8),
                const _Benefit(
                  icon: Icons.cloud_done_outlined,
                  text: 'Tu avance queda guardado con tu empresa.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('¡Comencemos!'),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: TextButton(
                    onPressed: onLater,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Ahora no, prefiero explorar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
