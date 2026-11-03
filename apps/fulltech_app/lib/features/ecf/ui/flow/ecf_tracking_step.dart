import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'ecf_flow_kit.dart';

/// Paso «Seguimiento».
///
/// Tres hitos y nada más: Solicitud → Pruebas → Certificación. El detalle de las
/// quince operaciones internas vive en «Detalle técnico», no aquí.
class EcfTrackingStep extends StatelessWidget {
  const EcfTrackingStep({
    super.key,
    required this.milestone,
    required this.official,
    required this.reviewing,
    required this.statusLabel,
    required this.statusMessage,
    required this.percent,
    required this.resolvedCount,
    required this.total,
    required this.nextMessage,
    required this.nextActionLabel,
    required this.onNextAction,
    required this.nextActionEnabled,
    required this.testBadge,
    this.xmlSlot,
    this.detailsBar,
    this.extraSections = const <Widget>[],
    this.wide = true,
  });

  /// Índice del hito actual (0 = Solicitud, 1 = Pruebas, 2 = Certificación).
  final int milestone;

  final bool official;
  final bool reviewing;
  final String statusLabel;
  final String statusMessage;
  final int percent;
  final int resolvedCount;
  final int total;

  /// Qué está haciendo FullPOS y qué toca después.
  final String nextMessage;
  final String nextActionLabel;
  final VoidCallback onNextAction;
  final bool nextActionEnabled;

  /// Distintivo de modo de prueba, si aplica.
  final String? testBadge;

  /// Selector de XML: se inyecta SOLO cuando la etapa lo requiere.
  final Widget? xmlSlot;

  /// Acceso al detalle técnico (solo administradores).
  final Widget? detailsBar;

  /// Secciones adicionales (guía de presentación, evidencias pendientes).
  final List<Widget> extraSections;

  final bool wide;

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
                  title: 'Seguimiento',
                  subtitle: 'Aquí ves en qué punto está tu habilitación.',
                ),
              ),
              if ((testBadge ?? '').isNotEmpty) EcfBadge(label: testBadge!),
            ],
          ),
          const SizedBox(height: 14),
          EcfSection(
            title: 'Tu proceso',
            icon: Icons.route_outlined,
            trailing: Text(
              statusLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Milestones(
                  milestone: milestone,
                  official: official,
                  reviewing: reviewing,
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (percent.clamp(0, 100)) / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  total > 0
                      ? '$resolvedCount de $total comprobaciones · $percent%'
                      : '$percent% completado',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          EcfSection(
            title: 'Ahora',
            icon: Icons.bolt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  statusMessage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  nextMessage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (wide)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 320,
                      child: EcfPrimaryAction(
                        label: nextActionLabel,
                        onPressed: nextActionEnabled ? onNextAction : null,
                      ),
                    ),
                  )
                else
                  EcfPrimaryAction(
                    label: nextActionLabel,
                    onPressed: nextActionEnabled ? onNextAction : null,
                  ),
              ],
            ),
          ),
          if (xmlSlot != null) ...[
            const SizedBox(height: 12),
            EcfSection(
              title: 'XML de postulación',
              icon: Icons.description_outlined,
              subtitle:
                  'Solo cuando la DGII te entrega el archivo de esta etapa.',
              child: xmlSlot!,
            ),
          ],
          for (final section in extraSections) ...[
            const SizedBox(height: 12),
            section,
          ],
          if (detailsBar != null) ...[const SizedBox(height: 12), detailsBar!],
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({
    required this.milestone,
    required this.official,
    required this.reviewing,
  });

  final int milestone;
  final bool official;
  final bool reviewing;

  static const _labels = <String>['Solicitud', 'Pruebas', 'Certificación'];

  EcfTone _tone(int index) {
    if (index < milestone) return EcfTone.done;
    if (index > milestone) return EcfTone.pending;
    if (index == 2 && official) return EcfTone.done;
    return EcfTone.current;
  }

  String _caption(int index) {
    if (index < milestone) return 'Completada';
    if (index > milestone) return 'Pendiente';
    if (index == 2 && official) return 'Completada';
    return reviewing ? 'En revisión' : 'En curso';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < _labels.length; index++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index == 0
                              ? Colors.transparent
                              : _tone(index) == EcfTone.pending
                              ? AppColors.border
                              : AppColors.primarySoft,
                        ),
                      ),
                      Icon(
                        ecfToneStyle(_tone(index)).icon,
                        size: 17,
                        color: ecfToneStyle(_tone(index)).fg,
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index == _labels.length - 1
                              ? Colors.transparent
                              : _tone(index + 1) == EcfTone.pending
                              ? AppColors.border
                              : AppColors.primarySoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _labels[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _tone(index) == EcfTone.current
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: _tone(index) == EcfTone.pending
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _caption(index),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
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
