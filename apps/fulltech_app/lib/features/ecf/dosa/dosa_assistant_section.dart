import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../data/ecf_repository.dart';
import 'dosa_assistant_config.dart';
import 'dosa_assistant_events.dart';
import 'dosa_assistant_launcher.dart';
import 'dosa_assistant_panel.dart';
import 'dosa_assistant_session.dart';
import 'dosa_certification_intent_api.dart';

/// Inserta el panel del asistente DOSA dentro del expediente existente.
///
/// Es el único punto que lee la identidad fiscal de la empresa: el RNC sale de
/// la configuración confirmada por el backend, nunca de un campo del asistente.
///
/// Con la bandera apagada devuelve `SizedBox.shrink()`: la pantalla actual no
/// cambia en absoluto para las empresas que no usan e-CF.
class DosaAssistantSection extends ConsumerWidget {
  const DosaAssistantSection({
    super.key,
    this.postulationExternalId,
    this.phase,
    this.onResume,
    this.onRefresh,
    this.config,
  });

  /// Referencia externa del expediente, si ya existe.
  final String? postulationExternalId;

  /// Fase observada. Por defecto se deduce de si hay expediente externo.
  final DosaAssistantPhase? phase;

  final VoidCallback? onResume;

  /// Recarga la pantalla que contiene la sección tras un evento del componente.
  final VoidCallback? onRefresh;

  /// Solo para pruebas; en la app se lee del build.
  final DosaAssistantConfig? config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = config ?? DosaAssistantConfig.fromEnvironment();
    if (!resolved.enabled) return const SizedBox.shrink();

    final companyId =
        ref.watch(authStateProvider).user?.companyId?.trim() ?? '';
    final taxId = ref.watch(companySettingsProvider).valueOrNull?.rnc.trim() ?? '';

    final binding = DosaAssistantBinding(
      companyId: companyId,
      taxId: taxId,
      postulationExternalId: postulationExternalId,
    );

    // El asistente NO se monta hasta que el backend confirma la intención. Esta
    // es la unica forma de que la empresa quede asociada a su RNC verificado
    // antes de que DOSA emita ningun evento.
    final intent = ref.watch(dosaIntentRegistrationProvider(taxId));

    return intent.when(
      loading: () => const _DosaIntentGate(
        icon: Icons.hourglass_top,
        message: 'Registrando la preparacion de facturacion electronica...',
      ),
      error: (error, _) => _DosaIntentGate(
        icon: Icons.block,
        message: error is DosaIntentException
            ? error.message
            : 'No se pudo registrar la intencion de certificacion.',
        // Solo se muestra como detalle un codigo propio del dominio: los
        // errores de transporte no aportan nada al administrador.
        detail: error is DosaIntentException &&
                (error.code.startsWith('ECF_') ||
                    error.code == 'AMBIGUOUS_RNC' ||
                    error.code == 'COMPANY_RNC_NOT_VERIFIED' ||
                    error.code == 'RNC_DOES_NOT_MATCH_COMPANY_IDENTITY' ||
                    error.code == 'SESSION_CLAIM_FAILED')
            ? error.code
            : null,
        onRetry: () => ref.invalidate(dosaIntentRegistrationProvider(taxId)),
      ),
      data: (registered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DosaIntentBanner(
            attemptNo: registered.attemptNo,
            created: registered.created,
            provider: registered.provider,
            onRefreshState: () => ref.invalidate(dosaIntentStateProvider),
          ),
          DosaAssistantPanel(
            config: resolved,
            session: DosaAssistantSession(
              binding: binding,
              phase: phase ?? _defaultPhase(postulationExternalId),
            ),
            onResume: onResume,
            // Un evento del navegador NO escribe nada: solo pide recargar.
            onWizardEvent: _onWizardEvent(ref),
            onOpenExternally: resolved.hasSessionUrl
                ? () => openDosaAssistantExternally(
                    sessionUrl: resolved.sessionUrl!,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  ValueChanged<DosaAssistantEvent> _onWizardEvent(WidgetRef ref) {
    return (event) {
      // Doble cinturón: aunque el evento llegue con forma válida, aquí no se
      // crea ninguna postulación ni se marca aceptación fiscal.
      if (mayMutateFiscalState(event)) return;
      if (!event.impliesRefresh) return;
      ref.invalidate(ecfOnboardingProvider);
      onRefresh?.call();
    };
  }

  /// Sin señal del proveedor no se inventa un estado: como mucho "en curso".
  static DosaAssistantPhase _defaultPhase(String? externalId) =>
      externalId == null || externalId.trim().isEmpty
      ? DosaAssistantPhase.idle
      : DosaAssistantPhase.running;
}

/// Estado previo al asistente: mientras la intención no esté registrada, DOSA
/// no se monta. Si falla, se explica el motivo y no se abre nada.
class _DosaIntentGate extends StatelessWidget {
  const _DosaIntentGate({
    required this.icon,
    required this.message,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: theme.textTheme.bodyMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra informativa con el estado interno de la preparación.
///
/// Solo muestra identificadores y estados: ni claves, ni credenciales, ni nada
/// que el administrador no deba ver.
class _DosaIntentBanner extends ConsumerWidget {
  const _DosaIntentBanner({
    required this.attemptNo,
    required this.created,
    required this.provider,
    required this.onRefreshState,
  });

  final int attemptNo;
  final bool created;
  final String provider;
  final VoidCallback onRefreshState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(dosaIntentStateProvider);

    final parts = <String>[
      'Intento $attemptNo',
      created ? 'registrado ahora' : 'ya estaba registrado',
      'proveedor $provider',
    ];

    state.whenData((value) {
      if (value.sessionStatus != null) {
        parts.add('sesion ${value.sessionStatus}');
      }
      if (value.credentialStatus != null) {
        parts.add('credencial ${value.credentialStatus}');
      }
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' \u00b7 '),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onRefreshState,
            child: const Text('Actualizar estado'),
          ),
        ],
      ),
    );
  }
}
