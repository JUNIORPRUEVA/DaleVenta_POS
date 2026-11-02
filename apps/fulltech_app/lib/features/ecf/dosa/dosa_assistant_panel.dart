import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ui/flow/ecf_flow_kit.dart';
import 'dosa_assistant_config.dart';
import 'dosa_assistant_events.dart';
import 'dosa_assistant_session.dart';
import 'dosa_wizard_view.dart';

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
    this.onWizardEvent,
    this.onOpenExternally,
  });

  final DosaAssistantConfig config;
  final DosaAssistantSession session;

  /// Solo para pruebas: sustituye el contenedor real.
  final DosaAssistantMountBuilder? mountBuilder;

  /// Reanudar: NO crea una postulación nueva, continúa la existente.
  final VoidCallback? onResume;

  /// Evento del componente oficial. Solo sirve para refrescar desde el backend.
  final ValueChanged<DosaAssistantEvent>? onWizardEvent;

  /// Abrir el asistente en el navegador (Windows, Android, iOS).
  final VoidCallback? onOpenExternally;

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
        return _content(context);
      case DosaAssistantPhase.attention:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfInlineNote(
              text:
                  session.message ??
                  'El contribuyente tiene que completar una acción para '
                      'continuar el proceso.',
              tone: EcfTone.warning,
              icon: Icons.pan_tool_alt_outlined,
            ),
            const SizedBox(height: 8),
            _content(context),
          ],
        );
      case DosaAssistantPhase.originBlocked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EcfInlineNote(
              text:
                  'El navegador no permitió mostrar el asistente dentro de '
                  'esta página. Se puede continuar en una pestaña nueva.',
              tone: EcfTone.warning,
              icon: Icons.open_in_new_rounded,
            ),
            const SizedBox(height: 8),
            _content(context),
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

  /// Contenedor del componente (o su ausencia) según la plataforma.
  ///
  /// Precedencia: si el llamador inyecta un contenedor (pruebas), ese manda.
  /// Si no, en Web/PWA se monta el componente oficial. En Windows, Android e iOS
  /// no hay contenedor: se ofrece abrir el asistente en el navegador.
  Widget _content(BuildContext context) {
    final custom = mountBuilder;
    final Widget? mounted;
    if (custom != null) {
      mounted = custom(context, config);
    } else if (dosaWizardSupported) {
      mounted = buildDosaWizardView(
        config: config,
        height: config.height,
        onEvent: (event) => onWizardEvent?.call(event),
      );
    } else {
      mounted = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mounted != null) mounted,
        if (mounted == null) ...[
          const EcfInlineNote(
            text:
                'El asistente se abre en el navegador. Al terminar, vuelve a '
                'esta pantalla y el progreso se recupera del servidor.',
            tone: EcfTone.pending,
            icon: Icons.open_in_new_rounded,
          ),
          if (onOpenExternally != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onOpenExternally,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Abrir asistente'),
              ),
            ),
          ],
        ],
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

  static String _phaseLabel(DosaAssistantPhase phase) {
    switch (phase) {
      case DosaAssistantPhase.blocked:
        return 'Bloqueado';
      case DosaAssistantPhase.idle:
        return 'Listo para iniciar';
      case DosaAssistantPhase.running:
        return 'En curso';
      case DosaAssistantPhase.attention:
        return 'Requiere tu atención';
      case DosaAssistantPhase.originBlocked:
        return 'Abrir en otra pestaña';
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
      case DosaAssistantPhase.originBlocked:
        return EcfTone.warning;
      case DosaAssistantPhase.idle:
        return EcfTone.pending;
      case DosaAssistantPhase.running:
        return EcfTone.current;
      case DosaAssistantPhase.attention:
        return EcfTone.pending;
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
      case DosaAssistantPhase.attention:
        return Icons.pan_tool_alt_outlined;
      case DosaAssistantPhase.originBlocked:
        return Icons.open_in_new_rounded;
      case DosaAssistantPhase.completed:
        return Icons.check_circle_outline;
      case DosaAssistantPhase.failed:
        return Icons.error_outline_rounded;
    }
  }
}
