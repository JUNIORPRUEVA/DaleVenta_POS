import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';

/// Onboarding fiscal de la EMPRESA, dentro de Configuración de Empresa.
///
/// Muestra el avance real que reporta el backend (pasos, bloqueos y resultado) y
/// permite marcar los pasos que el usuario puede gestionar. Es deliberadamente
/// conservador:
///
///  * **Nunca** presenta una empresa como certificada ante la DGII. Los estados
///    que devuelve son INTERNOS del proceso administrativo; la certificación es
///    un acto de la DGII y no se deduce de haber completado una pantalla.
///  * La emisión real sigue bloqueada por su propia compuerta (`productionEnabled`
///    + estado de certificación), no por esta lista.
///  * Solo aparece cuando la empresa tiene la facturación electrónica activada y
///    el usuario puede ver la configuración e-CF.
class EcfOnboardingSection extends ConsumerStatefulWidget {
  const EcfOnboardingSection({super.key});

  @override
  ConsumerState<EcfOnboardingSection> createState() =>
      _EcfOnboardingSectionState();
}

class _EcfOnboardingSectionState extends ConsumerState<EcfOnboardingSection> {
  bool _busy = false;
  String? _error;

  Future<void> _refresh() async {
    ref.invalidate(ecfOnboardingProvider);
    await ref.read(ecfOnboardingProvider.future);
  }

  Future<void> _markStep(EcfOnboardingStepView step, String status) async {
    if (_busy) return; // protección contra doble pulsación
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ecfRepositoryProvider)
          .updateOnboardingStep(stepKey: step.stepKey, status: status);
      ref.invalidate(ecfOnboardingProvider);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo actualizar el paso. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ecfEnabled =
        ref.watch(companySettingsProvider).valueOrNull?.ecfEnabled ?? false;
    if (!ecfEnabled) return const SizedBox.shrink();
    if (!hasUserPermission(
      ref.watch(authStateProvider).user,
      AppPermission.manageEcfConfig,
    )) {
      return const SizedBox.shrink();
    }

    final canManage = hasUserPermission(
      ref.watch(authStateProvider).user,
      AppPermission.manageEcfConfig,
    );
    final onboarding = ref.watch(ecfOnboardingProvider);

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: onboarding.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Row(
            children: [
              Expanded(
                child: Text(
                  'No se pudo cargar el proceso de habilitación.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(onPressed: _refresh, child: const Text('Reintentar')),
            ],
          ),
          data: (view) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Habilitación e-CF', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Proceso INTERNO de preparación. Completar estos pasos no '
                'acredita certificación ante la DGII: eso depende de la DGII y de '
                'la autorización expresa.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: view.progress,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(view.progress * 100).round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Estado de habilitación: ${view.certificationStatus}'
                '${view.productionEnabled ? ' · emisión productiva marcada' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              if (view.steps.isEmpty)
                Text(
                  'El backend todavía no ha creado los pasos de esta empresa.',
                  style: theme.textTheme.bodySmall,
                ),
              for (final step in view.steps) _StepRow(step: step),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (canManage && view.steps.any((s) => s.canComplete)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final step in view.steps)
                      if (step.canComplete)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _markStep(step, 'COMPLETED'),
                          child: Text('Marcar ${step.label}'),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _stepIcon(EcfOnboardingStepView step) => step.isDone
    ? Icons.check_circle
    : step.isBlocked
    ? Icons.block
    : Icons.radio_button_unchecked;

Color _stepColor(EcfOnboardingStepView step, ColorScheme scheme) =>
    step.isBlocked
    ? scheme.error
    : step.isDone
    ? const Color(0xFF1B7F3B)
    : scheme.outline;

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final EcfOnboardingStepView step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _stepIcon(step),
            size: 18,
            color: _stepColor(step, theme.colorScheme),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${step.label} · ${step.status}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (step.blockedReason != null && step.blockedReason!.isNotEmpty)
                  Text(
                    'Bloqueado: ${step.blockedReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                else if (step.resultSummary != null &&
                    step.resultSummary!.isNotEmpty)
                  Text(step.resultSummary!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
