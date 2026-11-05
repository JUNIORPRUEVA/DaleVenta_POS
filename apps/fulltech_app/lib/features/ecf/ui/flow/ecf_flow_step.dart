import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'ecf_flow_kit.dart';

/// Pasos del recorrido visual de habilitación.
///
/// Es una agrupación de PRESENTACIÓN: no crea estados nuevos ni sustituye al
/// backend. El paso que se muestra al abrir la pantalla se deduce del expediente
/// real (ver `initialEcfFlowStep`).
enum EcfFlowStep { welcome, preparation, tracking }

extension EcfFlowStepLabels on EcfFlowStep {
  /// Etiqueta corta para la guía de pasos.
  String get railLabel => switch (this) {
    EcfFlowStep.welcome => 'Bienvenida',
    EcfFlowStep.preparation => 'Preparación',
    EcfFlowStep.tracking => 'Tu postulación',
  };
}

/// Paso que corresponde al abrir la pantalla.
///
/// Reglas:
///  * Si la empresa todavía no empezó nada, se empieza por la bienvenida.
///  * Si ya hay expediente, requisitos resueltos o autorización, se entra
///    directamente a la etapa en la que está: nunca se reinicia el recorrido.
///  * Los datos de la empresa y el correo fiscal viven en Preparación, no en un
///    paso separado: el cliente ve un único recorrido de tres etapas.
EcfFlowStep initialEcfFlowStep({
  required String state,
  required bool hasResolvedRequirement,
  required bool officialAuthorization,
  required bool fiscalReady,
  required bool certificateValidated,
  required bool testsOrLater,
  bool dosaOwnsCertificate = false,
}) {
  if (officialAuthorization || testsOrLater) return EcfFlowStep.tracking;
  final started =
      state != 'NOT_STARTED' || hasResolvedRequirement || certificateValidated;
  if (!started) return EcfFlowStep.welcome;
  return EcfFlowStep.preparation;
}

/// Guía de pasos. Vertical en escritorio, en tira horizontal en móvil.
class EcfStepRail extends StatelessWidget {
  const EcfStepRail({
    super.key,
    required this.current,
    required this.onSelect,
    this.horizontal = false,
  });

  final EcfFlowStep current;

  /// Solo se permite volver a un paso anterior; hacia delante manda el flujo.
  final ValueChanged<EcfFlowStep> onSelect;

  final bool horizontal;

  bool _reachable(int index) => index < current.index;

  @override
  Widget build(BuildContext context) {
    return horizontal ? _strip(context) : _rail(context);
  }

  Widget _strip(BuildContext context) {
    // En pantallas estrechas se usa una tira que envuelve: todos los pasos
    // quedan visibles sin desplazamiento horizontal.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final step in EcfFlowStep.values) _chip(context, step)],
      ),
    );
  }

  Widget _chip(BuildContext context, EcfFlowStep step) {
    final index = step.index;
    final currentIndex = current.index;
    final done = index < currentIndex;
    final active = index == currentIndex;
    final reachable = _reachable(index);
    final fg = active || done ? AppColors.primary : AppColors.textMuted;
    return InkWell(
      onTap: reachable && !active ? () => onSelect(step) : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.secondaryBorder : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : active
                  ? Icons.adjust_rounded
                  : Icons.circle_outlined,
              size: 13,
              color: fg,
            ),
            const SizedBox(width: 5),
            Text(
              step.railLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    return EcfSurface(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu recorrido',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          for (final step in EcfFlowStep.values)
            _railRow(context, step, step == EcfFlowStep.values.last),
        ],
      ),
    );
  }

  Widget _railRow(BuildContext context, EcfFlowStep step, bool isLast) {
    final index = step.index;
    final currentIndex = current.index;
    final done = index < currentIndex;
    final active = index == currentIndex;
    final reachable = _reachable(index);
    final style = active
        ? ecfToneStyle(EcfTone.current)
        : done
        ? ecfToneStyle(EcfTone.done)
        : ecfToneStyle(EcfTone.pending);
    return InkWell(
      onTap: reachable && !active ? () => onSelect(step) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Icon(style.icon, size: 16, color: style.fg),
                if (!isLast)
                  Container(
                    width: 1.5,
                    height: 18,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done ? AppColors.primarySoft : AppColors.border,
                  ),
              ],
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  step.railLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active || done
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
