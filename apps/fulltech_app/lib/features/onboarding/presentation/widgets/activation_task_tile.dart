import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/activation_models.dart';

/// Fila de tarea del panel de activación.
///
/// Compacta a propósito: 44 px cerrada, sin iconos decorativos grandes. Solo
/// el estado, el título y, al desplegar, la explicación y las acciones.
class ActivationTaskTile extends StatelessWidget {
  const ActivationTaskTile({
    super.key,
    required this.task,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onAction,
    required this.onSkip,
    required this.onRestore,
    this.onTour,
    this.isNext = false,
  });

  final ActivationTask task;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onAction;
  final VoidCallback onSkip;
  final VoidCallback onRestore;
  final VoidCallback? onTour;

  /// La tarea que toca hacer ahora: recibe un refuerzo visual discreto.
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final done = task.isDone;
    final skipped = task.isSkipped;

    final titleColor = done
        ? AppColors.primaryDark
        : skipped
        ? AppColors.textMuted
        : AppColors.textPrimary;

    return Container(
      decoration: BoxDecoration(
        // Completada: superficie azul muy claro + check azul. Sin fondos verdes.
        color: done ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: done || skipped ? null : onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      _StatusIcon(task: task),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (skipped)
                        const _Chip(label: 'Omitido', tone: _ChipTone.neutral)
                      else if (isNext && !done)
                        const _Chip(
                          label: 'Siguiente',
                          tone: _ChipTone.accent,
                        ),
                      if (!done && !skipped && task.minutes > 0) ...[
                        const SizedBox(width: 6),
                        _MinutesChip(minutes: task.minutes),
                      ],
                      if (!done && !skipped)
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: (expanded && !done && !skipped)
                      ? _ExpandedBody(
                          task: task,
                          busy: busy,
                          onAction: onAction,
                          onSkip: onSkip,
                          onTour: onTour,
                        )
                      : (skipped
                            ? _SkippedBody(busy: busy, onRestore: onRestore)
                            : const SizedBox(width: double.infinity)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.task,
    required this.busy,
    required this.onAction,
    required this.onSkip,
    required this.onTour,
  });

  final ActivationTask task;
  final bool busy;
  final VoidCallback onAction;
  final VoidCallback onSkip;
  final VoidCallback? onTour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, right: 2, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
          if (task.detail != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    task.detail!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: busy ? null : onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(task.actionLabel),
                ),
              ),
              // La guía lateral está disponible en todas las tareas: se
              // construye con los datos reales de la tarea cuando no existe un
              // recorrido propio, así que no depende del contador del backend.
              if (onTour != null)
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onTour,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                    label: const Text('Ver cómo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.secondaryBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (task.optional)
                SizedBox(
                  height: 32,
                  child: TextButton(
                    onPressed: busy ? null : onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Omitir'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkippedBody extends StatelessWidget {
  const _SkippedBody({required this.busy, required this.onRestore});

  final bool busy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, right: 2, bottom: 2),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'La omitiste. Puedes retomarla cuando quieras.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRestore,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Retomar'),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.task});

  final ActivationTask task;

  @override
  Widget build(BuildContext context) {
    if (task.isDone) {
      return const Icon(
        Icons.check_circle_rounded,
        size: 16,
        color: AppColors.primary,
      );
    }
    final color = task.isSkipped ? AppColors.textMuted : AppColors.primary;
    return Icon(_iconFor(task.icon), size: 16, color: color);
  }

  static IconData _iconFor(String key) {
    switch (key) {
      case 'box':
        return Icons.inventory_2_outlined;
      case 'receipt':
        return Icons.point_of_sale_rounded;
      case 'store':
        return Icons.storefront_outlined;
      case 'percent':
        return Icons.percent_rounded;
      case 'printer':
        return Icons.print_outlined;
      case 'shield':
        return Icons.verified_user_outlined;
      case 'check':
      default:
        return Icons.task_alt_rounded;
    }
  }
}

class _MinutesChip extends StatelessWidget {
  const _MinutesChip({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.schedule_rounded,
          size: 11,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 3),
        Text(
          '$minutes min',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

enum _ChipTone { neutral, accent }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tone});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final background = tone == _ChipTone.accent
        ? AppColors.primarySoft
        : AppColors.surfaceMuted;
    final foreground = tone == _ChipTone.accent
        ? AppColors.primary
        : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: foreground,
        ),
      ),
    );
  }
}
