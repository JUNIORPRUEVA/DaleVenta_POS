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

    return DosaAssistantPanel(
      config: resolved,
      session: DosaAssistantSession(
        binding: binding,
        phase: phase ?? _defaultPhase(postulationExternalId),
      ),
      onResume: onResume,
      // Un evento del navegador NO escribe nada: solo pide recargar del backend.
      onWizardEvent: _onWizardEvent(ref),
      onOpenExternally: resolved.hasSessionUrl
          ? () => openDosaAssistantExternally(sessionUrl: resolved.sessionUrl!)
          : null,
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
