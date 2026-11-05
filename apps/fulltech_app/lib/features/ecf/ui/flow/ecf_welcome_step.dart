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

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 820;
    final left = _WelcomeIntro(
      short: short,
      onStart: onStart,
    );
    final right = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: short ? 520 : 640),
        child: EcfHabilitacionVideoCard(
          videoUrl: videoUrl,
          maxVideoWidth: short ? 500 : 620,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = wide || constraints.maxWidth >= 900;
        return Center(
          child: SingleChildScrollView(
            padding: short
                ? const EdgeInsets.fromLTRB(20, 14, 20, 18)
                : const EdgeInsets.fromLTRB(28, 22, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: left),
                        const SizedBox(width: 40),
                        Expanded(flex: 6, child: right),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        left,
                        const SizedBox(height: 20),
                        right,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Columna izquierda: mensaje, paso a paso y única acción.
///
/// Sin iconos decorativos ni tarjetas anidadas. El orden visual es el mismo que
/// seguirá el cliente al pulsar «Comenzar».
class _WelcomeIntro extends StatelessWidget {
  const _WelcomeIntro({required this.short, required this.onStart});

  final bool short;
  final VoidCallback onStart;

  static const _steps = <(String, String)>[
    (
      'Revisa tus datos',
      'Usamos la información que ya tienes registrada en FullPOS.',
    ),
    (
      'Completa lo que falte',
      'Solo te pediremos el correo fiscal o algún dato obligatorio.',
    ),
    (
      'Inicia la postulación',
      'Continúa el proceso acompañado, sin salir de FullPOS.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FACTURACIÓN ELECTRÓNICA',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Activa tu facturación electrónica',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.16,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Todo el proceso, acompañado por FullPOS y en un solo lugar. '
          'Mira la guía y comienza cuando estés listo.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Paso a paso',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _steps.length; index++)
          _WelcomeStepRow(
            number: index + 1,
            title: _steps[index].$1,
            hint: _steps[index].$2,
            isLast: index == _steps.length - 1,
          ),
        const SizedBox(height: 22),
        SizedBox(
          width: 340,
          child: EcfPrimaryAction(
            label: 'Comenzar',
            icon: Icons.arrow_forward_rounded,
            onPressed: onStart,
            helper: short
                ? null
                : 'Podrás volver al paso anterior cuando quieras.',
          ),
        ),
      ],
    );
  }
}

class _WelcomeStepRow extends StatelessWidget {
  const _WelcomeStepRow({
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Column(
            children: [
              Text(
                number.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.2,
                ),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.only(top: 5, bottom: 2),
                  color: AppColors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11.8,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
