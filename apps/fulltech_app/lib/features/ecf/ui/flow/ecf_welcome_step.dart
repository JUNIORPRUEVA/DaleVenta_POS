import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../ecf_habilitacion_video_card.dart';
import 'ecf_flow_kit.dart';

/// Pantalla de bienvenida del módulo e-CF.
///
/// Es lo primero que ve un cliente que aún no ha empezado. No muestra estados
/// internos, requisitos técnicos, XML, evidencias ni configuraciones: solo qué
/// va a pasar, qué necesita tener a mano y un único botón para empezar.
class EcfWelcomeStep extends StatelessWidget {
  const EcfWelcomeStep({
    super.key,
    required this.videoUrl,
    required this.onStart,
    this.wide = false,
  });

  /// URL del tutorial servida por el API. Puede llegar vacía.
  final String videoUrl;

  final VoidCallback onStart;

  /// En escritorio los dos bloques van en paralelo para que la portada quepa
  /// sin desplazamiento.
  final bool wide;

  static const _requirements = <(String, String)>[
    (
      'Acceso al Portal de Certificación de la DGII',
      'El usuario con el que tu representante entra al portal oficial.',
    ),
    (
      'Certificado digital vigente',
      'El archivo .pfx o .p12 del representante legal y su contraseña.',
    ),
    (
      'Datos fiscales de la empresa',
      'RNC, razón social, dirección y representante autorizado.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // En ventanas bajas (portátiles, Windows con DPI alto) el vídeo se reduce
    // para que el botón principal quede siempre a la vista.
    final short = MediaQuery.sizeOf(context).height < 820;
    final requirements = EcfSection(
      title: 'Lo que necesitas',
      icon: Icons.checklist_rounded,
      subtitle: 'Se consigue una sola vez, antes de empezar.',
      child: Column(
        children: [
          for (var index = 0; index < _requirements.length; index++)
            _Requirement(
              number: index + 1,
              title: _requirements[index].$1,
              hint: _requirements[index].$2,
              isLast: index == _requirements.length - 1,
            ),
        ],
      ),
    );
    final preparation = EcfSection(
      title: 'Cómo prepararte',
      icon: Icons.play_circle_outline_rounded,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: short ? 270 : 380),
          child: EcfHabilitacionVideoCard(videoUrl: videoUrl),
        ),
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: short
            ? const EdgeInsets.fromLTRB(16, 8, 16, 12)
            : const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 900 : 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.secondaryBorder),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    size: 23,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Activa tu facturación electrónica',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Te acompañamos durante el proceso de habilitación ante la '
                'DGII, paso a paso y de forma sencilla.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: requirements),
                    const SizedBox(width: 12),
                    Expanded(child: preparation),
                  ],
                )
              else ...[
                requirements,
                const SizedBox(height: 12),
                preparation,
              ],
              const SizedBox(height: 10),
              EcfPrimaryAction(
                label: 'Comenzar',
                icon: Icons.arrow_forward_rounded,
                onPressed: onStart,
                helper: short
                    ? null
                    : 'Podrás volver al paso anterior cuando quieras.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.number,
    required this.title,
    required this.hint,
    required this.isLast,
  });

  final int number;
  final String title;
  final String hint;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.secondaryBorder),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
