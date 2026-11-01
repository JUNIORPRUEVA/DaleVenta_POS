import 'package:flutter/material.dart';

import '../../core/offline/sale_attempt_recovery_engine.dart';
import '../../core/theme/app_colors.dart';

/// Estado compacto del motor de recuperación automática.
///
/// Un solo bloque, sin ventanas emergentes: dice qué está haciendo el sistema
/// ahora mismo, cuándo verificó por última vez y cuándo volverá a intentarlo.
class RecoveryStatusCard extends StatelessWidget {
  const RecoveryStatusCard({
    super.key,
    required this.state,
    required this.openIncidents,
    required this.pendingDeclarations,
  });

  final RecoveryEngineState state;
  final int openIncidents;
  final int pendingDeclarations;

  @override
  Widget build(BuildContext context) {
    final visual = _visual();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.running)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(visual.color),
                  ),
                )
              else
                Icon(visual.icon, size: 19, color: visual.color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      visual.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                icon: Icons.schedule_rounded,
                text: state.lastRunAt == null
                    ? 'Aún sin verificar'
                    : 'Última verificación: ${_formatMoment(state.lastRunAt!)}',
              ),
              if (state.waitingForConnection)
                _Chip(
                  icon: Icons.timer_outlined,
                  text: 'Reintento: ${_formatMoment(state.suspendedUntil!)}',
                )
              else if (state.nextRunAt != null)
                _Chip(
                  icon: Icons.timer_outlined,
                  text: 'Próximo intento: ${_formatMoment(state.nextRunAt!)}',
                ),
              if (openIncidents > 0)
                _Chip(
                  icon: Icons.receipt_long_rounded,
                  text: openIncidents == 1
                      ? '1 cobro por confirmar'
                      : '$openIncidents cobros por confirmar',
                ),
              if (pendingDeclarations > 0)
                _Chip(
                  icon: Icons.outbox_rounded,
                  text: pendingDeclarations == 1
                      ? '1 declaración por enviar'
                      : '$pendingDeclarations declaraciones por enviar',
                ),
            ],
          ),
        ],
      ),
    );
  }

  ({IconData icon, Color color, String title, String subtitle}) _visual() {
    if (state.running) {
      return (
        icon: Icons.sync_rounded,
        color: AppColors.primary,
        title: 'Recuperación automática en curso',
        subtitle:
            'Estamos consultando al servidor si alguno de los cobros por '
            'confirmar ya quedó registrado. No se reenvía ningún cobro.',
      );
    }
    if (state.waitingForConnection) {
      return (
        icon: Icons.cloud_off_rounded,
        color: AppColors.warning,
        title: 'Sin conexión con el servidor',
        subtitle:
            'No pudimos verificar los cobros pendientes. Se reintentará solo; '
            'nada se ha dado por cobrado ni por perdido.',
      );
    }
    if (openIncidents == 0 && state.lastOutcome == RecoveryRunOutcome.idle) {
      return (
        icon: Icons.verified_rounded,
        color: AppColors.success,
        title: 'Todo conciliado',
        subtitle:
            'No hay cobros por confirmar en este equipo. La verificación '
            'automática seguirá activa sin hacer consultas innecesarias.',
      );
    }
    if (openIncidents == 0) {
      return (
        icon: Icons.verified_rounded,
        color: AppColors.success,
        title: 'Verificación exitosa',
        subtitle:
            'Los cobros inciertos quedaron conciliados con el servidor y el '
            'aviso se retiró de este equipo.',
      );
    }
    if (state.lastOutcome == RecoveryRunOutcome.partiallyUnreachable ||
        state.consecutiveFailures > 0) {
      return (
        icon: Icons.cloud_off_rounded,
        color: AppColors.warning,
        title: 'Sin conexión con el servidor',
        subtitle:
            'Quedan cobros por confirmar y el servidor no respondió. Se '
            'reintentará automáticamente; no hace falta que hagas nada.',
      );
    }
    return (
      icon: Icons.report_problem_rounded,
      color: AppColors.warning,
      title: 'Requiere intervención',
      subtitle:
          'Estos cobros no se pueden resolver con evidencia concluyente. '
          'Revisa cada caso y decide con la evidencia que tengas.',
    );
  }

  static String _formatMoment(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
