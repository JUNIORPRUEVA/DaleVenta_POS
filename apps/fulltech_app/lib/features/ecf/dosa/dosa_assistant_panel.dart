import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ui/flow/ecf_flow_kit.dart';
import 'dosa_assistant_config.dart';
import 'dosa_assistant_session.dart';

/// Constructor del contenedor real del componente oficial.
///
/// Lo implementa la capa de plataforma (hoy no existe para ninguna: ver
/// `docs/ECF_DOSA_ASSISTANT_EMBEDDING.md`). El panel NO inyecta el script por su
/// cuenta: recibe el widget ya montado. Así el mismo panel sirve en Web/PWA,
/// Windows, Android e iOS sin que la UI sepa cómo se embebe.
typedef DosaAssistantMountBuilder =
    Widget Function(BuildContext context, DosaAssistantConfig config);

/// Adaptador visual del asistente DOSA dentro del expediente existente.
///
/// No crea un asistente nuevo: es una sección más del recorrido de Postulación
/// Inteligente, con el mismo lenguaje visual (`EcfSection` + `EcfInlineNote`).
///
/// Garantías:
/// * Con la bandera apagada el panel no se pinta (la pantalla decide no
///   incluirlo), así que la experiencia actual no cambia.
/// * Aunque se pinte, **no carga el script** ni inicia nada: solo muestra el
///   estado y, si el contrato estuviera completo, el hueco donde montar.
/// * "Finalizado por el proveedor" nunca se presenta como autorización fiscal.
class DosaAssistantPanel extends StatelessWidget {
  const DosaAssistantPanel({
    super.key,
    required this.config,
    required this.session,
    this.mountBuilder,
    this.onResume,
  });

  final DosaAssistantConfig config;
  final DosaAssistantSession session;

  /// Solo se usa cuando `config.canMount` y el contrato están completos.
  final DosaAssistantMountBuilder? mountBuilder;

  /// Reanudar: NO crea una postulación nueva, continúa la existente.
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final phase = config.canMount ? session.phase : DosaAssistantPhase.blocked;
    return EcfSection(
      title: 'Asistente de certificación DOSA',
      icon: Icons.auto_awesome_outlined,
      subtitle:
          'Proceso oficial del proveedor. Complementa el expediente; no lo '
          'sustituye ni autoriza emisión.',
      trailing: EcfBadge(
        label: _phaseLabel(phase),
        tone: _phaseTone(phase),
        icon: _phaseIcon(phase),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!config.canMount) ...[
            EcfInlineNote(
              text: config.blockedMessage,
              tone: EcfTone.warning,
              icon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 8),
            _boundIdentity(context),
          ] else
            _mountOrState(context, phase),
        ],
      ),
    );
  }

  Widget _mountOrState(BuildContext context, DosaAssistantPhase phase) {
    switch (phase) {
      case DosaAssistantPhase.blocked:
        return EcfInlineNote(
          text: config.blockedMessage,
          tone: EcfTone.warning,
          icon: Icons.lock_outline_rounded,
        );
      case DosaAssistantPhase.idle:
      case DosaAssistantPhase.running:
        final mount = mountBuilder;
        if (mount == null) {
          // Contrato completo pero sin contenedor de plataforma: se dice, no se
          // simula un asistente que no existe.
          return const EcfInlineNote(
            text:
                'Falta el contenedor de plataforma para mostrar el componente '
                'oficial en este dispositivo.',
            tone: EcfTone.pending,
            icon: Icons.devices_other_outlined,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 360, child: mount(context, config)),
            if (onResume != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onResume,
                  child: const Text('Reanudar proceso'),
                ),
              ),
            ],
          ],
        );
      case DosaAssistantPhase.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfInlineNote(
              text:
                  session.message ??
                  'El proveedor reportó la finalización del proceso. Esto NO '
                      'autoriza emisión: falta la autorización fiscal.',
              tone: EcfTone.done,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 8),
            _boundIdentity(context),
          ],
        );
      case DosaAssistantPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfInlineNote(
              text:
                  session.message ??
                  'El proceso se detuvo. Se puede reanudar sin crear otra '
                      'postulación.',
              tone: EcfTone.warning,
              icon: Icons.error_outline_rounded,
            ),
            if (onResume != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onResume,
                  child: const Text('Reanudar proceso'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _boundIdentity(context),
          ],
        );
    }
  }

  /// Vinculación visible: empresa + RNC + postulación. Es lo que impide que el
  /// administrador no sepa con qué identidad fiscal está trabajando.
  Widget _boundIdentity(BuildContext context) {
    final theme = Theme.of(context);
    final binding = session.binding;
    final external = binding.postulationExternalId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vinculado a ${binding.taxId.trim().isEmpty ? 'sin RNC' : binding.taxId}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          external == null
              ? 'Postulación: sin iniciar'
              : 'Postulación: $external',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: AppColors.textMuted,
          ),
        ),
        if (session.errorCode != null) ...[
          const SizedBox(height: 2),
          Text(
            'Código: ${session.errorCode}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  static String _phaseLabel(DosaAssistantPhase phase) {
    switch (phase) {
      case DosaAssistantPhase.blocked:
        return 'Bloqueado';
      case DosaAssistantPhase.idle:
        return 'Listo para iniciar';
      case DosaAssistantPhase.running:
        return 'En curso';
      case DosaAssistantPhase.completed:
        return 'Finalizado por el proveedor';
      case DosaAssistantPhase.failed:
        return 'Con error';
    }
  }

  static EcfTone _phaseTone(DosaAssistantPhase phase) {
    switch (phase) {
      case DosaAssistantPhase.blocked:
      case DosaAssistantPhase.failed:
        return EcfTone.warning;
      case DosaAssistantPhase.idle:
        return EcfTone.pending;
      case DosaAssistantPhase.running:
        return EcfTone.current;
      case DosaAssistantPhase.completed:
        return EcfTone.done;
    }
  }

  static IconData _phaseIcon(DosaAssistantPhase phase) {
    switch (phase) {
      case DosaAssistantPhase.blocked:
        return Icons.lock_outline_rounded;
      case DosaAssistantPhase.idle:
        return Icons.play_circle_outline;
      case DosaAssistantPhase.running:
        return Icons.sync_rounded;
      case DosaAssistantPhase.completed:
        return Icons.check_circle_outline;
      case DosaAssistantPhase.failed:
        return Icons.error_outline_rounded;
    }
  }
}
