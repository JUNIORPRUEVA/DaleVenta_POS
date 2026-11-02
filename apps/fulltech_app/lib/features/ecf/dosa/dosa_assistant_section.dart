import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import 'dosa_assistant_config.dart';
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
    this.config,
  });

  /// Referencia externa del expediente, si ya existe.
  final String? postulationExternalId;

  /// Fase observada. Por defecto se deduce de si hay expediente externo.
  final DosaAssistantPhase? phase;

  final VoidCallback? onResume;

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
    );
  }

  /// Sin señal del proveedor no se inventa un estado: como mucho "en curso".
  static DosaAssistantPhase _defaultPhase(String? externalId) =>
      externalId == null || externalId.trim().isEmpty
      ? DosaAssistantPhase.idle
      : DosaAssistantPhase.running;
}
