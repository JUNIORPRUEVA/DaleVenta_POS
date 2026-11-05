import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'ecf_flow_kit.dart';

/// Seguimiento del cliente cuando la postulación se completa en DOSA.
///
/// No repite pruebas ni certificación: solo muestra las tres etapas del proceso
/// y la acción real para continuar en el portal oficial.
class EcfDosaTrackingStep extends StatelessWidget {
  const EcfDosaTrackingStep({
    super.key,
    required this.milestone,
    required this.statusLabel,
    required this.statusMessage,
    required this.official,
    this.portal,
    this.advanced,
  });

  /// 0 = Solicitud, 1 = Pruebas, 2 = Certificación.
  final int milestone;
  final String statusLabel;
  final String statusMessage;
  final bool official;
  final Widget? portal;
  final Widget? advanced;

  static const _labels = ['Solicitud', 'Pruebas', 'Certificación'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: EcfStepTitle(
                  title: 'Tu postulación',
                  subtitle:
                      'Continúa el proceso en el asistente oficial de DOSA.',
                ),
              ),
              EcfBadge(
                label: statusLabel,
                tone: official ? EcfTone.done : EcfTone.current,
                icon: official
                    ? Icons.check_circle_outline_rounded
                    : Icons.timelapse_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DosaStageIndicator(
            labels: _labels,
            milestone: milestone,
            official: official,
          ),
          const SizedBox(height: 10),
          Text(
            statusMessage,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (portal != null) ...[
            const SizedBox(height: 12),
            portal!,
          ],
          if (advanced != null) ...[
            const SizedBox(height: 12),
            advanced!,
          ],
        ],
      ),
    );
  }
}

/// Indicador compacto de las tres etapas.
///
/// No duplica el estado con iconos y subtítulos: el badge superior y el texto
/// de estado ya explican qué ocurre. Aquí solo se marca el avance.
class _DosaStageIndicator extends StatelessWidget {
  const _DosaStageIndicator({
    required this.labels,
    required this.milestone,
    required this.official,
  });

  final List<String> labels;
  final int milestone;
  final bool official;

  EcfTone _tone(int index) {
    if (index < milestone) return EcfTone.done;
    if (index > milestone) return EcfTone.pending;
    if (index == 2 && official) return EcfTone.done;
    return EcfTone.current;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: ecfToneStyle(_tone(index)).fg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: _tone(index) == EcfTone.current
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: _tone(index) == EcfTone.pending
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
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
